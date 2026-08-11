#!/usr/bin/env bash
# lib/retention.sh - uploaded-bundle retention (Capture Flow step 13 in
# docs/spec/node-recorder.md). Reads LOCAL_RETENTION_COUNT from the
# environment: keep the newest N uploaded bundles (default 5), 0 deletes each
# bundle right after its upload, an explicit empty value turns retention off.
# shellcheck shell=bash

# retention_prune <incidents_dir>
# Deletes the oldest uploaded bundles beyond LOCAL_RETENTION_COUNT, oldest
# first (incident ids sort chronologically). Only bundles carrying an
# .uploaded marker are ever candidates: a bundle whose upload is pending or
# given up is the only copy of its incident data, so it is never deleted
# under any policy (see the spec's retention decision). Always returns 0 --
# a failed deletion is logged and must never take the caller down.
retention_prune() {
  local incidents_dir="$1"
  # ${VAR-default} (no colon) on purpose: unset means the default of 5, but
  # an explicit empty value is the documented way to turn retention off.
  local keep="${LOCAL_RETENTION_COUNT-5}"

  if [[ -z "$keep" ]]; then
    return 0
  fi

  local uploaded=()
  local incident_dir
  for incident_dir in "$incidents_dir"/*/; do
    incident_dir="${incident_dir%/}"
    [[ -d "$incident_dir" ]] || continue
    [[ -f "$incident_dir/.uploaded" ]] || continue
    uploaded+=("$incident_dir")
  done

  local excess=$(( ${#uploaded[@]} - keep ))
  if (( excess <= 0 )); then
    return 0
  fi

  local i
  for (( i = 0; i < excess; i++ )); do
    if rm -rf "${uploaded[$i]}"; then
      log_info "retention_prune: deleted uploaded bundle ${uploaded[$i]}"
    else
      log_error "retention_prune: failed to delete ${uploaded[$i]}"
    fi
  done
  return 0
}
