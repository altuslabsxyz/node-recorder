setup() {
  source "${BATS_TEST_DIRNAME}/../lib/log.sh"
  source "${BATS_TEST_DIRNAME}/../lib/state.sh"
  export STATE_DIR="$(mktemp -d)"
  export LOCK_FILE="$(mktemp -u)"
}

teardown() {
  rm -rf "$STATE_DIR"
  rm -f "$LOCK_FILE"
}

@test "get_state returns idle when no state file exists" {
  result="$(get_state "node-a" "AlertX")"
  [ "$result" = "idle" ]
}

@test "set_state then get_state round-trips the state" {
  set_state "node-a" "AlertX" "capturing" 0
  result="$(get_state "node-a" "AlertX")"
  [ "$result" = "capturing" ]
}

@test "in_cooldown returns true within the cooldown window" {
  future=$(( $(date +%s) + 900 ))
  set_state "node-a" "AlertX" "cooldown" "$future"
  run in_cooldown "node-a" "AlertX"
  [ "$status" -eq 0 ]
}

@test "in_cooldown returns false after the cooldown window has expired" {
  past=$(( $(date +%s) - 10 ))
  set_state "node-a" "AlertX" "cooldown" "$past"
  run in_cooldown "node-a" "AlertX"
  [ "$status" -eq 1 ]
}

@test "in_cooldown returns false when state is idle" {
  run in_cooldown "node-a" "AlertX"
  [ "$status" -eq 1 ]
}

@test "in_cooldown returns false when COOLDOWN_UNTIL is non-numeric (corrupted state)" {
  # Simulate a corrupted state file by writing it directly. Locate it with
  # _state_file rather than recomputing the path here: passing STATE_DIR through
  # the key sanitizer turns its `/` separators into `_`, which lands the fixture
  # in the CWD instead of STATE_DIR and leaves in_cooldown reading a file that
  # does not exist.
  node="node-a"
  alertname="AlertX"
  local file
  file="$(_state_file "$node" "$alertname")"
  {
    printf 'STATE=cooldown\n'
    printf 'COOLDOWN_UNTIL=notanumber\n'
  } > "$file"
  run in_cooldown "$node" "$alertname"
  [ "$status" -eq 1 ]
}

@test "in_cooldown does not evaluate a command substitution in COOLDOWN_UNTIL" {
  # The exit status alone cannot tell the guard apart from its absence: bash
  # arithmetic recursively evaluates `x[...]` as an array subscript, runs the
  # substitution inside it, and still compares as 0, so in_cooldown returns 1
  # either way. Assert on the side effect instead.
  node="node-a"
  alertname="AlertX"
  local file marker
  marker="$STATE_DIR/injected"
  file="$(_state_file "$node" "$alertname")"
  {
    printf 'STATE=cooldown\n'
    printf 'COOLDOWN_UNTIL=x[$(touch "%s")]\n' "$marker"
  } > "$file"
  run in_cooldown "$node" "$alertname"
  [ "$status" -eq 1 ]
  [ ! -f "$marker" ]
}

@test "set_state rejects an invalid state value" {
  run set_state "node-a" "AlertX" "bogus" 0
  [ "$status" -eq 1 ]
}

@test "set_state rejects a non-numeric cooldown_until" {
  run set_state "node-a" "AlertX" "cooldown" "notanumber"
  [ "$status" -eq 1 ]
}

@test "set_state rejecting invalid input does not write a state file" {
  set_state "node-a" "AlertX" "bogus" 0 || true
  result="$(get_state "node-a" "AlertX")"
  [ "$result" = "idle" ]
}

@test "acquire_run_lock succeeds when the lock is free" {
  run acquire_run_lock
  [ "$status" -eq 0 ]
}

@test "acquire_run_lock fails when the lock is already held" {
  flock -n "$LOCK_FILE" sleep 2 &
  holder_pid=$!
  sleep 0.2

  run acquire_run_lock
  [ "$status" -eq 1 ]

  wait "$holder_pid" 2>/dev/null || true
}

@test "release_run_lock allows a subsequent acquire_run_lock to succeed" {
  acquire_run_lock
  release_run_lock
  run acquire_run_lock
  [ "$status" -eq 0 ]
}
