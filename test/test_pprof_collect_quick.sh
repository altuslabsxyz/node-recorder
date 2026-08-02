#!/usr/bin/env bash
# test/test_pprof_collect_quick.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/pprof.sh"

out_dir="$(mktemp -d)"
results_file="$out_dir/results.tsv"
marker_file="$out_dir/fail_marker"

server_out="$(mktemp)"
FAKE_PPROF_FAIL_MARKER_FILE="$marker_file" \
  python3 "$TEST_DIR/fakes/fake_pprof_server.py" 0 > "$server_out" &
server_pid=$!
sleep 0.3
port="$(cat "$server_out")"
base_url="http://127.0.0.1:$port"

echo -n "heap" > "$marker_file"

PPROF_QUICK_TIMEOUT_SECONDS=5 pprof_collect_quick "$results_file" "$base_url" "$out_dir"

assert_file_exists "$out_dir/goroutine.pb.gz" "goroutine still collected when heap fails"
assert_file_exists "$out_dir/mutex.pb.gz" "mutex still collected when heap fails"
assert_file_absent "$out_dir/heap.pb.gz" "heap not written when its fetch fails"

heap_line="$(grep '^heap_profile' "$results_file")"
goroutine_line="$(grep '^goroutine_profile' "$results_file")"

assert_eq "error" "$(printf '%s' "$heap_line" | cut -f2)" "heap recorded as error"
assert_eq "ok" "$(printf '%s' "$goroutine_line" | cut -f2)" "goroutine recorded as ok"

kill "$server_pid" 2>/dev/null
wait "$server_pid" 2>/dev/null
rm -rf "$out_dir" "$server_out"
