#!/usr/bin/env bash
# lib/s3.sh - incident bundle compression and S3 upload (Capture Flow step 11
# in docs/spec/node-recorder.md). Reads S3_PREFIX, CHAIN, and NODE_ID from the
# environment; S3_UPLOAD_MAX_ATTEMPTS caps retries (default 5).
# shellcheck shell=bash

# _s3_incident_uri <incident_id>
# Prints the bundle's object URI, "${S3_PREFIX}/${CHAIN}/${NODE_ID}/<id>.tar.gz".
_s3_incident_uri() {
  printf '%s/%s/%s/%s.tar.gz' "${S3_PREFIX%/}" "$CHAIN" "$NODE_ID" "$1"
}

# _s3_ensure_tarball <incident_dir>
# Prints the path of "<incident_dir>.tar.gz", building it first if it does not
# exist. The bundle directory is immutable once capture finishes, so a tarball
# left behind by a failed upload is reused rather than rebuilt. Built via a
# .tmp path and renamed, so a partial build never leaves a tarball at the
# final path. The .upload* retry-state files are excluded from the archive.
_s3_ensure_tarball() {
  local incident_dir="$1"
  local tarball="${incident_dir}.tar.gz"

  if [[ ! -f "$tarball" ]]; then
    if ! tar -C "$(dirname "$incident_dir")" --exclude='.upload*' \
        -czf "${tarball}.tmp" "$(basename "$incident_dir")"; then
      rm -f "${tarball}.tmp"
      log_error "_s3_ensure_tarball: failed to build $tarball"
      return 1
    fi
    mv "${tarball}.tmp" "$tarball"
  fi

  printf '%s\n' "$tarball"
  return 0
}

# s3_upload_incident <incident_dir>
# Uploads the incident's tarball to S3. Each attempt bumps the directory's
# .upload-attempts counter first, so a crash mid-upload still counts; once the
# counter reaches S3_UPLOAD_MAX_ATTEMPTS the incident is skipped instead of
# retried forever. On success writes the S3 URI into an .uploaded marker and
# deletes the tarball (the bundle directory itself is retention's job, step
# 12). Returns 1 on a failed or skipped attempt.
s3_upload_incident() {
  local incident_dir="$1"
  local max_attempts="${S3_UPLOAD_MAX_ATTEMPTS:-5}"
  local attempts_file="$incident_dir/.upload-attempts"

  local attempts
  attempts="$(cat "$attempts_file" 2>/dev/null)"
  [[ "$attempts" =~ ^[0-9]+$ ]] || attempts=0

  if (( attempts >= max_attempts )); then
    log_error "s3_upload_incident: giving up on $incident_dir after ${attempts} attempts"
    return 1
  fi
  echo "$(( attempts + 1 ))" > "$attempts_file"

  local tarball
  if ! tarball="$(_s3_ensure_tarball "$incident_dir")"; then
    return 1
  fi

  local uri
  uri="$(_s3_incident_uri "$(basename "$incident_dir")")"

  if ! aws s3 cp --only-show-errors "$tarball" "$uri"; then
    log_error "s3_upload_incident: upload failed for $incident_dir (attempt $(( attempts + 1 ))/${max_attempts})"
    return 1
  fi

  printf '%s\n' "$uri" > "$incident_dir/.uploaded"
  rm -f "$tarball"
  log_info "s3_upload_incident: uploaded $incident_dir to $uri"
  return 0
}

# s3_upload_pending <incidents_dir>
# Attempts an upload for every complete incident directory that has no
# .uploaded marker yet, oldest first (incident ids sort chronologically).
# Completeness means manifest.json exists: run_capture writes it last, so it
# doubles as the bundle's completion marker (the same contract Stablevisor's
# .complete file provides) -- uploading earlier would snapshot a half-written
# bundle and the .uploaded marker would then keep the finished bundle from
# ever being retried. One incident failing does not stop the others; always
# returns 0 so a bad cycle cannot take the caller down.
s3_upload_pending() {
  local incidents_dir="$1"

  local incident_dir
  for incident_dir in "$incidents_dir"/*/; do
    incident_dir="${incident_dir%/}"
    [[ -d "$incident_dir" ]] || continue
    [[ -f "$incident_dir/.uploaded" ]] && continue
    [[ -f "$incident_dir/manifest.json" ]] || continue
    s3_upload_incident "$incident_dir" || true
  done
  return 0
}
