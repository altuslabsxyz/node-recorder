setup() {
  source "${BATS_TEST_DIRNAME}/../lib/log.sh"
  source "${BATS_TEST_DIRNAME}/../lib/prometheus.sh"
  export PROMETHEUS_URL="http://prometheus.test:9090"
  export ALERT_NAME="CometBFTBlockHeightBehind"
  export ALERT_NODE_LABEL="instance"
  export NODE_ID="main-stable-archive-ovh-de"
}

curl() {
  case "$CURL_FIXTURE" in
    firing) cat "${BATS_TEST_DIRNAME}/fixtures/firing.json"; printf '\n200' ;;
    pending) cat "${BATS_TEST_DIRNAME}/fixtures/pending.json"; printf '\n200' ;;
    absent) cat "${BATS_TEST_DIRNAME}/fixtures/absent.json"; printf '\n200' ;;
    both) cat "${BATS_TEST_DIRNAME}/fixtures/both.json"; printf '\n200' ;;
    height) cat "${BATS_TEST_DIRNAME}/fixtures/height.json"; printf '\n200' ;;
    http_error) printf '{"status":"error","error":"internal"}\n500' ;;
    prom_error_200) printf '{"status":"error","errorType":"bad_data","error":"invalid query"}\n200' ;;
    malformed) printf 'this is not json\n200' ;;
    network_error) echo "curl: (7) Failed to connect" >&2; return 7 ;;
  esac
}
export -f curl

@test "query_alert_state reports firing when a firing series is returned" {
  export CURL_FIXTURE=firing
  result="$(query_alert_state)"
  [ "$result" = "firing" ]
}

@test "query_alert_state reports pending when only a pending series is returned" {
  export CURL_FIXTURE=pending
  result="$(query_alert_state)"
  [ "$result" = "pending" ]
}

@test "query_alert_state reports absent when no series is returned" {
  export CURL_FIXTURE=absent
  result="$(query_alert_state)"
  [ "$result" = "absent" ]
}

@test "query_alert_state prefers firing when both firing and pending series are present" {
  export CURL_FIXTURE=both
  result="$(query_alert_state)"
  [ "$result" = "firing" ]
}

@test "query_alert_state reports error on a non-200 HTTP status" {
  export CURL_FIXTURE=http_error
  result="$(query_alert_state 2>/dev/null)" || exit_status=$?
  [ "$exit_status" -eq 1 ]
  [ "$result" = "error" ]
}

@test "query_alert_state reports error when Prometheus returns 200 with status=error" {
  export CURL_FIXTURE=prom_error_200
  result="$(query_alert_state 2>/dev/null)" || exit_status=$?
  [ "$exit_status" -eq 1 ]
  [ "$result" = "error" ]
}

@test "query_alert_state reports error on malformed JSON" {
  export CURL_FIXTURE=malformed
  result="$(query_alert_state 2>/dev/null)" || exit_status=$?
  [ "$exit_status" -eq 1 ]
  [ "$result" = "error" ]
}

@test "query_alert_state reports error on a curl network failure" {
  export CURL_FIXTURE=network_error
  result="$(query_alert_state 2>/dev/null)" || exit_status=$?
  [ "$exit_status" -eq 1 ]
  [ "$result" = "error" ]
}

@test "query_first_value prints the first series' sample value" {
  export CURL_FIXTURE=height
  result="$(query_first_value 'up')"
  [ "$result" = "1234000" ]
}

@test "query_first_value fails and prints nothing when the result set is empty" {
  export CURL_FIXTURE=absent
  result="$(query_first_value 'up' 2>/dev/null)" || exit_status=$?
  [ "${exit_status:-0}" -eq 1 ]
  [ -z "$result" ]
}

@test "query_first_value fails on a non-200 HTTP status" {
  export CURL_FIXTURE=http_error
  run query_first_value 'up'
  [ "$status" -eq 1 ]
}

@test "query_first_value fails when Prometheus returns 200 with status=error" {
  export CURL_FIXTURE=prom_error_200
  run query_first_value 'up'
  [ "$status" -eq 1 ]
}

@test "query_first_value fails on a curl network failure" {
  export CURL_FIXTURE=network_error
  run query_first_value 'up'
  [ "$status" -eq 1 ]
}
