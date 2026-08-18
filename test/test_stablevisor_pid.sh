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

# The three failure modes must be distinguishable from the log alone. They
# reached the operator as one undifferentiated "trigger or confirmation
# failed" line in manifest.json before, which is what made a wrong
# STABLEVISOR_SERVICE_NAME look identical to a dead Stablevisor.
out="$(FAKE_SYSTEMCTL_LOAD_STATE="not-found" FAKE_SYSTEMCTL_PID="0" stablevisor_get_pid 2>&1)"
assert_contains "$out" "no systemd unit named 'stablevisor'" "not-found unit is reported as a naming problem"

out="$(FAKE_SYSTEMCTL_LOAD_STATE="not-found" FAKE_SYSTEMCTL_PID="0" stablevisor_get_pid 2>&1)"
assert_contains "$out" "STABLEVISOR_SERVICE_NAME" "not-found error points at the setting to fix"

out="$(FAKE_SYSTEMCTL_LOAD_STATE="loaded" FAKE_SYSTEMCTL_PID="0" stablevisor_get_pid 2>&1)"
assert_contains "$out" "not running" "a loaded but stopped unit is reported as not running"

out="$(FAKE_SYSTEMCTL_LOAD_STATE="loaded" FAKE_SYSTEMCTL_PID="0" stablevisor_get_pid 2>&1)"
case "$out" in
  *"no systemd unit named"*) found_wrong_message=1 ;;
  *) found_wrong_message=0 ;;
esac
assert_eq "0" "$found_wrong_message" "a stopped unit is not misreported as a missing unit"

# verify_stablevisor_unit: startup counterpart to verify_node_label_match.
FAKE_SYSTEMCTL_PID=4242 verify_stablevisor_unit >/dev/null 2>&1
assert_exit_code 0 "$?" "verify_stablevisor_unit succeeds when the unit is running"

FAKE_SYSTEMCTL_LOAD_STATE="not-found" FAKE_SYSTEMCTL_PID="0" verify_stablevisor_unit >/dev/null 2>&1
assert_exit_code 1 "$?" "verify_stablevisor_unit fails when the unit does not exist"

out="$(FAKE_SYSTEMCTL_LOAD_STATE="not-found" FAKE_SYSTEMCTL_PID="0" verify_stablevisor_unit 2>&1)"
assert_contains "$out" "stablevisor_snapshot" "the failure names the artifact that will be lost"
