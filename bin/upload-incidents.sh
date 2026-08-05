#!/usr/bin/env bash
# bin/upload-incidents.sh
#
# Runs Capture Flow step 10 from docs/spec/node-recorder.md: compress and
# upload every incident bundle under INCIDENTS_DIR that has no .uploaded
# marker yet, retrying failed uploads up to S3_UPLOAD_MAX_ATTEMPTS across
# runs.
#
# This is not the full Node Recorder orchestrator described in the spec's
# 12-step Capture Flow (detection, capture, manifest, Slack notification, and
# cleanup live elsewhere). It exists so this ticket's slice of the flow is
# independently runnable and testable before the daemon wiring lands.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$SCRIPT_DIR/../lib" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/s3.sh"

incidents_dir="${INCIDENTS_DIR:?INCIDENTS_DIR is required}"
: "${S3_PREFIX:?S3_PREFIX is required}"
: "${CHAIN:?CHAIN is required}"
: "${NODE_ID:?NODE_ID is required}"

s3_upload_pending "$incidents_dir"

log_info "upload-incidents: done scanning $incidents_dir"
exit 0
