#!/usr/bin/env bash
# test/test_cli_entrypoint.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$TEST_DIR/.." && pwd)"
FAKES_BIN_DIR="$TEST_DIR/fakes/bin"

incident_dir="$(mktemp -d)"
snapshot_base_dir="$(mktemp -d)"

bash "$TEST_DIR/fakes/fake_stablevisor.sh" "$snapshot_base_dir" 0 &
fake_pid=$!
sleep 0.2

server_out="$(mktemp)"
python3 "$TEST_DIR/fakes/fake_pprof_server.py" 0 > "$server_out" &
server_pid=$!
sleep 0.3
port="$(cat "$server_out")"

export PATH="$FAKES_BIN_DIR:$PATH"
export STABLEVISOR_SERVICE_NAME="stablevisor"
export FAKE_SYSTEMCTL_PID="$fake_pid"
export STABLEVISOR_SNAPSHOT_BASE_DIR="$snapshot_base_dir"
export STABLEVISOR_SNAPSHOT_TIMEOUT_SECONDS=5
export STABLEVISOR_SNAPSHOT_POLL_INTERVAL_SECONDS=1
export PPROF_URL="http://127.0.0.1:$port"
export CPU_PROFILE_SECONDS=1
export PPROF_CPU_GRACE_SECONDS=5

"$REPO_ROOT/bin/capture-stablevisor-pprof.sh" "$incident_dir"
assert_exit_code 0 "$?" "entrypoint exits 0 on a full successful run"

assert_file_exists "$incident_dir/results.tsv" "results.tsv written"
assert_file_exists "$incident_dir/pprof/goroutine.pb.gz" "goroutine profile collected"
assert_file_exists "$incident_dir/pprof/heap.pb.gz" "heap profile collected"
assert_file_exists "$incident_dir/pprof/mutex.pb.gz" "mutex profile collected"
assert_file_exists "$incident_dir/pprof/cpu.pb.gz" "cpu profile collected"

stablevisor_line="$(grep '^stablevisor_snapshot' "$incident_dir/results.tsv")"
assert_eq "ok" "$(printf '%s' "$stablevisor_line" | cut -f2)" "stablevisor snapshot recorded as ok"

kill "$fake_pid" "$server_pid" 2>/dev/null
wait "$fake_pid" "$server_pid" 2>/dev/null
rm -rf "$incident_dir" "$snapshot_base_dir" "$server_out"
