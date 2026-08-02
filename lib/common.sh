#!/usr/bin/env bash
# lib/common.sh - logging and result-recording helpers shared by lib/*.sh.

log_info() {
  printf '[%s] INFO: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

log_error() {
  printf '[%s] ERROR: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

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
