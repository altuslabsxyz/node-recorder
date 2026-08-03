setup() {
  source "${BATS_TEST_DIRNAME}/../lib/log.sh"
  source "${BATS_TEST_DIRNAME}/../lib/config.sh"
  CONFIG_TMP="$(mktemp)"
}

teardown() {
  rm -f "$CONFIG_TMP"
  unset NODE_RECORDER_CONFIG PROMETHEUS_URL ALERT_NAME NODE_ID ALERT_STATE ALERT_NODE_LABEL POLL_INTERVAL_SECONDS COOLDOWN_SECONDS STATE_DIR LOCK_FILE
}

@test "load_config succeeds when required vars are present" {
  cat > "$CONFIG_TMP" <<'EOF'
PROMETHEUS_URL="http://prom.test:9090"
ALERT_NAME="CometBFTBlockHeightBehind"
NODE_ID="main-stable-archive-ovh-de"
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
EOF
  export NODE_RECORDER_CONFIG="$CONFIG_TMP"

  load_config

  [ "$ALERT_STATE" = "firing" ]
  [ "$ALERT_NODE_LABEL" = "instance" ]
  [ "$POLL_INTERVAL_SECONDS" = "15" ]
  [ "$COOLDOWN_SECONDS" = "900" ]
  [ "$STATE_DIR" = "/var/lib/node-recorder/state" ]
  [ "$LOCK_FILE" = "/run/node-recorder.lock" ]
}

@test "load_config fails when a required variable is missing" {
  cat > "$CONFIG_TMP" <<'EOF'
PROMETHEUS_URL="http://prom.test:9090"
EOF
  export NODE_RECORDER_CONFIG="$CONFIG_TMP"

  run load_config
  [ "$status" -eq 1 ]
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
