# shellcheck shell=bash

_state_file() {
  local node="$1"
  local alertname="$2"
  local key
  key="$(printf '%s__%s' "$node" "$alertname" | tr '/ ' '__')"
  printf '%s/%s.state' "$STATE_DIR" "$key"
}

get_state() {
  local node="$1"
  local alertname="$2"
  local file
  file="$(_state_file "$node" "$alertname")"

  if [[ ! -f "$file" ]]; then
    echo "idle"
    return 0
  fi

  local STATE COOLDOWN_UNTIL
  # shellcheck disable=SC1090
  source "$file"
  echo "${STATE:-idle}"
}

set_state() {
  local node="$1"
  local alertname="$2"
  local state="$3"
  local cooldown_until="${4:-0}"
  local file
  file="$(_state_file "$node" "$alertname")"

  mkdir -p "$STATE_DIR"
  {
    printf 'STATE=%s\n' "$state"
    printf 'COOLDOWN_UNTIL=%s\n' "$cooldown_until"
  } > "$file"
}

in_cooldown() {
  local node="$1"
  local alertname="$2"
  local file
  file="$(_state_file "$node" "$alertname")"

  if [[ ! -f "$file" ]]; then
    return 1
  fi

  local STATE COOLDOWN_UNTIL
  # shellcheck disable=SC1090
  source "$file"

  if [[ "${STATE:-idle}" != "cooldown" ]]; then
    return 1
  fi

  local now
  now="$(date +%s)"
  if (( now < COOLDOWN_UNTIL )); then
    return 0
  fi

  return 1
}

acquire_run_lock() {
  exec 200>"$LOCK_FILE"
  if ! flock -n 200; then
    return 1
  fi
  return 0
}

release_run_lock() {
  flock -u 200 2>/dev/null || true
  exec 200>&- 2>/dev/null || true
}
