#!/usr/bin/env bash
# lib/slack.sh - incident notification via Slack incoming webhook (Capture
# Flow step 12 in docs/spec/node-recorder.md). Reads SLACK_WEBHOOK_URL from
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

# _slack_s3_object_url <s3_uri>
# Prints the virtual-hosted-style object URL for an s3://bucket/key URI,
# "https://<bucket>.s3.<region>.amazonaws.com/<key>". Shown as the bare URL,
# not as link text, so what renders is exactly where the click goes. Prints
# nothing if the input is not an s3:// URI, leaving the caller to show the
# raw value. The key charset is already URL-safe: incident ids come from the
# sanitized allow-list.
#
# The region comes from S3_REGION, then the AWS SDK's own AWS_DEFAULT_REGION
# and AWS_REGION, so the usual deployment needs no extra setting: install.sh
# already wires /etc/node-recorder/aws-credentials in as an EnvironmentFile.
# With none of them set (an EC2 instance profile takes its region from IMDS,
# not the environment) the URL falls back to the region-less global endpoint,
# which S3 redirects to the right region. Deriving it from the bucket instead
# is not an option: the upload IAM policy grants only PutObject and
# AbortMultipartUpload, so GetBucketLocation would be denied.
#
# Note this URL is not anonymously reachable, since the bucket is private. It
# resolves for a logged-in console session and is the exact path `aws s3 cp`
# takes, which is what the operators reading these notifications want.
_slack_s3_object_url() {
  local uri="$1"
  [[ "$uri" == s3://*/* ]] || return 0

  local rest="${uri#s3://}"
  local bucket="${rest%%/*}"
  local key="${rest#*/}"
  local region="${S3_REGION:-${AWS_DEFAULT_REGION:-${AWS_REGION:-}}}"

  if [[ -n "$region" ]]; then
    printf 'https://%s.s3.%s.amazonaws.com/%s' "$bucket" "$region" "$key"
  else
    printf 'https://%s.s3.amazonaws.com/%s' "$bucket" "$key"
  fi
}

# _slack_build_payload <incident_dir>
# Prints the full webhook JSON: a single color-coded Block Kit attachment,
# with no top-level text (it would render as a duplicate line above the
# attachment). The attachment "fallback" carries a one-line summary for push
# notifications and clients that do not render blocks. Color reflects
# collection health: red when any artifact failed or the upload is pending,
# yellow when there are warnings, green when everything landed. A missing or
# corrupt manifest degrades to the plain-text payload from
# _slack_build_text.
_slack_build_payload() {
  local incident_dir="$1"
  local manifest="$incident_dir/manifest.json"

  if ! jq -e . "$manifest" >/dev/null 2>&1; then
    jq -cn --arg text "$(_slack_build_text "$incident_dir")" '{text: $text}'
    return 0
  fi

  local upload_line color
  if [[ -f "$incident_dir/.uploaded" ]]; then
    local s3_uri object_url
    s3_uri="$(cat "$incident_dir/.uploaded")"
    object_url="$(_slack_s3_object_url "$s3_uri")"
    if [[ -n "$object_url" ]]; then
      upload_line=":package: uploaded: <${object_url}>"
    else
      upload_line=":package: uploaded: \`${s3_uri}\`"
    fi
    color="good"
  else
    upload_line=":hourglass_flowing_sand: upload PENDING - bundle kept at \`${incident_dir}\`"
    color="danger"
  fi
  if [[ "$color" == "good" ]]; then
    if jq -e '((.errors // []) | length) > 0 or ([(.artifacts // {})[]] | any(. != "ok"))' "$manifest" >/dev/null; then
      color="danger"
    elif jq -e '((.warnings // []) | length) > 0' "$manifest" >/dev/null; then
      color="warning"
    fi
  fi

  jq -c --arg upload "$upload_line" --arg color "$color" '
    {
      attachments: [{
        color: $color,
        fallback: ((.trigger // "incident") + " incident " + (.incident_id // "unknown") + " on " + (.node // "?")
                   + " -- " + ([(.artifacts // {})[] | select(. == "ok")] | length | tostring) + "/"
                   + ([(.artifacts // {})[]] | length | tostring) + " artifacts ok"),
        blocks: ([
          {type: "header",
           text: {type: "plain_text", text: (":rotating_light: " + (.trigger // "incident") + " incident"), emoji: true}},
          {type: "section", fields: [
            {type: "mrkdwn", text: ("*Incident*\n`" + (.incident_id // "unknown") + "`")},
            {type: "mrkdwn", text: ("*Node*\n" + (.node // "?") + " (" + (.chain // "?") + ")")},
            {type: "mrkdwn", text: ("*Triggered*\n" + (.triggered_at // "?"))},
            {type: "mrkdwn", text: ("*Lag*\n" + (if .lag_blocks == null then "n/a" else (.lag_blocks | tostring) + " blocks" end))}
          ]},
          {type: "section",
           text: {type: "mrkdwn",
                  text: ("*Artifacts*\n" + ([(.artifacts // {}) | to_entries[] |
                    (if .value == "ok" then ":white_check_mark: " else ":x: " end) + .key] | join("   ")))}}
        ]
        + (if ((.errors // []) | length) > 0 then
            [{type: "section", text: {type: "mrkdwn", text: ("*Errors*\n" + (.errors | map(":x: " + .) | join("\n")))}}]
           else [] end)
        + (if ((.warnings // []) | length) > 0 then
            [{type: "section", text: {type: "mrkdwn", text: ("*Warnings*\n" + (.warnings | map(":warning: " + .) | join("\n")))}}]
           else [] end)
        + [{type: "context", elements: [{type: "mrkdwn", text: $upload}]}])
      }]
    }' "$manifest"
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
  payload="$(_slack_build_payload "$incident_dir")"

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
