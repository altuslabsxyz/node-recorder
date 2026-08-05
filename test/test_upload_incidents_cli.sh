#!/usr/bin/env bash
# test/test_upload_incidents_cli.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BIN_DIR="$(cd "$TEST_DIR/../bin" && pwd)"
FAKES_BIN_DIR="$TEST_DIR/fakes/bin"

# Case 1: full successful run over one pending incident.
incidents_dir="$(mktemp -d)"
mkdir -p "$incidents_dir/20260731T090700Z-block-lag"
echo '{}' > "$incidents_dir/20260731T090700Z-block-lag/manifest.json"
aws_log="$(mktemp)"

PATH="$FAKES_BIN_DIR:$PATH" \
  INCIDENTS_DIR="$incidents_dir" S3_PREFIX="s3://bucket/node-recorder" \
  CHAIN="stable" NODE_ID="node-a" FAKE_AWS_LOG="$aws_log" \
  bash "$BIN_DIR/upload-incidents.sh" 2>/dev/null
assert_exit_code 0 "$?" "entrypoint exits 0 on a successful run"
assert_file_exists "$incidents_dir/20260731T090700Z-block-lag/.uploaded" "entrypoint uploads the pending incident"

# Case 2: a missing required variable fails fast.
out="$(INCIDENTS_DIR="$incidents_dir" S3_PREFIX= CHAIN=stable NODE_ID=node-a bash "$BIN_DIR/upload-incidents.sh" 2>&1)"
assert_exit_code 1 "$?" "entrypoint fails when S3_PREFIX is empty"

rm -rf "$incidents_dir" "$aws_log"
