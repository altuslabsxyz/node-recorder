#!/usr/bin/env bash
# lib/incident.sh - incident ID and working-directory creation (Capture Flow
# step 4 in docs/spec/node-recorder.md).
# shellcheck shell=bash

# _incident_id <trigger>
# Prints "<UTC timestamp>Z-<trigger>", e.g. "20260731T090700Z-block-lag" for
# trigger "block_lag" (the spec's bundle-layout id format). Characters outside
# a filesystem-safe allow-list are replaced with "-", which both maps the
# trigger's underscores to the layout's hyphens and keeps a trigger containing
# "/" from producing a nested or escaped path.
_incident_id() {
  local trigger="$1"
  local safe_trigger
  safe_trigger="$(printf '%s' "$trigger" | tr -c 'A-Za-z0-9.-' '-')"
  printf '%sZ-%s' "$(date -u +%Y%m%dT%H%M%S)" "$safe_trigger"
}

# incident_create <base_dir> <trigger>
# Creates "<base_dir>/<incident id>" (creating base_dir itself if needed) and
# prints the created path. Returns 1 (nothing printed) if the directory
# cannot be created. The incident directory itself is made without -p, so a
# pre-existing directory of the same name is a failure rather than being
# silently reused for a second incident's artifacts.
incident_create() {
  local base_dir="$1"
  local trigger="$2"

  local incident_dir
  incident_dir="$base_dir/$(_incident_id "$trigger")"

  if ! mkdir -p "$base_dir" 2>/dev/null || ! mkdir "$incident_dir" 2>/dev/null; then
    log_error "incident_create: failed to create $incident_dir"
    return 1
  fi

  printf '%s\n' "$incident_dir"
  return 0
}
