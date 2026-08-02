#!/usr/bin/env bash
# test/test_common.sh
LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../lib" && pwd)"
source "$LIB_DIR/common.sh"

tmp_dir="$(mktemp -d)"
results_file="$tmp_dir/results.tsv"

record_result "$results_file" "cpu_profile" "ok"
record_result "$results_file" "heap_profile" "error" "timeout after 10s"

line1="$(sed -n '1p' "$results_file")"
line2="$(sed -n '2p' "$results_file")"

assert_eq "$(printf 'cpu_profile\tok\t')" "$line1" "ok result has empty reason field"
assert_eq "$(printf 'heap_profile\terror\ttimeout after 10s')" "$line2" "error result includes reason"

rm -rf "$tmp_dir"
