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

daemon_home="$(mktemp -d)"
mkdir -p "$daemon_home/config"
printf '[rpc]\npprof_laddr = "127.0.0.1:%s"\n' "$port" > "$daemon_home/config/config.toml"

export PATH="$FAKES_BIN_DIR:$PATH"
export STABLEVISOR_SERVICE_NAME="stablevisor"
export FAKE_SYSTEMCTL_PID="$fake_pid"
export STABLEVISOR_SNAPSHOT_BASE_DIR="$snapshot_base_dir"
export STABLEVISOR_SNAPSHOT_TIMEOUT_SECONDS=5
export STABLEVISOR_SNAPSHOT_POLL_INTERVAL_SECONDS=1
export DAEMON_HOME="$daemon_home"
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

snapshot_id="$(printf '%s' "$stablevisor_line" | cut -f3)"
assert_dir_exists "$incident_dir/stablevisor/$snapshot_id" "snapshot is copied into the bundle under stablevisor/"
assert_file_exists "$incident_dir/stablevisor/$snapshot_id/.complete" "copied snapshot keeps its .complete marker"
assert_dir_exists "$snapshot_base_dir/$snapshot_id" "stablevisor's own copy is left in place (copied, not moved)"

kill "$fake_pid" "$server_pid" 2>/dev/null
wait "$fake_pid" "$server_pid" 2>/dev/null

# Copy-failure case: a file squatting on the bundle's stablevisor/ path makes
# mkdir -p fail, so the snapshot is confirmed but cannot enter the bundle.
incident_dir2="$(mktemp -d)"
snapshot_base_dir2="$(mktemp -d)"
bash "$TEST_DIR/fakes/fake_stablevisor.sh" "$snapshot_base_dir2" 0 &
fake_pid2=$!
sleep 0.2
export FAKE_SYSTEMCTL_PID="$fake_pid2"
export STABLEVISOR_SNAPSHOT_BASE_DIR="$snapshot_base_dir2"
touch "$incident_dir2/stablevisor"

"$REPO_ROOT/bin/capture-stablevisor-pprof.sh" "$incident_dir2" 2>/dev/null
assert_exit_code 0 "$?" "entrypoint still exits 0 when the snapshot copy fails"
stablevisor_line2="$(grep '^stablevisor_snapshot' "$incident_dir2/results.tsv")"
assert_eq "error" "$(printf '%s' "$stablevisor_line2" | cut -f2)" "failed copy is recorded as an error"
printf '%s' "$stablevisor_line2" | cut -f3 | grep -q "copying it into the bundle failed"
assert_exit_code 0 "$?" "the error reason names the copy failure"

kill "$fake_pid2" 2>/dev/null
wait "$fake_pid2" 2>/dev/null
rm -rf "$incident_dir" "$snapshot_base_dir" "$server_out" "$incident_dir2" "$snapshot_base_dir2" "$daemon_home"
