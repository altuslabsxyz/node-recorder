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
  [ "$(jq -r 'has("text")' <<<"$payload")" = "false" ]
  blocks="$(jq -r '.attachments[0].blocks' <<<"$payload")"
  [[ "$blocks" == *"20260731T090700Z-block-lag"* ]]
  [[ "$blocks" == *"node-a (stable)"* ]]
  [[ "$blocks" == *"cpu_profile"* ]]
  [[ "$(jq -r '.attachments[0].blocks[-1].elements[0].text' <<<"$payload")" == *"s3://bucket/node-recorder/stable/node-a/20260731T090700Z-block-lag.tar.gz"* ]]
  [[ "$(jq -r '.attachments[0].fallback' <<<"$payload")" == *"1/1 artifacts ok"* ]]
}

@test "slack_notify_incident marks a pending upload and includes errors and warnings" {
  write_manifest <<'EOF'
{"incident_id":"20260731T090700Z-block-lag","node":"node-a","chain":"stable","trigger":"block_lag","triggered_at":"2026-07-31T07:47:00Z","artifacts":{"cpu_profile":"error"},"errors":["cpu_profile: timeout"],"warnings":["haproxy_log: truncated"]}
EOF
  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 0 ]

  payload="$(grep '^PAYLOAD ' "$CURL_LOG" | sed 's/^PAYLOAD //')"
  blocks="$(jq -r '.attachments[0].blocks' <<<"$payload")"
  [[ "$blocks" == *"cpu_profile: timeout"* ]]
  [[ "$blocks" == *"haproxy_log: truncated"* ]]
  [[ "$(jq -r '.attachments[0].blocks[-1].elements[0].text' <<<"$payload")" == *"upload PENDING"* ]]
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

@test "payload carries a green Block Kit attachment when everything landed" {
  write_manifest <<'EOF2'
{"incident_id":"i","node":"n","chain":"c","trigger":"block_lag","triggered_at":"t","lag_blocks":82,"artifacts":{"cpu_profile":"ok"},"errors":[],"warnings":[]}
EOF2
  echo "s3://bucket/x.tar.gz" > "$INCIDENT_DIR/.uploaded"

  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 0 ]

  payload="$(grep '^PAYLOAD ' "$CURL_LOG" | sed 's/^PAYLOAD //')"
  [ "$(jq -r '.attachments[0].color' <<<"$payload")" = "good" ]
  [ "$(jq -r '.attachments[0].blocks[0].type' <<<"$payload")" = "header" ]
  [[ "$(jq -r '.attachments[0].blocks[] | select(.fields) | .fields[].text' <<<"$payload")" == *"82 blocks"* ]]
  [[ "$(jq -r '.attachments[0].blocks[-1].elements[0].text' <<<"$payload")" == *"uploaded"* ]]
}

@test "payload turns red when the upload is pending or an artifact failed" {
  write_manifest <<'EOF2'
{"incident_id":"i","node":"n","chain":"c","trigger":"block_lag","triggered_at":"t","lag_blocks":null,"artifacts":{"cpu_profile":"error"},"errors":["cpu_profile: timeout"],"warnings":[]}
EOF2
  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 0 ]

  payload="$(grep '^PAYLOAD ' "$CURL_LOG" | sed 's/^PAYLOAD //')"
  [ "$(jq -r '.attachments[0].color' <<<"$payload")" = "danger" ]
  [[ "$(jq -r '[.attachments[0].blocks[] | select(.text.text // "" | contains("Errors"))] | length' <<<"$payload")" = "1" ]]
  [[ "$(jq -r '.attachments[0].blocks[-1].elements[0].text' <<<"$payload")" == *"PENDING"* ]]
}

@test "payload turns yellow on warnings when everything else landed" {
  write_manifest <<'EOF2'
{"incident_id":"i","node":"n","chain":"c","trigger":"block_lag","triggered_at":"t","lag_blocks":1,"artifacts":{"haproxy_log":"ok"},"errors":[],"warnings":["haproxy_log: truncated"]}
EOF2
  echo "s3://bucket/x.tar.gz" > "$INCIDENT_DIR/.uploaded"

  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 0 ]

  payload="$(grep '^PAYLOAD ' "$CURL_LOG" | sed 's/^PAYLOAD //')"
  [ "$(jq -r '.attachments[0].color' <<<"$payload")" = "warning" ]
}

@test "a corrupt manifest degrades to the plain-text payload without attachments" {
  echo "not json" > "$INCIDENT_DIR/manifest.json"

  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 0 ]

  payload="$(grep '^PAYLOAD ' "$CURL_LOG" | sed 's/^PAYLOAD //')"
  [ "$(jq -r 'has("attachments")' <<<"$payload")" = "false" ]
  [[ "$(jq -r '.text' <<<"$payload")" == *"manifest missing or unreadable"* ]]
}

@test "a schema-less but valid manifest still produces a payload instead of a jq error" {
  echo '{}' > "$INCIDENT_DIR/manifest.json"

  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 0 ]

  payload="$(grep '^PAYLOAD ' "$CURL_LOG" | sed 's/^PAYLOAD //')"
  [[ "$(jq -r '.attachments[0].fallback' <<<"$payload")" == *"0/0 artifacts ok"* ]]
  [ "$(jq -r '.attachments[0].color' <<<"$payload")" = "danger" ]
}

@test "payload turns red on a failed artifact even when the upload itself succeeded" {
  write_manifest <<'EOF2'
{"incident_id":"i","node":"n","chain":"c","trigger":"block_lag","triggered_at":"t","lag_blocks":1,"artifacts":{"cpu_profile":"error","haproxy_log":"ok"},"errors":["cpu_profile: timeout"],"warnings":[]}
EOF2
  echo "s3://bucket/x.tar.gz" > "$INCIDENT_DIR/.uploaded"

  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 0 ]

  payload="$(grep '^PAYLOAD ' "$CURL_LOG" | sed 's/^PAYLOAD //')"
  [ "$(jq -r '.attachments[0].color' <<<"$payload")" = "danger" ]
}
