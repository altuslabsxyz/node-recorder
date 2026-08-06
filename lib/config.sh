# shellcheck shell=bash

source "$(dirname "${BASH_SOURCE[0]}")/log.sh"

load_config() {
  local config_file="${NODE_RECORDER_CONFIG:-/etc/node-recorder/config}"

  if [[ -f "$config_file" ]]; then
    # shellcheck disable=SC1090
    source "$config_file"
  fi

  : "${ALERT_STATE:=firing}"
  : "${PROMETHEUS_TIMEOUT_SECONDS:=10}"
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
  : "${S3_PREFIX:=s3://node-recorder-snapshot}"
  : "${S3_UPLOAD_MAX_ATTEMPTS:=5}"
  # Empty is a valid operator choice: notification is best-effort and
  # skipped with a warning when no webhook is configured.
  : "${SLACK_WEBHOOK_URL:=}"
  # ${VAR-default} (no colon) on purpose: unset gets the default, but an
  # explicit empty value means "retention off" and must survive.
  : "${LOCAL_RETENTION_COUNT-5}"
  LOCAL_RETENTION_COUNT="${LOCAL_RETENTION_COUNT-5}"
  # Empty height queries are a valid operator choice: the manifest records
  # null heights with a warning instead of failing (see the spec's Manifest
  # decisions).
  : "${LOCAL_HEIGHT_QUERY:=}"
  : "${NETWORK_TIP_HEIGHT_QUERY:=}"

  # STABLEVISOR_SNAPSHOT_BASE_DIR has no sensible default: it is wherever this
  # host's Stablevisor writes its incident snapshots. CHAIN labels the
  # manifest (and, later, the S3 bundle path). Validating them here means a
  # deployment mistake fails at daemon startup, not at the first incident.
  local missing=()
  [[ -z "${PROMETHEUS_URL:-}" ]] && missing+=("PROMETHEUS_URL")
  [[ -z "${ALERT_NAME:-}" ]] && missing+=("ALERT_NAME")
  [[ -z "${NODE_ID:-}" ]] && missing+=("NODE_ID")
  [[ -z "${CHAIN:-}" ]] && missing+=("CHAIN")
  [[ -z "${STABLEVISOR_SNAPSHOT_BASE_DIR:-}" ]] && missing+=("STABLEVISOR_SNAPSHOT_BASE_DIR")

  if [[ ${#missing[@]} -gt 0 ]]; then
    log_error "missing required config: ${missing[*]}"
    return 1
  fi

  # Numeric settings feed sleep and bash arithmetic; a non-numeric value
  # would otherwise kill the daemon at its first use (a crash loop via
  # Restart=always, or a death at the first incident) instead of failing
  # startup with a message that names the offending variable. Leading zeros
  # are rejected too: bash arithmetic reads them as octal, which either dies
  # ("0900") or silently computes the wrong number ("020" is 16).
  local num_var
  for num_var in POLL_INTERVAL_SECONDS COOLDOWN_SECONDS PROMETHEUS_TIMEOUT_SECONDS CPU_PROFILE_SECONDS LOG_WINDOW_BEFORE_SECONDS HAPROXY_LOG_MAX_BYTES S3_UPLOAD_MAX_ATTEMPTS; do
    if [[ ! "${!num_var}" =~ ^(0|[1-9][0-9]*)$ ]]; then
      log_error "config value must be a whole number of seconds/bytes/attempts: ${num_var}='${!num_var}'"
      return 1
    fi
  done
  # LOCAL_RETENTION_COUNT sits outside the loop: empty is valid (retention
  # off), but anything else must be a whole number.
  if [[ -n "$LOCAL_RETENTION_COUNT" && ! "$LOCAL_RETENTION_COUNT" =~ ^(0|[1-9][0-9]*)$ ]]; then
    log_error "config value must be a whole number or empty: LOCAL_RETENTION_COUNT='${LOCAL_RETENTION_COUNT}'"
    return 1
  fi

  local dep
  for dep in jq flock curl zcat tar aws; do
    if ! command -v "$dep" >/dev/null 2>&1; then
      log_error "required dependency not found on PATH: $dep"
      if [[ "$dep" == "aws" ]]; then
        log_error "install the AWS CLI v2 before starting the daemon: https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html"
      fi
      return 1
    fi
  done

  export PROMETHEUS_URL PROMETHEUS_TIMEOUT_SECONDS ALERT_NAME NODE_ID CHAIN ALERT_STATE ALERT_NODE_LABEL POLL_INTERVAL_SECONDS COOLDOWN_SECONDS STATE_DIR LOCK_FILE
  export INCIDENTS_DIR STABLEVISOR_SERVICE_NAME STABLEVISOR_SNAPSHOT_BASE_DIR PPROF_URL CPU_PROFILE_SECONDS HAPROXY_LOG LOG_WINDOW_BEFORE_SECONDS HAPROXY_LOG_MAX_BYTES
  export LOCAL_HEIGHT_QUERY NETWORK_TIP_HEIGHT_QUERY S3_PREFIX S3_UPLOAD_MAX_ATTEMPTS SLACK_WEBHOOK_URL LOCAL_RETENTION_COUNT
  return 0
}
