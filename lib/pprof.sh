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

# pprof_collect_quick <results_file> <base_url> <out_dir>
# Fetches goroutine, heap, and mutex profiles in parallel. Each fetch has
# its own timeout (PPROF_QUICK_TIMEOUT_SECONDS, default 10s) and records
# its own result via pprof_fetch; one failing does not stop or fail the
# others. record_result's appends are safe here because each is a single
# short printf write (well under PIPE_BUF), so concurrent appends from the
# parallel subshells don't interleave within a line.
pprof_collect_quick() {
  local results_file="$1"
  local base_url="$2"
  local out_dir="$3"
  local timeout_seconds="${PPROF_QUICK_TIMEOUT_SECONDS:-10}"

  local pids=()

  pprof_fetch "$results_file" "goroutine_profile" "$base_url/goroutine" "$out_dir/goroutine.pb.gz" "$timeout_seconds" &
  pids+=("$!")

  pprof_fetch "$results_file" "heap_profile" "$base_url/heap" "$out_dir/heap.pb.gz" "$timeout_seconds" &
  pids+=("$!")

  pprof_fetch "$results_file" "mutex_profile" "$base_url/mutex" "$out_dir/mutex.pb.gz" "$timeout_seconds" &
  pids+=("$!")

  local pid
  for pid in "${pids[@]}"; do
    wait "$pid"
  done
  return 0
}
