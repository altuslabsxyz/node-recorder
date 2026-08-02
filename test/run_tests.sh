#!/usr/bin/env bash
# test/run_tests.sh - sources every test/test_*.sh file and reports totals.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/assertions.sh"

for test_file in "$SCRIPT_DIR"/test_*.sh; do
  [[ -e "$test_file" ]] || continue
  echo "== $(basename "$test_file") =="
  source "$test_file"
done

echo "TESTS_RUN=$TESTS_RUN TESTS_FAILED=$TESTS_FAILED"
[[ "$TESTS_FAILED" -eq 0 ]]
