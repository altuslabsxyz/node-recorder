#!/usr/bin/env bash
# lib/manifest.sh - manifest.json generation (Capture Flow step 10 in
# docs/spec/node-recorder.md).
# shellcheck shell=bash

# _manifest_epoch_to_iso <epoch_seconds>
# Prints epoch_seconds as a UTC "YYYY-MM-DDTHH:MM:SSZ" string. Tries GNU
# date's "-d @<epoch>" syntax first (production/Linux); falls back to BSD
# date's "-r <epoch>" syntax (local dev on macOS) if that fails.
_manifest_epoch_to_iso() {
  local epoch="$1"
  date -u -d "@${epoch}" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null && return 0
  date -u -r "${epoch}" +%Y-%m-%dT%H:%M:%SZ
}

# _manifest_query_height <query> <field_name> <errors_file> <warnings_file>
# Prints the height for an operator-supplied PromQL query, or "null". An
# unset query is a deliberate operator choice, so it lands in warnings; a
# configured query that fails or returns a non-integer lands in errors.
_manifest_query_height() {
  local query="$1"
  local field_name="$2"
  local errors_file="$3"
  local warnings_file="$4"

  if [[ -z "$query" ]]; then
    printf '%s: height query not configured\n' "$field_name" >> "$warnings_file"
    echo "null"
    return 0
  fi

  local value
  if ! value="$(query_first_value "$query")"; then
    printf '%s: height query failed\n' "$field_name" >> "$errors_file"
    echo "null"
    return 0
  fi

  if [[ ! "$value" =~ ^[0-9]+$ ]]; then
    printf '%s: height query returned a non-integer value: %s\n' "$field_name" "$value" >> "$errors_file"
    echo "null"
    return 0
  fi

  echo "$value"
  return 0
}

# manifest_write <incident_dir> <node> <chain> <trigger> <triggered_at_epoch>
# Builds <incident_dir>/manifest.json (spec's Manifest example schema) from
# <incident_dir>/results.tsv plus the height queries. Failures along the way
# (missing results.tsv, unset or failing height queries) degrade to null
# fields with entries in the manifest's own errors/warnings arrays; this
# function only returns 1 when the manifest file itself cannot be written.
# The manifest is written to a .tmp path first and renamed, so a partial
# write never leaves a file at the final path.
manifest_write() {
  local incident_dir="$1"
  local node="$2"
  local chain="$3"
  local trigger="$4"
  local triggered_at_epoch="$5"

  local results_file="$incident_dir/results.tsv"
  local manifest_file="$incident_dir/manifest.json"
  local errors_file warnings_file
  errors_file="$(mktemp)"
  warnings_file="$(mktemp)"

  # artifacts object from results.tsv. The stablevisor_snapshot row's reason
  # column carries the snapshot directory name on success, not a caveat, so
  # it becomes stablevisor_incident_id instead of a warning.
  local artifacts_json="{}"
  local stablevisor_incident_id="null"
  if [[ -r "$results_file" ]]; then
    local key status reason
    while IFS=$'\t' read -r key status reason; do
      [[ -z "$key" ]] && continue
      artifacts_json="$(jq --arg k "$key" --arg s "$status" '. + {($k): $s}' <<<"$artifacts_json")"
      if [[ "$key" == "stablevisor_snapshot" && "$status" == "ok" && -n "$reason" ]]; then
        stablevisor_incident_id="$(jq -n --arg id "$reason" '$id')"
      elif [[ "$status" == "ok" && -n "$reason" ]]; then
        printf '%s: %s\n' "$key" "$reason" >> "$warnings_file"
      elif [[ "$status" != "ok" ]]; then
        printf '%s: %s\n' "$key" "${reason:-collection failed}" >> "$errors_file"
      fi
    done < "$results_file"
  else
    printf 'results.tsv missing or unreadable: %s\n' "$results_file" >> "$errors_file"
  fi

  local local_height network_tip_height
  local_height="$(_manifest_query_height "${LOCAL_HEIGHT_QUERY:-}" "local_height" "$errors_file" "$warnings_file")"
  network_tip_height="$(_manifest_query_height "${NETWORK_TIP_HEIGHT_QUERY:-}" "network_tip_height" "$errors_file" "$warnings_file")"

  local lag_blocks="null"
  if [[ "$local_height" != "null" && "$network_tip_height" != "null" ]]; then
    lag_blocks=$(( network_tip_height - local_height ))
  fi

  local triggered_at
  triggered_at="$(_manifest_epoch_to_iso "$triggered_at_epoch")"

  local tmp_file="${manifest_file}.tmp"
  if ! jq -n \
    --arg incident_id "$(basename "$incident_dir")" \
    --arg node "$node" \
    --arg chain "$chain" \
    --arg trigger "$trigger" \
    --arg triggered_at "$triggered_at" \
    --argjson local_height "$local_height" \
    --argjson network_tip_height "$network_tip_height" \
    --argjson lag_blocks "$lag_blocks" \
    --argjson stablevisor_incident_id "$stablevisor_incident_id" \
    --argjson artifacts "$artifacts_json" \
    --rawfile errors_raw "$errors_file" \
    --rawfile warnings_raw "$warnings_file" \
    '{
      schema_version: 1,
      incident_id: $incident_id,
      node: $node,
      chain: $chain,
      trigger: $trigger,
      triggered_at: $triggered_at,
      local_height: $local_height,
      network_tip_height: $network_tip_height,
      lag_blocks: $lag_blocks,
      stablevisor_incident_id: $stablevisor_incident_id,
      artifacts: $artifacts,
      errors: ($errors_raw | split("\n") | map(select(. != ""))),
      warnings: ($warnings_raw | split("\n") | map(select(. != "")))
    }' > "$tmp_file"; then
    rm -f "$tmp_file" "$errors_file" "$warnings_file"
    log_error "manifest_write: failed to build ${manifest_file}"
    return 1
  fi

  rm -f "$errors_file" "$warnings_file"
  mv "$tmp_file" "$manifest_file"
  return 0
}
