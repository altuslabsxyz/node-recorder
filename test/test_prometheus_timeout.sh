#!/usr/bin/env bash
# test/test_prometheus_timeout.sh - uses real curl against a local socket
# that accepts and never responds, unlike test_prometheus.bats whose curl
# override cannot exercise transport behavior. Each call runs under an outer
# `timeout 6` so that a regression (a query function losing its --max-time)
# fails the assertion quickly instead of hanging the suite.
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/prometheus.sh"

hang_port_file="$(mktemp)"
python3 - > "$hang_port_file" <<'EOF' &
import socket
s = socket.socket()
s.bind(("127.0.0.1", 0))
s.listen(4)
print(s.getsockname()[1], flush=True)
conns = []
while True:
    try:
        c, _ = s.accept()
        conns.append(c)  # hold the connection open and never respond
    except OSError:
        break
EOF
hang_server_pid=$!
sleep 0.5
hang_port="$(cat "$hang_port_file")"

export PROMETHEUS_URL="http://127.0.0.1:${hang_port}"
export PROMETHEUS_TIMEOUT_SECONDS=1
export ALERT_NAME="CometBFTBlockHeightBehind"
export ALERT_NODE_LABEL="instance"
export NODE_ID="node-a"

# Case 1: query_alert_state gives up within its timeout instead of hanging.
out="$(timeout 6 bash -c 'source "$1/common.sh"; source "$1/prometheus.sh"; query_alert_state' _ "$LIB_DIR" 2>/dev/null)"
exit_code=$?
assert_exit_code 1 "$exit_code" "query_alert_state fails within PROMETHEUS_TIMEOUT_SECONDS against a hung server"
assert_eq "error" "$out" "query_alert_state reports error on timeout"

# Case 2: query_first_value gives up within its timeout instead of hanging.
out2="$(timeout 6 bash -c 'source "$1/common.sh"; source "$1/prometheus.sh"; query_first_value up' _ "$LIB_DIR" 2>/dev/null)"
exit_code2=$?
assert_exit_code 1 "$exit_code2" "query_first_value fails within PROMETHEUS_TIMEOUT_SECONDS against a hung server"
assert_eq "" "$out2" "query_first_value prints nothing on timeout"

kill "$hang_server_pid" 2>/dev/null
wait "$hang_server_pid" 2>/dev/null
rm -f "$hang_port_file"
