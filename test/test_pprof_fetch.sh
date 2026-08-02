#!/usr/bin/env bash
# test/test_pprof_fetch.sh
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

pprof_fetch "$results_file" "ok_profile" "$base_url/whatever" "$out_dir/ok.out" 5
assert_exit_code 0 "$?" "pprof_fetch succeeds on 200"
assert_file_exists "$out_dir/ok.out" "output file written on success"

pprof_fetch "$results_file" "slow_profile" "$base_url/slow/3" "$out_dir/slow.out" 1
assert_exit_code 1 "$?" "pprof_fetch fails when curl times out first"
assert_file_absent "$out_dir/slow.out" "no file left behind on timeout"
assert_file_absent "$out_dir/slow.out.tmp" "no tmp file left behind on timeout"

pprof_fetch "$results_file" "error_profile" "$base_url/error" "$out_dir/error.out" 5
assert_exit_code 1 "$?" "pprof_fetch fails on HTTP 500"
assert_file_absent "$out_dir/error.out" "no file left behind on http error"

pprof_fetch "$results_file" "empty_profile" "$base_url/empty" "$out_dir/empty.out" 5
assert_exit_code 1 "$?" "pprof_fetch fails on empty body"
assert_file_absent "$out_dir/empty.out" "no file left behind on empty body"

kill "$server_pid" 2>/dev/null
wait "$server_pid" 2>/dev/null
rm -rf "$out_dir" "$server_out"
