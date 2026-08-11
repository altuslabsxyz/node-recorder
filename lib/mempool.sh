#!/usr/bin/env bash
# lib/mempool.sh - CometBFT mempool status collection (Capture Flow step 8
# in docs/spec/node-recorder.md).
# shellcheck shell=bash

# mempool_collect <results_file> <daemon_home> <out_file> <timeout_seconds>
# Fetches the CometBFT RPC "num_unconfirmed_txs" response and writes the raw
# body to out_file. Writes to "<out_file>.tmp" first and only renames to
# out_file once the response is confirmed HTTP 200, non-empty, and valid
# JSON, so a failed or partial fetch never leaves a file at the final path
# (same contract as pprof_fetch). Always records the outcome via
# record_result under the "mempool_status" key. Returns 0 on success, 1 on
# any failure -- including the RPC address itself not being resolvable from
# <daemon_home>'s config.toml, which is treated as just another collection
# failure, not a reason to stop the rest of the incident capture.
mempool_collect() {
  local results_file="$1"
  local daemon_home="$2"
  local out_file="$3"
  local timeout_seconds="$4"
  local tmp_file="${out_file}.tmp"

  rm -f "$tmp_file"

  local rpc_url
  if ! rpc_url="$(cometbft_rpc_url "$daemon_home")"; then
    record_result "$results_file" "mempool_status" "error" \
      "could not resolve RPC address from ${daemon_home}/config/config.toml"
    return 1
  fi

  local http_code
  http_code="$(curl --silent --max-time "$timeout_seconds" \
    --output "$tmp_file" --write-out '%{http_code}' \
    "${rpc_url}/num_unconfirmed_txs" 2>/dev/null)"
  local curl_exit=$?

  if [[ "$curl_exit" -ne 0 ]]; then
    rm -f "$tmp_file"
    record_result "$results_file" "mempool_status" "error" "curl exit ${curl_exit} (timeout ${timeout_seconds}s)"
    return 1
  fi

  if [[ "$http_code" != "200" ]]; then
    rm -f "$tmp_file"
    record_result "$results_file" "mempool_status" "error" "http status ${http_code}"
    return 1
  fi

  if [[ ! -s "$tmp_file" ]]; then
    rm -f "$tmp_file"
    record_result "$results_file" "mempool_status" "error" "empty response body"
    return 1
  fi

  if ! jq -e . "$tmp_file" >/dev/null 2>&1; then
    rm -f "$tmp_file"
    record_result "$results_file" "mempool_status" "error" "malformed JSON response"
    return 1
  fi

  mv "$tmp_file" "$out_file"
  record_result "$results_file" "mempool_status" "ok"
  return 0
}
