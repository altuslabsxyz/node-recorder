#!/usr/bin/env bash
# lib/stablevisor.sh - Stablevisor PID lookup, SIGUSR1, and snapshot
# confirmation (Capture Flow step 5 in docs/spec/node-recorder.md).

# _stablevisor_show_value <systemctl_show_output> <property>
# Prints the value of <property> from `systemctl show` key=value output.
# Parsed by key rather than by line position because the order systemd
# prints requested properties in is not guaranteed across versions.
_stablevisor_show_value() {
  local raw="$1"
  local key="$2"
  local line

  while IFS= read -r line; do
    if [[ "$line" == "${key}="* ]]; then
      printf '%s\n' "${line#*=}"
      return 0
    fi
  done <<<"$raw"

  return 0
}

# stablevisor_get_pid
# Prints the Stablevisor MainPID to stdout on success. Returns 1 (nothing
# printed) if STABLEVISOR_SERVICE_NAME is unset, systemctl fails, the unit
# does not exist, or MainPID is 0 (unit loaded but not running). Never calls
# exit, so a missing STABLEVISOR_SERVICE_NAME is a normal failure return,
# not a shell exit.
#
# Every failure path logs, and a non-existent unit is reported differently
# from a stopped one. The distinction matters because the two need opposite
# responses: a wrong STABLEVISOR_SERVICE_NAME is a config typo to fix here,
# while a stopped unit is a problem on the Stablevisor side. Both used to
# return silently and surface only as manifest.json's undifferentiated
# "stablevisor_snapshot: trigger or confirmation failed".
stablevisor_get_pid() {
  if [[ -z "${STABLEVISOR_SERVICE_NAME:-}" ]]; then
    log_error "stablevisor_get_pid: STABLEVISOR_SERVICE_NAME is not set"
    return 1
  fi

  local raw
  if ! raw="$(systemctl show "$STABLEVISOR_SERVICE_NAME" --property=LoadState,MainPID 2>/dev/null)"; then
    log_error "stablevisor_get_pid: systemctl show failed for unit '${STABLEVISOR_SERVICE_NAME}'"
    return 1
  fi

  local load_state pid
  load_state="$(_stablevisor_show_value "$raw" "LoadState")"
  pid="$(_stablevisor_show_value "$raw" "MainPID")"

  if [[ "$load_state" == "not-found" ]]; then
    log_error "stablevisor_get_pid: no systemd unit named '${STABLEVISOR_SERVICE_NAME}'; set STABLEVISOR_SERVICE_NAME to the real unit (systemctl list-units --type=service lists them)"
    return 1
  fi

  if [[ -z "$pid" || "$pid" == "0" ]]; then
    log_error "stablevisor_get_pid: unit '${STABLEVISOR_SERVICE_NAME}' exists but is not running (MainPID=0)"
    return 1
  fi

  printf '%s\n' "$pid"
  return 0
}

# verify_stablevisor_unit
# Startup counterpart to verify_node_label_match in lib/prometheus.sh: a
# wrong STABLEVISOR_SERVICE_NAME is invisible until the first incident, and
# then it only shows up as one failed artifact inside manifest.json, which
# reads the same as "this node has no Stablevisor". Checking once at startup
# turns that into a line an operator sees while they are still deploying.
# stablevisor_get_pid has already logged the specific cause, so this adds
# only the consequence. Returns 1 on any resolution failure; the caller
# treats it as advisory and never refuses to start.
verify_stablevisor_unit() {
  local pid
  if pid="$(stablevisor_get_pid)"; then
    log_info "stablevisor unit check: '${STABLEVISOR_SERVICE_NAME}' is running (pid ${pid})"
    return 0
  fi

  log_error "stablevisor unit check failed: incident captures will record stablevisor_snapshot as an error until this is resolved"
  return 1
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
