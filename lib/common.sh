#!/usr/bin/env bash
# lib/common.sh - result-recording helper shared by lib/*.sh. Logging lives in
# lib/log.sh, sourced here so callers get log_info/log_error from one place.

source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

# record_result <results_file> <artifact_key> <ok|error> [reason]
# Appends one TSV line to results_file. This is a plain interchange format
# for whichever future ticket builds manifest.json from it, not a finished
# manifest itself.
record_result() {
  local results_file="$1"
  local artifact_key="$2"
  local status="$3"
  local reason="${4:-}"
  printf '%s\t%s\t%s\n' "$artifact_key" "$status" "$reason" >> "$results_file"
}
