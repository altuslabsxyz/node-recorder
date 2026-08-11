#!/usr/bin/env bash
# bin/capture-haproxy-log.sh <incident_dir> <triggered_at_epoch>
#
# Runs Capture Flow step 9 from docs/spec/node-recorder.md: extract the
# HAProxy request log around the incident time window (reaching into the
# previous day's rotated file when the window crosses the daily rotation
# boundary) into <incident_dir>/logs/haproxy.log, capped at
# HAPROXY_LOG_MAX_BYTES, and record the outcome as one line in
# <incident_dir>/results.tsv.
#
# This is not the full Node Recorder orchestrator described in the spec's
# 13-step Capture Flow (detection, Stablevisor/pprof capture, mempool
# status capture, manifest.json, S3 upload, and Slack notification are
# separate tickets).
# It exists so this ticket's slice of the flow is independently runnable
# and testable before the rest of Node Recorder exists.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/haproxy.sh"

incident_dir="${1:?usage: capture-haproxy-log.sh <incident_dir> <triggered_at_epoch>}"
triggered_at_epoch="${2:?usage: capture-haproxy-log.sh <incident_dir> <triggered_at_epoch>}"

logs_out_dir="$incident_dir/logs"
results_file="$incident_dir/results.tsv"

haproxy_log="${HAPROXY_LOG:-/var/log/haproxy.log}"
log_window_before_seconds="${LOG_WINDOW_BEFORE_SECONDS:-600}"
haproxy_log_max_bytes="${HAPROXY_LOG_MAX_BYTES:-209715200}"

mkdir -p "$logs_out_dir"
[[ -f "$results_file" ]] || : > "$results_file"

start_epoch=$(( triggered_at_epoch - log_window_before_seconds ))
end_epoch="$(date +%s)"

haproxy_extract_window "$results_file" "$haproxy_log" "$start_epoch" "$end_epoch" \
  "$logs_out_dir/haproxy.log" "$haproxy_log_max_bytes"

log_info "capture-haproxy-log: done, results in $results_file"
exit 0
