#!/usr/bin/env bash
# test/test_incident.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/incident.sh"

# Case 1: creates the directory under base_dir, prints its path, and the id
# matches the spec's "<UTC>Z-block-lag" bundle-layout format.
base_dir="$(mktemp -d)"
incident_dir="$(incident_create "$base_dir" "block_lag")"
assert_exit_code 0 "$?" "incident_create succeeds"
assert_dir_exists "$incident_dir" "incident directory exists"
assert_eq "$base_dir" "$(dirname "$incident_dir")" "incident dir is created directly under base_dir"
id="$(basename "$incident_dir")"
[[ "$id" =~ ^[0-9]{8}T[0-9]{6}Z-block-lag$ ]]
assert_exit_code 0 "$?" "incident id matches <YYYYMMDDTHHMMSS>Z-block-lag (got: $id)"

# Case 2: a trigger containing a path separator cannot escape base_dir.
incident_dir2="$(incident_create "$base_dir" "../escape")"
assert_exit_code 0 "$?" "incident_create succeeds with a hostile trigger"
assert_eq "$base_dir" "$(dirname "$incident_dir2")" "sanitized trigger stays directly under base_dir"
id2="$(basename "$incident_dir2")"
assert_eq "..-escape" "${id2#*Z-}" "path separator is replaced, dots kept"

rm -rf "$base_dir"

# Case 3: base_dir not writable -> returns 1 and prints nothing.
ro_dir="$(mktemp -d)"
chmod 0555 "$ro_dir"
out3="$(incident_create "$ro_dir" "block_lag" 2>/dev/null)"
assert_exit_code 1 "$?" "incident_create fails when base_dir is not writable"
assert_eq "" "$out3" "nothing is printed on failure"
chmod 0755 "$ro_dir"
rm -rf "$ro_dir"

# Case 4: a missing base_dir is created on the way (deployment may not have
# pre-created /var/lib/node-recorder/incidents on a fresh host).
parent_dir="$(mktemp -d)"
incident_dir4="$(incident_create "$parent_dir/nested/incidents" "block_lag")"
assert_exit_code 0 "$?" "incident_create creates a missing base_dir"
assert_dir_exists "$incident_dir4" "incident directory exists under the created base_dir"
rm -rf "$parent_dir"

# Case 5: a pre-existing same-name incident directory is a failure, not a
# silent reuse. The real id changes every second, so stub _incident_id to a
# fixed value for a deterministic collision (the same approach the bats tests
# take with curl), then re-source the module to restore it.
base_dir5="$(mktemp -d)"
_incident_id() { printf 'collision-id'; }
incident_dir5="$(incident_create "$base_dir5" "block_lag")"
assert_exit_code 0 "$?" "first incident_create with the stubbed id succeeds"
out5="$(incident_create "$base_dir5" "block_lag" 2>/dev/null)"
assert_exit_code 1 "$?" "incident_create refuses to reuse a pre-existing incident directory"
assert_eq "" "$out5" "nothing is printed on the collision failure"
source "$LIB_DIR/incident.sh"
rm -rf "$base_dir5"
