#!/usr/bin/env bash
# test/test_haproxy_filter_lines.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/haproxy.sh"

input="$(mktemp)"
cat > "$input" <<'EOF'
2026-08-03T02:00:00.000000+00:00 host haproxy[1]: {"id":"before-window"}
2026-08-03T02:10:00.000000+00:00 host haproxy[1]: {"id":"window-start-boundary"}
2026-08-03T02:12:21.725958+00:00 host haproxy[1]: {"id":"inside-window"}
2026-08-03T02:20:00.000000+00:00 host haproxy[1]: {"id":"window-end-boundary"}
2026-08-03T02:20:01.000000+00:00 host haproxy[1]: {"id":"after-window"}
EOF

output="$(_haproxy_filter_lines "2026-08-03T02:10:00" "2026-08-03T02:20:00" < "$input")"

assert_eq "3" "$(grep -c . <<<"$output")" "exactly 3 lines fall within the window"
echo "$output" | grep -q "window-start-boundary" && start_ok=0 || start_ok=1
assert_exit_code 0 "$start_ok" "start boundary is inclusive"
echo "$output" | grep -q "window-end-boundary" && end_ok=0 || end_ok=1
assert_exit_code 0 "$end_ok" "end boundary is inclusive"
echo "$output" | grep -q "before-window" && before_found=0 || before_found=1
assert_exit_code 1 "$before_found" "line before the window is excluded"
echo "$output" | grep -q "after-window" && after_found=0 || after_found=1
assert_exit_code 1 "$after_found" "line after the window is excluded"

rm -f "$input"
