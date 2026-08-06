setup() {
  NODE_RECORDER_HOME="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  source "${NODE_RECORDER_HOME}/bin/node-recorder"

  # run_capture's manifest step reads these; unset height queries keep it
  # from talking to Prometheus. The upload step builds the object URI from
  # CHAIN, NODE_ID, and S3_PREFIX, and talks to the aws PATH fake.
  export CHAIN="stable"
  export NODE_ID="node-a"
  export S3_PREFIX="s3://bucket/node-recorder"
  unset LOCAL_HEIGHT_QUERY NETWORK_TIP_HEIGHT_QUERY
  PATH="${BATS_TEST_DIRNAME}/fakes/bin:$PATH"
  FAKE_AWS_LOG="$(mktemp)"
  export FAKE_AWS_LOG

  export INCIDENTS_DIR="$(mktemp -d)"
  CALL_LOG="$(mktemp)"
  export CALL_LOG

  # Fake capture scripts: record how they were invoked, exit per FAKE_*_EXIT.
  FAKE_BIN_DIR="$(mktemp -d)"
  cat > "${FAKE_BIN_DIR}/capture-stablevisor-pprof.sh" <<'EOF'
#!/usr/bin/env bash
printf 'stablevisor-pprof %s\n' "$*" >> "$CALL_LOG"
exit "${FAKE_STABLEVISOR_PPROF_EXIT:-0}"
EOF
  cat > "${FAKE_BIN_DIR}/capture-haproxy-log.sh" <<'EOF'
#!/usr/bin/env bash
printf 'haproxy-log %s\n' "$*" >> "$CALL_LOG"
exit "${FAKE_HAPROXY_LOG_EXIT:-0}"
EOF
  chmod +x "${FAKE_BIN_DIR}"/capture-*.sh
  export CAPTURE_STABLEVISOR_PPROF_BIN="${FAKE_BIN_DIR}/capture-stablevisor-pprof.sh"
  export CAPTURE_HAPROXY_LOG_BIN="${FAKE_BIN_DIR}/capture-haproxy-log.sh"
}

teardown() {
  rm -rf "$INCIDENTS_DIR" "$FAKE_BIN_DIR"
  rm -f "$CALL_LOG" "$FAKE_AWS_LOG"
  unset FAKE_STABLEVISOR_PPROF_EXIT FAKE_HAPROXY_LOG_EXIT FAKE_AWS_EXIT
}

@test "run_capture creates an incident dir and runs both capture scripts against it, in order" {
  run run_capture "node-a" "AlertX"
  [ "$status" -eq 0 ]

  incident_dir="$(find "$INCIDENTS_DIR" -mindepth 1 -maxdepth 1 -type d)"
  [ -n "$incident_dir" ]
  [[ "$(basename "$incident_dir")" =~ ^[0-9]{8}T[0-9]{6}Z-block-lag$ ]]

  line1="$(sed -n '1p' "$CALL_LOG")"
  line2="$(sed -n '2p' "$CALL_LOG")"
  [ "$line1" = "stablevisor-pprof $incident_dir" ]
  [[ "$line2" =~ ^haproxy-log\ $incident_dir\ [0-9]+$ ]]
}

@test "run_capture writes a manifest for the incident after the captures" {
  run run_capture "node-a" "AlertX"
  [ "$status" -eq 0 ]

  incident_dir="$(find "$INCIDENTS_DIR" -mindepth 1 -maxdepth 1 -type d)"
  m="$incident_dir/manifest.json"
  [ -f "$m" ]
  [ "$(jq -r '.incident_id' "$m")" = "$(basename "$incident_dir")" ]
  [ "$(jq -r '.node' "$m")" = "node-a" ]
  [ "$(jq -r '.chain' "$m")" = "stable" ]
  [ "$(jq -r '.trigger' "$m")" = "block_lag" ]
}

@test "run_capture uploads the finished bundle after writing the manifest" {
  run run_capture "node-a" "AlertX"
  [ "$status" -eq 0 ]

  incident_dir="$(find "$INCIDENTS_DIR" -mindepth 1 -maxdepth 1 -type d)"
  [ -f "$incident_dir/.uploaded" ]
  [ "$(cat "$incident_dir/.uploaded")" = "s3://bucket/node-recorder/stable/node-a/$(basename "$incident_dir").tar.gz" ]
  grep -q "^s3 cp " "$FAKE_AWS_LOG"
}

@test "run_capture returns 0 when the upload fails and leaves the bundle pending" {
  export FAKE_AWS_EXIT=1

  run run_capture "node-a" "AlertX"
  [ "$status" -eq 0 ]

  incident_dir="$(find "$INCIDENTS_DIR" -mindepth 1 -maxdepth 1 -type d)"
  [ ! -f "$incident_dir/.uploaded" ]
  [ "$(cat "$incident_dir/.upload-attempts")" = "1" ]
}

@test "run_capture passes the trigger time to the haproxy capture as an epoch near now" {
  before="$(date +%s)"
  run_capture "node-a" "AlertX"
  after="$(date +%s)"

  epoch="$(sed -n '2p' "$CALL_LOG" | awk '{print $3}')"
  [ "$epoch" -ge "$before" ]
  [ "$epoch" -le "$after" ]
}

@test "run_capture still runs the haproxy capture and returns 0 when the stablevisor/pprof script fails" {
  export FAKE_STABLEVISOR_PPROF_EXIT=1

  run run_capture "node-a" "AlertX"
  [ "$status" -eq 0 ]

  grep -q '^haproxy-log ' "$CALL_LOG"
}

@test "run_capture returns 0 when both capture scripts fail" {
  export FAKE_STABLEVISOR_PPROF_EXIT=1
  export FAKE_HAPROXY_LOG_EXIT=1

  run run_capture "node-a" "AlertX"
  [ "$status" -eq 0 ]
}

@test "a failing capture script does not kill the daemon under set -e" {
  # bats' `run` executes its command in a status-tested context, which turns
  # bash's errexit off inside run_capture, so the tests above cannot see an
  # errexit death. The daemon calls run_capture as a plain statement with
  # errexit active, so exercise that exact context in a fresh shell: if a
  # failing capture or upload line is not guarded, the shell dies before
  # SURVIVED.
  export FAKE_STABLEVISOR_PPROF_EXIT=1
  export FAKE_AWS_EXIT=1

  run bash -c "source '${NODE_RECORDER_HOME}/bin/node-recorder'; run_capture node-a AlertX >/dev/null 2>&1; echo SURVIVED"
  [ "$status" -eq 0 ]
  [[ "$output" == *"SURVIVED"* ]]
}

@test "run_capture returns 0 and runs no capture script when the incident dir cannot be created" {
  chmod 0555 "$INCIDENTS_DIR"

  run run_capture "node-a" "AlertX"
  [ "$status" -eq 0 ]

  [ ! -s "$CALL_LOG" ]
  chmod 0755 "$INCIDENTS_DIR"
}