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
