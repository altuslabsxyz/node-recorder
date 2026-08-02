#!/usr/bin/env bash
# lib/stablevisor.sh - Stablevisor PID lookup, SIGUSR1, and snapshot
# confirmation (Capture Flow step 5 in docs/spec/node-recorder.md).

# stablevisor_get_pid
# Prints the Stablevisor MainPID to stdout on success. Returns 1 (nothing
# printed) if STABLEVISOR_SERVICE_NAME is unset, systemctl fails, or
# MainPID is 0 (service not running). Never calls exit, so a missing
# STABLEVISOR_SERVICE_NAME is a normal failure return, not a shell exit.
stablevisor_get_pid() {
  if [[ -z "${STABLEVISOR_SERVICE_NAME:-}" ]]; then
    log_error "stablevisor_get_pid: STABLEVISOR_SERVICE_NAME is not set"
    return 1
  fi

  local pid
  if ! pid="$(systemctl show "$STABLEVISOR_SERVICE_NAME" --property=MainPID --value 2>/dev/null)"; then
    return 1
  fi

  if [[ -z "$pid" || "$pid" == "0" ]]; then
    return 1
  fi

  printf '%s\n' "$pid"
  return 0
}

# stablevisor_trigger_snapshot <base_dir> <out_var_name>
# Sends SIGUSR1 to the PID from stablevisor_get_pid, then polls base_dir
# for a directory that: did not exist before signaling, does not have a
# .tmp- prefix, and contains a .complete marker (Stablevisor's atomic
# write contract). On success, writes that directory's name into the
# variable named by out_var_name and returns 0. On timeout or PID
# resolution failure, returns 1.
stablevisor_trigger_snapshot() {
  local _snapshot_base_dir="$1"
  local _snapshot_out_var_name="$2"
  local _snapshot_timeout_seconds="${STABLEVISOR_SNAPSHOT_TIMEOUT_SECONDS:-30}"
  local _snapshot_poll_interval_seconds="${STABLEVISOR_SNAPSHOT_POLL_INTERVAL_SECONDS:-1}"

  local _snapshot_pid
  if ! _snapshot_pid="$(stablevisor_get_pid)"; then
    log_error "stablevisor_trigger_snapshot: could not resolve Stablevisor PID"
    return 1
  fi

  local _snapshot_before_entries
  _snapshot_before_entries="$(mktemp)"
  ( cd "$_snapshot_base_dir" && ls -A ) > "$_snapshot_before_entries" 2>/dev/null

  if ! kill -USR1 "$_snapshot_pid" 2>/dev/null; then
    log_error "stablevisor_trigger_snapshot: failed to send SIGUSR1 to pid $_snapshot_pid"
    rm -f "$_snapshot_before_entries"
    return 1
  fi

  local _snapshot_elapsed=0
  local _snapshot_found=""
  while (( _snapshot_elapsed < _snapshot_timeout_seconds )); do
    local _snapshot_candidate
    while IFS= read -r _snapshot_candidate; do
      [[ "$_snapshot_candidate" == .tmp-* ]] && continue
      grep -qxF "$_snapshot_candidate" "$_snapshot_before_entries" && continue
      if [[ -f "$_snapshot_base_dir/$_snapshot_candidate/.complete" ]]; then
        _snapshot_found="$_snapshot_candidate"
        break
      fi
    done < <(cd "$_snapshot_base_dir" && ls -A 2>/dev/null)

    [[ -n "$_snapshot_found" ]] && break
    sleep "$_snapshot_poll_interval_seconds"
    _snapshot_elapsed=$((_snapshot_elapsed + _snapshot_poll_interval_seconds))
  done

  rm -f "$_snapshot_before_entries"

  if [[ -z "$_snapshot_found" ]]; then
    log_error "stablevisor_trigger_snapshot: timed out after ${_snapshot_timeout_seconds}s waiting for .complete marker"
    return 1
  fi

  printf -v "$_snapshot_out_var_name" '%s' "$_snapshot_found"
  return 0
}
