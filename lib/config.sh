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
  : "${INCIDENTS_DIR:=/var/lib/node-recorder/incidents}"
  : "${STABLEVISOR_SERVICE_NAME:=stablevisor}"
  : "${PPROF_URL:=http://127.0.0.1:6060/debug/pprof}"
  : "${CPU_PROFILE_SECONDS:=20}"
  : "${HAPROXY_LOG:=/var/log/haproxy.log}"
  : "${LOG_WINDOW_BEFORE_SECONDS:=600}"
  : "${HAPROXY_LOG_MAX_BYTES:=209715200}"

  # STABLEVISOR_SNAPSHOT_BASE_DIR has no sensible default: it is wherever this
  # host's Stablevisor writes its incident snapshots. Validating it here means
  # a deployment mistake fails at daemon startup, not at the first incident.
  local missing=()
  [[ -z "${PROMETHEUS_URL:-}" ]] && missing+=("PROMETHEUS_URL")
  [[ -z "${ALERT_NAME:-}" ]] && missing+=("ALERT_NAME")
  [[ -z "${NODE_ID:-}" ]] && missing+=("NODE_ID")
  [[ -z "${STABLEVISOR_SNAPSHOT_BASE_DIR:-}" ]] && missing+=("STABLEVISOR_SNAPSHOT_BASE_DIR")

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "missing required config: ${missing[*]}"
    return 1
  fi

  local dep
  for dep in jq flock curl zcat; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      log_error "required dependency not found on PATH: $dep"
      return 1
    fi
  done

  export PROMETHEUS_URL ALERT_NAME NODE_ID ALERT_STATE ALERT_NODE_LABEL POLL_INTERVAL_SECONDS COOLDOWN_SECONDS STATE_DIR LOCK_FILE
  export INCIDENTS_DIR STABLEVISOR_SERVICE_NAME STABLEVISOR_SNAPSHOT_BASE_DIR PPROF_URL CPU_PROFILE_SECONDS HAPROXY_LOG LOG_WINDOW_BEFORE_SECONDS HAPROXY_LOG_MAX_BYTES
  return 0
}
