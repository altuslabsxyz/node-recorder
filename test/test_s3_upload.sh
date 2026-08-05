#!/usr/bin/env bash
# test/test_s3_upload.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"
FAKES_BIN_DIR="$TEST_DIR/fakes/bin"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/s3.sh"

export PATH="$FAKES_BIN_DIR:$PATH"
export S3_PREFIX="s3://bucket/node-recorder"
export CHAIN="stable"
export NODE_ID="node-a"
export S3_UPLOAD_MAX_ATTEMPTS=2

make_incident() {
  local base="$1"
  local dir="$base/20260731T090700Z-block-lag"
  mkdir -p "$dir/pprof"
  echo '{}' > "$dir/manifest.json"
  echo 'profile' > "$dir/pprof/cpu.pb.gz"
  printf '%s' "$dir"
}

# Case 0: the object URI normalizes a trailing slash on S3_PREFIX.
assert_eq "s3://bucket/node-recorder/stable/node-a/x.tar.gz" \
  "$(S3_PREFIX='s3://bucket/node-recorder/' _s3_incident_uri x)" \
  "trailing slash on S3_PREFIX does not produce a double slash"

# Case 1: successful upload writes the .uploaded marker with the URI,
# deletes the tarball, and calls aws against an existing tarball.
incidents_dir="$(mktemp -d)"
incident_dir="$(make_incident "$incidents_dir")"
export FAKE_AWS_LOG="$(mktemp)"
unset FAKE_AWS_EXIT

s3_upload_incident "$incident_dir"
assert_exit_code 0 "$?" "s3_upload_incident succeeds"
assert_file_exists "$incident_dir/.uploaded" "uploaded marker exists"
assert_eq "s3://bucket/node-recorder/stable/node-a/20260731T090700Z-block-lag.tar.gz" \
  "$(cat "$incident_dir/.uploaded")" "marker records the object URI"
assert_eq "1" "$(cat "$incident_dir/.upload-attempts")" "attempt counter is 1"
assert_file_absent "${incident_dir}.tar.gz" "tarball is deleted after a successful upload"
aws_line="$(sed -n '1p' "$FAKE_AWS_LOG")"
assert_eq "s3 cp --only-show-errors ${incident_dir}.tar.gz s3://bucket/node-recorder/stable/node-a/20260731T090700Z-block-lag.tar.gz src_exists=yes" \
  "$aws_line" "aws is called with the tarball and the object URI"
rm -rf "$incidents_dir" "$FAKE_AWS_LOG"

# Case 2: a failed upload keeps the tarball for reuse, records the attempt,
# and writes no marker; the tarball excludes .upload* files and contains the
# bundle contents.
incidents_dir2="$(mktemp -d)"
incident_dir2="$(make_incident "$incidents_dir2")"
export FAKE_AWS_LOG="$(mktemp)"
export FAKE_AWS_EXIT=1

s3_upload_incident "$incident_dir2" 2>/dev/null
assert_exit_code 1 "$?" "s3_upload_incident fails when aws fails"
assert_file_absent "$incident_dir2/.uploaded" "no marker on failure"
assert_eq "1" "$(cat "$incident_dir2/.upload-attempts")" "failed attempt is counted"
assert_file_exists "${incident_dir2}.tar.gz" "tarball is kept for the next attempt"
tar_listing="$(tar -tzf "${incident_dir2}.tar.gz")"
echo "$tar_listing" | grep -q 'manifest.json'
assert_exit_code 0 "$?" "tarball contains the bundle contents"
echo "$tar_listing" | grep -q '.upload'
assert_exit_code 1 "$?" "tarball excludes .upload* retry-state files"

# Case 3: the kept tarball is reused, not rebuilt, on the next attempt.
# ls -i instead of stat: stat's flags differ between GNU and BSD, and the
# repo's helpers keep macOS dev working.
inode_before="$(ls -i "${incident_dir2}.tar.gz" | awk '{print $1}')"
s3_upload_incident "$incident_dir2" 2>/dev/null
assert_exit_code 1 "$?" "second attempt also fails"
assert_eq "2" "$(cat "$incident_dir2/.upload-attempts")" "second attempt is counted"
assert_eq "$inode_before" "$(ls -i "${incident_dir2}.tar.gz" | awk '{print $1}')" "tarball is reused, not rebuilt"

# Case 4: after S3_UPLOAD_MAX_ATTEMPTS failures the incident is skipped
# without calling aws again.
s3_upload_incident "$incident_dir2" 2>/dev/null
assert_exit_code 1 "$?" "attempts at the cap are skipped"
assert_eq "2" "$(cat "$incident_dir2/.upload-attempts")" "skipped attempt does not bump the counter"
assert_eq "2" "$(wc -l < "$FAKE_AWS_LOG")" "aws is not called once the cap is reached"
rm -rf "$incidents_dir2" "$FAKE_AWS_LOG"

# Case 5: the pending scan uploads unmarked incidents, skips uploaded ones
# and half-captured ones (no manifest.json yet), and one failure does not
# stop the scan.
incidents_dir3="$(mktemp -d)"
done_dir="$(make_incident "$incidents_dir3")"
mv "$done_dir" "$incidents_dir3/20260731T080000Z-block-lag"
touch "$incidents_dir3/20260731T080000Z-block-lag/.uploaded"
pending_a="$incidents_dir3/20260731T090000Z-block-lag"
pending_b="$incidents_dir3/20260731T100000Z-block-lag"
mkdir -p "$pending_a" "$pending_b"; echo '{}' > "$pending_a/manifest.json"; echo '{}' > "$pending_b/manifest.json"
half_dir="$incidents_dir3/20260731T110000Z-block-lag"
mkdir -p "$half_dir/pprof"   # capture still in progress: no manifest.json
export FAKE_AWS_LOG="$(mktemp)"
export FAKE_AWS_EXIT=1

s3_upload_pending "$incidents_dir3" 2>/dev/null
assert_exit_code 0 "$?" "s3_upload_pending returns 0 even when uploads fail"
assert_eq "2" "$(wc -l < "$FAKE_AWS_LOG")" "both pending incidents are attempted, the uploaded one is skipped"
assert_file_absent "$half_dir/.uploaded" "a bundle without manifest.json is not uploaded"
assert_file_absent "${half_dir}.tar.gz" "a bundle without manifest.json is not even tarred"

unset FAKE_AWS_EXIT
s3_upload_pending "$incidents_dir3"
assert_file_exists "$pending_a/.uploaded" "first pending incident is uploaded on a later run"
assert_file_exists "$pending_b/.uploaded" "second pending incident is uploaded on a later run"
rm -rf "$incidents_dir3" "$FAKE_AWS_LOG"
