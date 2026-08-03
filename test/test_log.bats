setup() {
  source "${BATS_TEST_DIRNAME}/../lib/log.sh"
}

@test "log_info writes an INFO line to stdout" {
  run log_info "hello world"
  [ "$status" -eq 0 ]
  [[ "$output" == *"[INFO]"* ]]
  [[ "$output" == *"hello world"* ]]
}

@test "log_error writes an ERROR line to stderr, not stdout" {
  stdout="$(log_error "boom" 2>/dev/null)"
  stderr="$(log_error "boom" 2>&1 1>/dev/null)"
  [ -z "$stdout" ]
  [[ "$stderr" == *"[ERROR]"* ]]
  [[ "$stderr" == *"boom"* ]]
}
