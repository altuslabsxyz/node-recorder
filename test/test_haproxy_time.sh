#!/usr/bin/env bash
# test/test_haproxy_time.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/haproxy.sh"

result="$(_haproxy_epoch_to_iso 1785723141)"
assert_eq "2026-08-03T02:12:21" "$result" "epoch 1785723141 converts to expected UTC ISO string"

result2="$(_haproxy_epoch_to_iso 0)"
assert_eq "1970-01-01T00:00:00" "$result2" "epoch 0 converts to the Unix epoch"
