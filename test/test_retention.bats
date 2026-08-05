setup() {
  source "${BATS_TEST_DIRNAME}/../lib/log.sh"
  source "${BATS_TEST_DIRNAME}/../lib/retention.sh"

  INCIDENTS_DIR="$(mktemp -d)"
}

teardown() {
  rm -rf "$INCIDENTS_DIR"
  unset LOCAL_RETENTION_COUNT
}

# make_bundle <id> [uploaded]
make_bundle() {
  mkdir -p "$INCIDENTS_DIR/$1"
  echo '{}' > "$INCIDENTS_DIR/$1/manifest.json"
  [[ "${2:-}" == "uploaded" ]] && touch "$INCIDENTS_DIR/$1/.uploaded"
  return 0
}

@test "retention_prune keeps the newest N uploaded bundles and deletes older ones" {
  make_bundle 20260801T000000Z-block-lag uploaded
  make_bundle 20260802T000000Z-block-lag uploaded
  make_bundle 20260803T000000Z-block-lag uploaded
  export LOCAL_RETENTION_COUNT=2

  run retention_prune "$INCIDENTS_DIR"
  [ "$status" -eq 0 ]

  [ ! -d "$INCIDENTS_DIR/20260801T000000Z-block-lag" ]
  [ -d "$INCIDENTS_DIR/20260802T000000Z-block-lag" ]
  [ -d "$INCIDENTS_DIR/20260803T000000Z-block-lag" ]
}

@test "retention_prune with 0 deletes every uploaded bundle" {
  make_bundle 20260801T000000Z-block-lag uploaded
  make_bundle 20260802T000000Z-block-lag uploaded
  export LOCAL_RETENTION_COUNT=0

  run retention_prune "$INCIDENTS_DIR"
  [ "$status" -eq 0 ]

  [ ! -d "$INCIDENTS_DIR/20260801T000000Z-block-lag" ]
  [ ! -d "$INCIDENTS_DIR/20260802T000000Z-block-lag" ]
}

@test "retention_prune with an explicit empty value deletes nothing" {
  make_bundle 20260801T000000Z-block-lag uploaded
  make_bundle 20260802T000000Z-block-lag uploaded
  export LOCAL_RETENTION_COUNT=""

  run retention_prune "$INCIDENTS_DIR"
  [ "$status" -eq 0 ]

  [ -d "$INCIDENTS_DIR/20260801T000000Z-block-lag" ]
  [ -d "$INCIDENTS_DIR/20260802T000000Z-block-lag" ]
}

@test "retention_prune never deletes a bundle without an .uploaded marker, even the oldest" {
  make_bundle 20260801T000000Z-block-lag
  make_bundle 20260802T000000Z-block-lag uploaded
  make_bundle 20260803T000000Z-block-lag uploaded
  export LOCAL_RETENTION_COUNT=1

  run retention_prune "$INCIDENTS_DIR"
  [ "$status" -eq 0 ]

  [ -d "$INCIDENTS_DIR/20260801T000000Z-block-lag" ]
  [ ! -d "$INCIDENTS_DIR/20260802T000000Z-block-lag" ]
  [ -d "$INCIDENTS_DIR/20260803T000000Z-block-lag" ]
}

@test "retention_prune returns 0 on an empty incidents directory" {
  export LOCAL_RETENTION_COUNT=5

  run retention_prune "$INCIDENTS_DIR"
  [ "$status" -eq 0 ]
}
