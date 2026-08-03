# shellcheck shell=bash

source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

load_config() {
  local config_file="${NODE_RECORDER_CONFIG:-/etc/node-recorder/config}"

  if [[ -f "$config_file" ]]; then
    # shellcheck disable=SC1090
    source "$config_file"
  fi

  : "${ALERT_STATE:=firing}"
  : "${ALERT_NODE_LABEL:=instance}"
  : "${POLL_INTERVAL_SECONDS:=15}"
  : "${COOLDOWN_SECONDS:=900}"
  : "${STATE_DIR:=/var/lib/node-recorder/state}"
  : "${LOCK_FILE:=/run/node-recorder.lock}"

  local missing=()
  [[ -z "${PROMETHEUS_URL:-}" ]] && missing+=("PROMETHEUS_URL")
  [[ -z "${ALERT_NAME:-}" ]] && missing+=("ALERT_NAME")
  [[ -z "${NODE_ID:-}" ]] && missing+=("NODE_ID")

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "missing required config: ${missing[*]}"
    return 1
  fi

  local dep
  for dep in jq flock; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      log_error "required dependency not found on PATH: $dep"
      return 1
    fi
  done

  export PROMETHEUS_URL ALERT_NAME NODE_ID ALERT_STATE ALERT_NODE_LABEL POLL_INTERVAL_SECONDS COOLDOWN_SECONDS STATE_DIR LOCK_FILE
  return 0
}
