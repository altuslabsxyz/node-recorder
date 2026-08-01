#!/usr/bin/env bash
# lib/pprof.sh - pprof profile collection (Capture Flow steps 6-7 in
# docs/spec/node-recorder.md).

# pprof_fetch <results_file> <artifact_key> <url> <out_file> <timeout_seconds>
# Fetches a single profile. Writes to "<out_file>.tmp" first and only
# renames to <out_file> on HTTP 200 with a non-empty body, so a failed or
# partial fetch never leaves a file at the final path. Always records the
# outcome via record_result.
pprof_fetch() {
  local results_file="$1"
  local artifact_key="$2"
  local url="$3"
  local out_file="$4"
  local timeout_seconds="$5"
  local tmp_file="${out_file}.tmp"

  rm -f "$tmp_file"

  local http_code
  http_code="$(curl --silent --max-time "$timeout_seconds" \
    --output "$tmp_file" --write-out '%{http_code}' "$url" 2>/dev/null)"
  local curl_exit=$?

  if [[ "$curl_exit" -ne 0 ]]; then
    rm -f "$tmp_file"
    record_result "$results_file" "$artifact_key" "error" "curl exit ${curl_exit} (timeout ${timeout_seconds}s)"
    return 1
  fi

  if [[ "$http_code" != "200" ]]; then
    rm -f "$tmp_file"
    record_result "$results_file" "$artifact_key" "error" "http status ${http_code}"
    return 1
  fi

  if [[ ! -s "$tmp_file" ]]; then
    rm -f "$tmp_file"
    record_result "$results_file" "$artifact_key" "error" "empty response body"
    return 1
  fi

  mv "$tmp_file" "$out_file"
  record_result "$results_file" "$artifact_key" "ok"
  return 0
}
