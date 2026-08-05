setup() {
  source "${BATS_TEST_DIRNAME}/../lib/log.sh"
  source "${BATS_TEST_DIRNAME}/../lib/config.sh"
  CONFIG_TMP="$(mktemp)"
  # aws is in the dependency check but not installed everywhere; the PATH
  # fake satisfies `command -v` the same way the other fakes do.
  PATH="${BATS_TEST_DIRNAME}/fakes/bin:$PATH"
}

teardown() {
  rm -f "$CONFIG_TMP"
  unset NODE_RECORDER_CONFIG PROMETHEUS_URL ALERT_NAME NODE_ID ALERT_STATE ALERT_NODE_LABEL POLL_INTERVAL_SECONDS COOLDOWN_SECONDS STATE_DIR LOCK_FILE
  unset INCIDENTS_DIR STABLEVISOR_SERVICE_NAME STABLEVISOR_SNAPSHOT_BASE_DIR PPROF_URL CPU_PROFILE_SECONDS HAPROXY_LOG LOG_WINDOW_BEFORE_SECONDS HAPROXY_LOG_MAX_BYTES
  unset CHAIN LOCAL_HEIGHT_QUERY NETWORK_TIP_HEIGHT_QUERY S3_PREFIX S3_UPLOAD_MAX_ATTEMPTS
}

@test "load_config succeeds when required vars are present" {
  cat > "$CONFIG_TMP" <<'EOF'
PROMETHEUS_URL="http://prom.test:9090"
ALERT_NAME="CometBFTBlockHeightBehind"
NODE_ID="main-stable-archive-ovh-de"
CHAIN="stable"
STABLEVISOR_SNAPSHOT_BASE_DIR="/var/lib/stablevisor/incidents"
EOF
  export NODE_RECORDER_CONFIG="$CONFIG_TMP"

  run load_config
  [ "$status" -eq 0 ]
}

@test "load_config applies documented defaults when not set in the config file" {
  cat > "$CONFIG_TMP" <<'EOF'
PROMETHEUS_URL="http://prom.test:9090"
ALERT_NAME="CometBFTBlockHeightBehind"
NODE_ID="main-stable-archive-ovh-de"
CHAIN="stable"
STABLEVISOR_SNAPSHOT_BASE_DIR="/var/lib/stablevisor/incidents"
EOF
  export NODE_RECORDER_CONFIG="$CONFIG_TMP"

  load_config

  [ "$ALERT_STATE" = "firing" ]
  [ "$ALERT_NODE_LABEL" = "instance" ]
  [ "$POLL_INTERVAL_SECONDS" = "15" ]
  [ "$COOLDOWN_SECONDS" = "900" ]
  [ "$STATE_DIR" = "/var/lib/node-recorder/state" ]
  [ "$LOCK_FILE" = "/run/node-recorder.lock" ]
  [ "$INCIDENTS_DIR" = "/var/lib/node-recorder/incidents" ]
  [ "$STABLEVISOR_SERVICE_NAME" = "stablevisor" ]
  [ "$PPROF_URL" = "http://127.0.0.1:6060/debug/pprof" ]
  [ "$CPU_PROFILE_SECONDS" = "20" ]
  [ "$HAPROXY_LOG" = "/var/log/haproxy.log" ]
  [ "$LOG_WINDOW_BEFORE_SECONDS" = "600" ]
  [ "$HAPROXY_LOG_MAX_BYTES" = "209715200" ]
  [ -z "$LOCAL_HEIGHT_QUERY" ]
  [ -z "$NETWORK_TIP_HEIGHT_QUERY" ]
  [ "$S3_PREFIX" = "s3://altuslabs-node-recorder/node-recorder" ]
  [ "$S3_UPLOAD_MAX_ATTEMPTS" = "5" ]
}

@test "load_config fails when a required variable is missing" {
  cat > "$CONFIG_TMP" <<'EOF'
PROMETHEUS_URL="http://prom.test:9090"
EOF
  export NODE_RECORDER_CONFIG="$CONFIG_TMP"

  run load_config
  [ "$status" -eq 1 ]
}

@test "load_config fails when STABLEVISOR_SNAPSHOT_BASE_DIR is missing" {
  cat > "$CONFIG_TMP" <<'EOF'
PROMETHEUS_URL="http://prom.test:9090"
ALERT_NAME="CometBFTBlockHeightBehind"
NODE_ID="main-stable-archive-ovh-de"
CHAIN="stable"
EOF
  export NODE_RECORDER_CONFIG="$CONFIG_TMP"

  run load_config
  [ "$status" -eq 1 ]
  [[ "$output" == *"STABLEVISOR_SNAPSHOT_BASE_DIR"* ]]
}

@test "load_config fails when a required dependency is missing from PATH" {
  cat > "$CONFIG_TMP" <<'EOF'
PROMETHEUS_URL="http://prom.test:9090"
ALERT_NAME="CometBFTBlockHeightBehind"
NODE_ID="main-stable-archive-ovh-de"
EOF
  export NODE_RECORDER_CONFIG="$CONFIG_TMP"

  PATH="" run load_config
  [ "$status" -eq 1 ]
}

@test "load_config fails when CHAIN is missing" {
  cat > "$CONFIG_TMP" <<'CONF'
PROMETHEUS_URL="http://prom.test:9090"
ALERT_NAME="CometBFTBlockHeightBehind"
NODE_ID="main-stable-archive-ovh-de"
STABLEVISOR_SNAPSHOT_BASE_DIR="/var/lib/stablevisor/incidents"
CONF
  export NODE_RECORDER_CONFIG="$CONFIG_TMP"

  run load_config
  [ "$status" -eq 1 ]
  [[ "$output" == *"CHAIN"* ]]
}
