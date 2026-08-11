#!/usr/bin/env bash
# bin/capture-stablevisor-pprof.sh <incident_dir>
#
# Runs Capture Flow steps 5-7 from docs/spec/node-recorder.md: trigger and
# confirm the Stablevisor incident snapshot, then collect the goroutine,
# heap, mutex, and CPU pprof profiles. Writes profile artifacts under
# <incident_dir>/pprof/ and one result line per artifact (including
# stablevisor_snapshot) to <incident_dir>/results.tsv.
#
# This is not the full Node Recorder orchestrator described in the spec's
# 13-step Capture Flow (detection, dedup/cooldown, HAProxy capture, mempool
# status capture, manifest.json, S3 upload, and Slack notification are
# separate tickets). It exists so this ticket's slice of the flow is
# independently runnable and testable before the rest of Node Recorder
# exists.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/cometbft.sh"
source "$LIB_DIR/stablevisor.sh"
source "$LIB_DIR/pprof.sh"

incident_dir="${1:?usage: capture-stablevisor-pprof.sh <incident_dir>}"
pprof_out_dir="$incident_dir/pprof"
results_file="$incident_dir/results.tsv"

daemon_home="${DAEMON_HOME:?DAEMON_HOME is required}"
stablevisor_snapshot_base_dir="${STABLEVISOR_SNAPSHOT_BASE_DIR:?STABLEVISOR_SNAPSHOT_BASE_DIR is required}"
cpu_profile_seconds="${CPU_PROFILE_SECONDS:-20}"

mkdir -p "$pprof_out_dir"
: > "$results_file"

snapshot_dir_name=""
if stablevisor_trigger_snapshot "$stablevisor_snapshot_base_dir" snapshot_dir_name; then
  # The bundle must be self-contained: stablevisor's own copy is rotated away
  # by its retention (10 incidents / 10GB, spec's Stablevisor Signal and
  # Snapshot section), so the snapshot goes INTO the bundle under
  # stablevisor/<id>/ per the spec's Incident Bundle tree. Copied, not moved:
  # the incidents directory is stablevisor's own bookkeeping.
  if mkdir -p "$incident_dir/stablevisor" \
      && cp -a "$stablevisor_snapshot_base_dir/$snapshot_dir_name" "$incident_dir/stablevisor/"; then
    record_result "$results_file" "stablevisor_snapshot" "ok" "$snapshot_dir_name"
  else
    record_result "$results_file" "stablevisor_snapshot" "error" "snapshot ${snapshot_dir_name} confirmed but copying it into the bundle failed"
  fi
else
  record_result "$results_file" "stablevisor_snapshot" "error" "trigger or confirmation failed"
fi

pprof_base_url=""
if pprof_base_url="$(cometbft_pprof_url "$daemon_home")"; then
  pprof_collect_quick "$results_file" "$pprof_base_url" "$pprof_out_dir"
  pprof_collect_cpu "$results_file" "$pprof_base_url" "$pprof_out_dir" "$cpu_profile_seconds"
else
  pprof_unresolved_reason="could not resolve pprof address from ${daemon_home}/config/config.toml"
  record_result "$results_file" "goroutine_profile" "error" "$pprof_unresolved_reason"
  record_result "$results_file" "heap_profile" "error" "$pprof_unresolved_reason"
  record_result "$results_file" "mutex_profile" "error" "$pprof_unresolved_reason"
  record_result "$results_file" "cpu_profile" "error" "$pprof_unresolved_reason"
fi

log_info "capture-stablevisor-pprof: done, results in $results_file"
exit 0
