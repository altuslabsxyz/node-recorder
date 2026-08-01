#!/usr/bin/env bash
# test/test_pprof_collect_cpu.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/pprof.sh"

out_dir="$(mktemp -d)"
results_file="$out_dir/results.tsv"

server_out="$(mktemp)"
python3 "$TEST_DIR/fakes/fake_pprof_server.py" 0 > "$server_out" &
server_pid=$!
sleep 0.3
port="$(cat "$server_out")"
base_url="http://127.0.0.1:$port"

PPROF_CPU_GRACE_SECONDS=5 pprof_collect_cpu "$results_file" "$base_url" "$out_dir" 1
assert_exit_code 0 "$?" "pprof_collect_cpu succeeds"
assert_file_exists "$out_dir/cpu.pb.gz" "cpu profile written"

cpu_line="$(grep '^cpu_profile' "$results_file")"
assert_eq "ok" "$(printf '%s' "$cpu_line" | cut -f2)" "cpu profile recorded as ok"

kill "$server_pid" 2>/dev/null
wait "$server_pid" 2>/dev/null
rm -rf "$out_dir" "$server_out"
