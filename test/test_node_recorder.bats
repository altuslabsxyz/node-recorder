setup() {
  NODE_RECORDER_HOME="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  export STATE_DIR="$(mktemp -d)"
  export LOCK_FILE="$(mktemp -u)"
  export NODE_ID="main-stable-archive-ovh-de"
  export ALERT_NAME="CometBFTBlockHeightBehind"
  export ALERT_NODE_LABEL="instance"
  export PROMETHEUS_URL="http://prometheus.test:9090"
  export COOLDOWN_SECONDS=900

  curl() {
    case "$CURL_FIXTURE" in
      firing) cat "${BATS_TEST_DIRNAME}/fixtures/firing.json"; printf '\n200' ;;
      absent) cat "${BATS_TEST_DIRNAME}/fixtures/absent.json"; printf '\n200' ;;
      network_error) echo "curl: (7) Failed to connect" >&2; return 7 ;;
    esac
  }
  export -f curl

  source "${NODE_RECORDER_HOME}/lib/log.sh"
  source "${NODE_RECORDER_HOME}/lib/state.sh"
  source "${NODE_RECORDER_HOME}/lib/prometheus.sh"
  source "${NODE_RECORDER_HOME}/bin/node-recorder"

  CAPTURE_LOG="$(mktemp)"
  run_capture() { echo "captured:$1:$2" >> "$CAPTURE_LOG"; }
}

teardown() {
  rm -rf "$STATE_DIR"
  rm -f "$LOCK_FILE" "$CAPTURE_LOG"
}

@test "poll_once calls run_capture and enters cooldown when alert is firing" {
  export CURL_FIXTURE=firing

  poll_once

  grep -q "captured:${NODE_ID}:${ALERT_NAME}" "$CAPTURE_LOG"
  [ "$(get_state "$NODE_ID" "$ALERT_NAME")" = "cooldown" ]
}

@test "poll_once skips capture when alert is firing but already in cooldown" {
  export CURL_FIXTURE=firing
  set_state "$NODE_ID" "$ALERT_NAME" "cooldown" "$(( $(date +%s) + 900 ))"

  poll_once

  [ ! -s "$CAPTURE_LOG" ]
}

@test "poll_once does nothing when no alert is firing" {
  export CURL_FIXTURE=absent

  poll_once

  [ ! -s "$CAPTURE_LOG" ]
  [ "$(get_state "$NODE_ID" "$ALERT_NAME")" = "idle" ]
}

@test "poll_once does nothing and releases the lock when the Prometheus query fails" {
  export CURL_FIXTURE=network_error

  poll_once

  [ ! -s "$CAPTURE_LOG" ]
  [ "$(get_state "$NODE_ID" "$ALERT_NAME")" = "idle" ]

  # confirm the lock was actually released (not leaked) by acquiring it again
  run acquire_run_lock
  [ "$status" -eq 0 ]
  release_run_lock
}

@test "poll_once skips the cycle when the lock is already held" {
  # NOTE: deviates from the plan's literal test body. Holding the lock via
  # `exec 200>"$LOCK_FILE"; flock -n 200` in-process doesn't work here: since
  # bats runs this test body and the sourced poll_once/acquire_run_lock in the
  # same shell, acquire_run_lock's own `exec 200>"$LOCK_FILE"` closes this
  # test's fd 200 first (releasing the flock, as it's tied to the open file
  # description, not the process) before re-acquiring a fresh lock, so the
  # "lock already held" condition never actually holds by the time poll_once
  # runs. Verified by reproducing in isolation: reopening fd 200 on the same
  # path in the same process releases a lock held via the old fd 200.
  # test/test_state.bats hit the identical same-process/fd issue for its
  # "acquire_run_lock fails when the lock is already held" case and fixed it
  # by holding the lock in a genuinely separate process; mirrored here.
  flock -n "$LOCK_FILE" sleep 2 &
  holder_pid=$!
  sleep 0.2

  export CURL_FIXTURE=firing
  poll_once

  [ ! -s "$CAPTURE_LOG" ]

  wait "$holder_pid" 2>/dev/null || true
}
