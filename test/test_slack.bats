setup() {
  source "${BATS_TEST_DIRNAME}/../lib/log.sh"
  source "${BATS_TEST_DIRNAME}/../lib/slack.sh"

  INCIDENT_DIR="$(mktemp -d)/20260731T090700Z-block-lag"
  mkdir -p "$INCIDENT_DIR"
  CURL_LOG="$(mktemp)"
  export CURL_LOG
  export SLACK_WEBHOOK_URL="https://hooks.slack.test/services/T000/B000/XXX"
  # Pinned so the object URL is deterministic regardless of the host's AWS
  # environment; the no-region fallback has its own test below.
  unset AWS_DEFAULT_REGION AWS_REGION
  export S3_REGION="ap-northeast-1"
}

teardown() {
  rm -rf "$(dirname "$INCIDENT_DIR")"
  rm -f "$CURL_LOG"
  unset SLACK_WEBHOOK_URL FAKE_CURL_HTTP_CODE FAKE_CURL_EXIT
  unset S3_REGION AWS_DEFAULT_REGION AWS_REGION
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
  context_line="$(jq -r '.attachments[0].blocks[-1].elements[0].text' <<<"$payload")"
  [ "$context_line" = ":package: uploaded: <https://bucket.s3.ap-northeast-1.amazonaws.com/node-recorder/stable/node-a/20260731T090700Z-block-lag.tar.gz>" ]
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

@test "_slack_s3_object_url builds the virtual-hosted URL for the configured region" {
  run _slack_s3_object_url "s3://node-recorder-snapshot/stable/Test_stable_archive_use1/20260813T094142Z-block-lag.tar.gz"
  [ "$status" -eq 0 ]
  [ "$output" = "https://node-recorder-snapshot.s3.ap-northeast-1.amazonaws.com/stable/Test_stable_archive_use1/20260813T094142Z-block-lag.tar.gz" ]
}

@test "_slack_s3_object_url falls back to AWS_DEFAULT_REGION when S3_REGION is unset" {
  unset S3_REGION
  export AWS_DEFAULT_REGION="eu-central-1"
  run _slack_s3_object_url "s3://bucket/a/b.tar.gz"
  [ "$output" = "https://bucket.s3.eu-central-1.amazonaws.com/a/b.tar.gz" ]
}

@test "_slack_s3_object_url falls back to AWS_REGION when the others are unset" {
  unset S3_REGION
  export AWS_REGION="us-west-2"
  run _slack_s3_object_url "s3://bucket/a/b.tar.gz"
  [ "$output" = "https://bucket.s3.us-west-2.amazonaws.com/a/b.tar.gz" ]
}

@test "_slack_s3_object_url uses the global endpoint when no region is known" {
  unset S3_REGION
  run _slack_s3_object_url "s3://bucket/a/b.tar.gz"
  [ "$output" = "https://bucket.s3.amazonaws.com/a/b.tar.gz" ]
}

@test "_slack_s3_object_url prints nothing for a non-s3 URI" {
  run _slack_s3_object_url "/var/lib/node-recorder/incidents/x"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a non-s3 .uploaded marker degrades to the literal value instead of a broken link" {
  write_manifest <<'EOF2'
{"incident_id":"i","node":"n","chain":"c","trigger":"block_lag","triggered_at":"t","artifacts":{"cpu_profile":"ok"},"errors":[],"warnings":[]}
EOF2
  echo "not-an-s3-uri" > "$INCIDENT_DIR/.uploaded"

  run slack_notify_incident "$INCIDENT_DIR"
  [ "$status" -eq 0 ]

  payload="$(grep '^PAYLOAD ' "$CURL_LOG" | sed 's/^PAYLOAD //')"
  context_line="$(jq -r '.attachments[0].blocks[-1].elements[0].text' <<<"$payload")"
  [ "$context_line" = ':package: uploaded: `not-an-s3-uri`' ]
}
