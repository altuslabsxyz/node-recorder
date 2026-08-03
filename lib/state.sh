# shellcheck shell=bash

_state_file() {
  local node="$1"
  local alertname="$2"
  local key
  key="$(printf '%s__%s' "$node" "$alertname" | tr -c 'A-Za-z0-9_.-' '_')"
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

  local STATE="" COOLDOWN_UNTIL=""
  local k v
  while IFS='=' read -r k v; do
    case "$k" in
      STATE) STATE="$v" ;;
      COOLDOWN_UNTIL) COOLDOWN_UNTIL="$v" ;;
    esac
  done < "$file"
  echo "${STATE:-idle}"
}

set_state() {
  local node="$1"
  local alertname="$2"
  local state="$3"
  local cooldown_until="${4:-0}"
  local file

  case "$state" in
    idle|capturing|cooldown) ;;
    *) echo "set_state: invalid state '$state'" >&2; return 1 ;;
  esac
  [[ "$cooldown_until" =~ ^[0-9]+$ ]] || { echo "set_state: invalid cooldown_until '$cooldown_until'" >&2; return 1; }

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

  local STATE="" COOLDOWN_UNTIL=""
  local k v
  while IFS='=' read -r k v; do
    case "$k" in
      STATE) STATE="$v" ;;
      COOLDOWN_UNTIL) COOLDOWN_UNTIL="$v" ;;
    esac
  done < "$file"

  if [[ "${STATE:-idle}" != "cooldown" ]]; then
    return 1
  fi

  # Validate COOLDOWN_UNTIL is numeric before using in arithmetic to prevent
  # command injection from corrupted or malicious state files.
  if [[ ! "$COOLDOWN_UNTIL" =~ ^[0-9]+$ ]]; then
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
