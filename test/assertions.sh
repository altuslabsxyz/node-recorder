#!/usr/bin/env bash
# test/assertions.sh - minimal assertion helpers, sourced once by run_tests.sh.
# Each test_*.sh file runs its assertions top-to-bottom when sourced; there
# is no per-test-function discovery, to keep the harness simple.

TESTS_RUN=0
TESTS_FAILED=0

assert_eq() {
  local expected="$1" actual="$2" msg="${3:-assert_eq}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$expected" != "$actual" ]]; then
    echo "FAIL: $msg (expected [$expected], got [$actual])" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_exit_code() {
  local expected="$1" actual="$2" msg="${3:-assert_exit_code}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ "$expected" -ne "$actual" ]]; then
    echo "FAIL: $msg (expected exit [$expected], got [$actual])" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_file_exists() {
  local path="$1" msg="${2:-assert_file_exists}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ ! -f "$path" ]]; then
    echo "FAIL: $msg (expected file to exist: $path)" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}

assert_file_absent() {
  local path="$1" msg="${2:-assert_file_absent}"
  TESTS_RUN=$((TESTS_RUN + 1))
  if [[ -f "$path" ]]; then
    echo "FAIL: $msg (expected file to NOT exist: $path)" >&2
    TESTS_FAILED=$((TESTS_FAILED + 1))
  fi
}
