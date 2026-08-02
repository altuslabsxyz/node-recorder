#!/usr/bin/env bash
# test/test_stablevisor_pid.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"
FAKES_BIN_DIR="$TEST_DIR/fakes/bin"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/stablevisor.sh"

export STABLEVISOR_SERVICE_NAME="stablevisor"
export PATH="$FAKES_BIN_DIR:$PATH"

pid="$(FAKE_SYSTEMCTL_PID=4242 stablevisor_get_pid)"
assert_eq "4242" "$pid" "returns running PID"

FAKE_SYSTEMCTL_PID="0" stablevisor_get_pid >/dev/null 2>&1
assert_exit_code 1 "$?" "MainPID=0 returns failure"

unset FAKE_SYSTEMCTL_PID
stablevisor_get_pid >/dev/null 2>&1
assert_exit_code 1 "$?" "systemctl failure returns failure"

unset STABLEVISOR_SERVICE_NAME
stablevisor_get_pid >/dev/null 2>&1
assert_exit_code 1 "$?" "missing STABLEVISOR_SERVICE_NAME returns failure without exiting the shell"
export STABLEVISOR_SERVICE_NAME="stablevisor"
