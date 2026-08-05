setup() {
  source "${BATS_TEST_DIRNAME}/../lib/log.sh"
  source "${BATS_TEST_DIRNAME}/../lib/slack.sh"

  INCIDENT_DIR="$(mktemp -d)/20260731T090700Z-block-lag"
  mkdir -p "$INCIDENT_DIR"
  CURL_LOG="$(mktemp)"
  export CURL_LOG
  export SLACK_WEBHOOK_URL="https://hooks.slack.test/services/T000/B000/XXX"
}

teardown() {
  rm -rf "$(dirname "$INCIDENT_DIR")"
  rm -f "$CURL_LOG"
  unset SLACK_WEBHOOK_URL FAKE_CURL_HTTP_CODE FAKE_CURL_EXIT
}

# Records every invocation (one line: all args) and the --data payload to
# CURL_LOG, then prints FAKE_CURL_HTTP_CODE (default 200) like the real
# curl's -w '%{http_code}' would.
curl() {
  local arg data="" grab=""
  for arg in "$@"; do
    [[ "$grab" == "data" ]] && { data="$arg"; grab=""; }
    [[ "$arg" == "--data" ]] && grab="data"
  done
  printf '%s\n' "$*" >> "$CURL_LOG"
  printf 'PAYLOAD %s\n' "$data" >> "$CURL_LOG"
  if [[ -n "${FAKE_CURL_EXIT:-}" ]]; then return "$FAKE_CURL_EXIT"; fi
  printf '%s' "${FAKE_CURL_HTTP_CODE:-200}"
}
export -f curl

write_manifest() {
  cat > "$INCIDENT_DIR/manifest.json"
}

@test "slack_notify_incident posts a summary with the incident id, node, and S3 URI" {
  write_manifest <<'EOF'
{"incident_id":"20260731T090700Z-block-lag","node":"node-a","chain":"stable","trigger":"block_lag","triggered_at":"2026-07-31T07:47:00Z","artifacts":{"cpu_profile":"ok"},"errors":[],"warnings":[]}
EOF
  echo "s3://bucket/node-recorder/stable/node-a/20260731T090700Z-block-lag.tar.gz" > "$INCIDENT_DIR/.uploaded"

  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 0 ]

  grep -q "$SLACK_WEBHOOK_URL" "$CURL_LOG"
  payload="$(grep '^PAYLOAD ' "$CURL_LOG" | sed 's/^PAYLOAD //')"
  text="$(jq -r '.text' <<<"$payload")"
  [[ "$text" == *"20260731T090700Z-block-lag"* ]]
  [[ "$text" == *"node node-a chain stable"* ]]
  [[ "$text" == *"cpu_profile=ok"* ]]
  [[ "$text" == *"uploaded: s3://bucket/node-recorder/stable/node-a/20260731T090700Z-block-lag.tar.gz"* ]]
}

@test "slack_notify_incident marks a pending upload and includes errors and warnings" {
  write_manifest <<'EOF'
{"incident_id":"20260731T090700Z-block-lag","node":"node-a","chain":"stable","trigger":"block_lag","triggered_at":"2026-07-31T07:47:00Z","artifacts":{"cpu_profile":"error"},"errors":["cpu_profile: timeout"],"warnings":["haproxy_log: truncated"]}
EOF
  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 0 ]

  payload="$(grep '^PAYLOAD ' "$CURL_LOG" | sed 's/^PAYLOAD //')"
  text="$(jq -r '.text' <<<"$payload")"
  [[ "$text" == *"errors: cpu_profile: timeout"* ]]
  [[ "$text" == *"warnings: haproxy_log: truncated"* ]]
  [[ "$text" == *"upload PENDING - bundle kept at ${INCIDENT_DIR}"* ]]
}

@test "slack_notify_incident skips with 0 and no POST when the webhook URL is not set" {
  unset SLACK_WEBHOOK_URL

  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not configured"* ]]
  [ ! -s "$CURL_LOG" ]
}

@test "slack_notify_incident still notifies when the manifest is missing" {
  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 0 ]

  payload="$(grep '^PAYLOAD ' "$CURL_LOG" | sed 's/^PAYLOAD //')"
  text="$(jq -r '.text' <<<"$payload")"
  [[ "$text" == *"manifest missing or unreadable"* ]]
}

@test "slack_notify_incident returns 1 on a transport failure" {
  export FAKE_CURL_EXIT=7

  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 1 ]
}

@test "slack_notify_incident returns 1 on a non-200 response" {
  export FAKE_CURL_HTTP_CODE=500

  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 1 ]
}

@test "slack_notify_incident still notifies when the manifest is corrupt JSON" {
  echo "not json at all" > "$INCIDENT_DIR/manifest.json"

  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 0 ]

  payload="$(grep '^PAYLOAD ' "$CURL_LOG" | sed 's/^PAYLOAD //')"
  text="$(jq -r '.text' <<<"$payload")"
  [[ "$text" == *"manifest missing or unreadable"* ]]
  [[ "$text" == *"upload PENDING"* ]]
}
