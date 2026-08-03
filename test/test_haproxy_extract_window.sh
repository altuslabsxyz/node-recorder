#!/usr/bin/env bash
# test/test_haproxy_extract_window.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/haproxy.sh"

# Case 1: happy path, single file, no rotation, no truncation.
work_dir="$(mktemp -d)"
log_path="$work_dir/haproxy.log"
results_file="$work_dir/results.tsv"
out_file="$work_dir/haproxy.log.out"
: > "$results_file"

cat > "$log_path" <<'EOF'
2026-08-03T02:00:00.000000+00:00 host haproxy[1]: {"id":"before-window"}
2026-08-03T02:12:21.725958+00:00 host haproxy[1]: {"id":"inside-window"}
2026-08-03T02:30:00.000000+00:00 host haproxy[1]: {"id":"after-window"}
EOF

# window: 2026-08-03T02:05:00 (1785722700) .. 2026-08-03T02:20:00 (1785723600)
haproxy_extract_window "$results_file" "$log_path" 1785722700 1785723600 "$out_file" 209715200
assert_exit_code 0 "$?" "case 1: extraction succeeds"
assert_file_exists "$out_file" "case 1: output file is written"
assert_eq "1" "$(grep -c . "$out_file")" "case 1: only the in-window line is kept"
assert_eq "1" "$(grep -c $'haproxy_log\tok' "$results_file")" "case 1: results.tsv records ok"

# Case 2: log file missing -> error result, no output file.
work_dir2="$(mktemp -d)"
results_file2="$work_dir2/results.tsv"
out_file2="$work_dir2/haproxy.log.out"
: > "$results_file2"

haproxy_extract_window "$results_file2" "$work_dir2/does-not-exist.log" 1785722700 1785723600 "$out_file2" 209715200
assert_exit_code 1 "$?" "case 2: extraction fails when log file is missing"
assert_file_absent "$out_file2" "case 2: no output file left behind"
assert_eq "1" "$(grep -c $'haproxy_log\terror' "$results_file2")" "case 2: results.tsv records error"

# Case 3: rotated file needed because the window starts before the live
# file's earliest line.
work_dir3="$(mktemp -d)"
log_path3="$work_dir3/haproxy.log"
results_file3="$work_dir3/results.tsv"
out_file3="$work_dir3/haproxy.log.out"
: > "$results_file3"

printf '2026-08-03T00:05:00.000000+00:00 host haproxy[1]: {"id":"live-in-window"}\n' > "$log_path3"
printf '2026-08-02T23:58:00.000000+00:00 host haproxy[1]: {"id":"rotated-in-window"}\n' > "${log_path3}.1"

# window: 2026-08-02T23:55:00 (1785714900) .. 2026-08-03T00:10:00 (1785715800)
haproxy_extract_window "$results_file3" "$log_path3" 1785714900 1785715800 "$out_file3" 209715200
assert_exit_code 0 "$?" "case 3: extraction succeeds across a rotation boundary"
assert_eq "2" "$(grep -c . "$out_file3")" "case 3: lines from both rotated and live file are kept"
assert_eq "1" "$(sed -n '1p' "$out_file3" | grep -c "rotated-in-window")" "case 3: rotated file's line comes first (oldest first)"
assert_eq "1" "$(sed -n '2p' "$out_file3" | grep -c "live-in-window")" "case 3: live file's line comes second"

# Case 4: filtered output exceeds max_bytes -> truncated, keeping the tail.
# Each of the 3 lines below is exactly 66 bytes (including its newline;
# verify with `printf '...line...\n' | wc -c` if you ever change their
# content), so a 66-byte cap truncates to precisely the last full line
# with no partial-line contamination.
work_dir4="$(mktemp -d)"
log_path4="$work_dir4/haproxy.log"
results_file4="$work_dir4/results.tsv"
out_file4="$work_dir4/haproxy.log.out"
: > "$results_file4"

{
  printf '2026-08-03T02:10:00.000000+00:00 host haproxy[1]: {"id":"oldest"}\n'
  printf '2026-08-03T02:15:00.000000+00:00 host haproxy[1]: {"id":"middle"}\n'
  printf '2026-08-03T02:20:00.000000+00:00 host haproxy[1]: {"id":"newest"}\n'
} > "$log_path4"

# window: 2026-08-03T02:05:00 (1785722700) .. 2026-08-03T02:25:00 (1785723900),
# covering all 3 lines above before the size cap is applied.
# Cap set to exactly one line's byte length (66), so only the newest full
# line survives truncation.
haproxy_extract_window "$results_file4" "$log_path4" 1785722700 1785723900 "$out_file4" 66
assert_exit_code 0 "$?" "case 4: extraction succeeds even when truncated"
assert_eq "1" "$(grep -c . "$out_file4")" "case 4: exactly one full line survives truncation"
assert_eq "1" "$(grep -c "newest" "$out_file4")" "case 4: newest line survives truncation"
assert_eq "0" "$(grep -c "oldest" "$out_file4")" "case 4: oldest line is dropped by truncation"
assert_eq "1" "$(grep -c $'haproxy_log\tok\ttruncated' "$results_file4")" "case 4: results.tsv notes the truncation"

rm -rf "$work_dir" "$work_dir2" "$work_dir3" "$work_dir4"
