#!/usr/bin/env bash
# test/test_haproxy_candidate_files.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/haproxy.sh"

work_dir="$(mktemp -d)"
log_path="$work_dir/haproxy.log"

# Case 1: window starts before the live file's first line -> rotated file included.
printf '2026-08-03T00:05:00.000000+00:00 host haproxy[1]: {"id":"a"}\n' > "$log_path"
printf '2026-08-02T23:50:00.000000+00:00 host haproxy[1]: {"id":"rotated"}\n' > "${log_path}.1"

result="$(_haproxy_candidate_files "$log_path" "2026-08-02T23:55:00")"
assert_eq "2" "$(grep -c . <<<"$result")" "case 1: both rotated and live file are candidates"
assert_eq "${log_path}.1" "$(sed -n '1p' <<<"$result")" "case 1: rotated file listed first (oldest first)"
assert_eq "$log_path" "$(sed -n '2p' <<<"$result")" "case 1: live file listed second"

# Case 2: .1.gz takes priority over an uncompressed .1 if both exist.
gzip -k -f "${log_path}.1"
result2="$(_haproxy_candidate_files "$log_path" "2026-08-02T23:55:00")"
assert_eq "${log_path}.1.gz" "$(sed -n '1p' <<<"$result2")" "case 2: .1.gz preferred over uncompressed .1"

# Case 3: window starts after the live file's first line -> rotated file not needed.
result3="$(_haproxy_candidate_files "$log_path" "2026-08-03T00:10:00")"
assert_eq "1" "$(grep -c . <<<"$result3")" "case 3: only the live file is a candidate"
assert_eq "$log_path" "$(sed -n '1p' <<<"$result3")" "case 3: live file is the only candidate"

# Case 4: no rotated file exists at all -> only the live file, no error.
work_dir2="$(mktemp -d)"
log_path2="$work_dir2/haproxy.log"
printf '2026-08-03T00:05:00.000000+00:00 host haproxy[1]: {"id":"a"}\n' > "$log_path2"
result4="$(_haproxy_candidate_files "$log_path2" "2026-08-02T23:55:00")"
assert_eq "1" "$(grep -c . <<<"$result4")" "case 4: missing rotated file is skipped, not an error"
assert_eq "$log_path2" "$(sed -n '1p' <<<"$result4")" "case 4: live file is the only candidate"

rm -rf "$work_dir" "$work_dir2"
