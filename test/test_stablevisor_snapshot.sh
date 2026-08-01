#!/usr/bin/env bash
# test/test_stablevisor_snapshot.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"
FAKES_BIN_DIR="$TEST_DIR/fakes/bin"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/stablevisor.sh"

export STABLEVISOR_SERVICE_NAME="stablevisor"
export PATH="$FAKES_BIN_DIR:$PATH"

# Case 1: success within timeout.
snapshot_base_dir="$(mktemp -d)"
bash "$TEST_DIR/fakes/fake_stablevisor.sh" "$snapshot_base_dir" 1 &
fake_pid=$!
sleep 0.2

export FAKE_SYSTEMCTL_PID="$fake_pid"
export STABLEVISOR_SNAPSHOT_TIMEOUT_SECONDS=5
export STABLEVISOR_SNAPSHOT_POLL_INTERVAL_SECONDS=1

result_dir=""
stablevisor_trigger_snapshot "$snapshot_base_dir" result_dir
exit_code=$?
assert_exit_code 0 "$exit_code" "trigger_snapshot succeeds within timeout"
assert_file_exists "$snapshot_base_dir/$result_dir/.complete" "snapshot .complete marker exists"

wait "$fake_pid" 2>/dev/null
rm -rf "$snapshot_base_dir"

# Case 2: timeout when the snapshot never completes.
snapshot_base_dir2="$(mktemp -d)"
bash "$TEST_DIR/fakes/fake_stablevisor.sh" "$snapshot_base_dir2" 999 &
fake_pid2=$!
sleep 0.2

export FAKE_SYSTEMCTL_PID="$fake_pid2"
export STABLEVISOR_SNAPSHOT_TIMEOUT_SECONDS=2
export STABLEVISOR_SNAPSHOT_POLL_INTERVAL_SECONDS=1

result_dir2=""
stablevisor_trigger_snapshot "$snapshot_base_dir2" result_dir2
exit_code2=$?
assert_exit_code 1 "$exit_code2" "trigger_snapshot times out when .complete never appears"

kill "$fake_pid2" 2>/dev/null
wait "$fake_pid2" 2>/dev/null
rm -rf "$snapshot_base_dir2"
