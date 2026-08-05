setup() {
  source "${BATS_TEST_DIRNAME}/../lib/log.sh"
  source "${BATS_TEST_DIRNAME}/../lib/prometheus.sh"
  source "${BATS_TEST_DIRNAME}/../lib/manifest.sh"
  export PROMETHEUS_URL="http://prometheus.test:9090"
  unset LOCAL_HEIGHT_QUERY NETWORK_TIP_HEIGHT_QUERY

  INCIDENT_DIR="$(mktemp -d)/20260731T090700Z-block-lag"
  mkdir -p "$INCIDENT_DIR"
}

teardown() {
  rm -rf "$(dirname "$INCIDENT_DIR")"
  unset LOCAL_HEIGHT_QUERY NETWORK_TIP_HEIGHT_QUERY CURL_FIXTURE
}

# The curl override serves both height queries in one call to manifest_write,
# so fixtures are selected per query string, not by a single CURL_FIXTURE.
curl() {
  local arg query=""
  for arg in "$@"; do
    case "$arg" in query=*) query="${arg#query=}" ;; esac
  done
  case "$query" in
    local_ok) printf '{"status":"success","data":{"result":[{"value":[1,"1234000"]}]}}\n200' ;;
    tip_ok) printf '{"status":"success","data":{"result":[{"value":[1,"1234082"]}]}}\n200' ;;
    boom) printf '{"status":"error","error":"internal"}\n500' ;;
    not_a_number) printf '{"status":"success","data":{"result":[{"value":[1,"NaN"]}]}}\n200' ;;
  esac
}
export -f curl

write_results() {
  cat > "$INCIDENT_DIR/results.tsv"
}

@test "manifest_write builds the spec manifest from a fully-ok results.tsv" {
  write_results <<'EOF'
stablevisor_snapshot	ok	incident-20260731-090700-123456
cpu_profile	ok
haproxy_log	ok
EOF
  export LOCAL_HEIGHT_QUERY="local_ok" NETWORK_TIP_HEIGHT_QUERY="tip_ok"

  run manifest_write "$INCIDENT_DIR" "node-a" "stable" "block_lag" "1785484020"
  [ "$status" -eq 0 ]

  m="$INCIDENT_DIR/manifest.json"
  [ "$(jq -r '.schema_version' "$m")" = "1" ]
  [ "$(jq -r '.incident_id' "$m")" = "20260731T090700Z-block-lag" ]
  [ "$(jq -r '.node' "$m")" = "node-a" ]
  [ "$(jq -r '.chain' "$m")" = "stable" ]
  [ "$(jq -r '.trigger' "$m")" = "block_lag" ]
  [ "$(jq -r '.triggered_at' "$m")" = "2026-07-31T07:47:00Z" ]
  [ "$(jq -r '.local_height' "$m")" = "1234000" ]
  [ "$(jq -r '.network_tip_height' "$m")" = "1234082" ]
  [ "$(jq -r '.lag_blocks' "$m")" = "82" ]
  [ "$(jq -r '.stablevisor_incident_id' "$m")" = "incident-20260731-090700-123456" ]
  [ "$(jq -r '.artifacts.cpu_profile' "$m")" = "ok" ]
  [ "$(jq -r '.artifacts.stablevisor_snapshot' "$m")" = "ok" ]
  [ "$(jq -r '.errors | length' "$m")" = "0" ]
  [ "$(jq -r '.warnings | length' "$m")" = "0" ]
}

@test "manifest_write records artifact failures in errors and keeps their status" {
  write_results <<'EOF'
stablevisor_snapshot	error	trigger or confirmation failed
cpu_profile	ok
EOF
  run manifest_write "$INCIDENT_DIR" "node-a" "stable" "block_lag" "1785484020"
  [ "$status" -eq 0 ]

  m="$INCIDENT_DIR/manifest.json"
  [ "$(jq -r '.artifacts.stablevisor_snapshot' "$m")" = "error" ]
  [ "$(jq -r '.stablevisor_incident_id' "$m")" = "null" ]
  jq -e '.errors | index("stablevisor_snapshot: trigger or confirmation failed")' "$m"
}

@test "manifest_write surfaces ok-with-caveat reasons (haproxy truncation) as warnings" {
  write_results <<'EOF'
haproxy_log	ok	truncated to 209715200 bytes (window was 300000000 bytes)
EOF
  run manifest_write "$INCIDENT_DIR" "node-a" "stable" "block_lag" "1785484020"
  [ "$status" -eq 0 ]

  m="$INCIDENT_DIR/manifest.json"
  [ "$(jq -r '.artifacts.haproxy_log' "$m")" = "ok" ]
  jq -e '.warnings | index("haproxy_log: truncated to 209715200 bytes (window was 300000000 bytes)")' "$m"
  [ "$(jq -r '.errors | length' "$m")" = "0" ]
}

@test "manifest_write leaves heights null with warnings when the queries are not configured" {
  write_results <<'EOF'
cpu_profile	ok
EOF
  run manifest_write "$INCIDENT_DIR" "node-a" "stable" "block_lag" "1785484020"
  [ "$status" -eq 0 ]

  m="$INCIDENT_DIR/manifest.json"
  [ "$(jq -r '.local_height' "$m")" = "null" ]
  [ "$(jq -r '.network_tip_height' "$m")" = "null" ]
  [ "$(jq -r '.lag_blocks' "$m")" = "null" ]
  jq -e '.warnings | index("local_height: height query not configured")' "$m"
  jq -e '.warnings | index("network_tip_height: height query not configured")' "$m"
}

@test "manifest_write leaves heights null with errors when a configured query fails" {
  write_results <<'EOF'
cpu_profile	ok
EOF
  export LOCAL_HEIGHT_QUERY="boom" NETWORK_TIP_HEIGHT_QUERY="not_a_number"

  run manifest_write "$INCIDENT_DIR" "node-a" "stable" "block_lag" "1785484020"
  [ "$status" -eq 0 ]

  m="$INCIDENT_DIR/manifest.json"
  [ "$(jq -r '.local_height' "$m")" = "null" ]
  [ "$(jq -r '.lag_blocks' "$m")" = "null" ]
  jq -e '.errors | index("local_height: height query failed")' "$m"
  jq -e '.errors | index("network_tip_height: height query returned a non-integer value: NaN")' "$m"
}

@test "manifest_write records a missing results.tsv in errors and still writes the manifest" {
  run manifest_write "$INCIDENT_DIR" "node-a" "stable" "block_lag" "1785484020"
  [ "$status" -eq 0 ]

  m="$INCIDENT_DIR/manifest.json"
  [ "$(jq -r '.artifacts | length' "$m")" = "0" ]
  jq -e '.errors[0] | startswith("results.tsv missing or unreadable")' "$m"
}

@test "manifest_write output is valid JSON with exactly the spec's top-level fields" {
  write_results <<'EOF'
cpu_profile	ok
EOF
  manifest_write "$INCIDENT_DIR" "node-a" "stable" "block_lag" "1785484020"

  keys="$(jq -r 'keys_unsorted | join(",")' "$INCIDENT_DIR/manifest.json")"
  [ "$keys" = "schema_version,incident_id,node,chain,trigger,triggered_at,local_height,network_tip_height,lag_blocks,stablevisor_incident_id,artifacts,errors,warnings" ]
}
