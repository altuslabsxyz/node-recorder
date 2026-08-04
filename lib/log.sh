# shellcheck shell=bash
# Both levels write to stderr so stdout stays free as a return channel. Several
# lib functions return their value by echoing it (query_alert_state,
# stablevisor_get_pid, get_state, _state_file, _haproxy_epoch_to_iso), and a log
# line on stdout would be captured as part of that value by the caller's command
# substitution.

log_info() {
  printf '%s [INFO] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}

log_error() {
  printf '%s [ERROR] %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" >&2
}
