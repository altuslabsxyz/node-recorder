#!/usr/bin/env bash
# lib/slack.sh - incident notification via Slack incoming webhook (Capture
# Flow step 11 in docs/spec/node-recorder.md). Reads SLACK_WEBHOOK_URL from
# the environment; SLACK_TIMEOUT_SECONDS caps the POST (default 10).
# shellcheck shell=bash

# _slack_build_text <incident_dir>
# Prints the human-readable message body for the incident, built from
# manifest.json and the .uploaded marker. A missing or corrupt manifest
# degrades to a note rather than failing: the operator should hear about the
# incident even when the bundle is broken.
_slack_build_text() {
  local incident_dir="$1"
  local manifest="$incident_dir/manifest.json"

  local upload_line
  if [[ -f "$incident_dir/.uploaded" ]]; then
    upload_line="uploaded: $(cat "$incident_dir/.uploaded")"
  else
    upload_line="upload PENDING - bundle kept at ${incident_dir}"
  fi

  if ! jq -e . "$manifest" >/dev/null 2>&1; then
    printf 'node-recorder incident %s\nmanifest missing or unreadable\n%s\n' \
      "$(basename "$incident_dir")" "$upload_line"
    return 0
  fi

  jq -r --arg upload "$upload_line" '
    "node-recorder incident \(.incident_id)\n" +
    "node \(.node) chain \(.chain) trigger \(.trigger) at \(.triggered_at)\n" +
    "artifacts: " + (.artifacts | to_entries | map("\(.key)=\(.value)") | join(", ")) + "\n" +
    (if (.errors | length) > 0 then "errors: " + (.errors | join("; ")) + "\n" else "" end) +
    (if (.warnings | length) > 0 then "warnings: " + (.warnings | join("; ")) + "\n" else "" end) +
    $upload' "$manifest"
}

# slack_notify_incident <incident_dir>
# POSTs the incident summary to SLACK_WEBHOOK_URL. An unset or empty webhook
# URL logs and skips with 0: notification is best-effort by design (see the
# spec's Slack Notification decisions). Returns 1 on a transport failure or
# a non-200 response.
slack_notify_incident() {
  local incident_dir="$1"
  local timeout_seconds="${SLACK_TIMEOUT_SECONDS:-10}"

  if [[ -z "${SLACK_WEBHOOK_URL:-}" ]]; then
    log_info "slack_notify_incident: SLACK_WEBHOOK_URL not configured, skipping notification"
    return 0
  fi

  local payload
  payload="$(jq -cn --arg text "$(_slack_build_text "$incident_dir")" '{text: $text}')"

  local http_code
  if ! http_code="$(curl -sS --max-time "$timeout_seconds" -X POST \
      -H 'Content-type: application/json' --data "$payload" \
      -o /dev/null -w '%{http_code}' "$SLACK_WEBHOOK_URL" 2>&1)"; then
    log_error "slack_notify_incident: webhook POST failed: ${http_code}"
    return 1
  fi

  if [[ "$http_code" != "200" ]]; then
    log_error "slack_notify_incident: webhook returned HTTP ${http_code}"
    return 1
  fi

  log_info "slack_notify_incident: notified for $(basename "$incident_dir")"
  return 0
}
