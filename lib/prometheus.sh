# shellcheck shell=bash

# query_first_value <promql>
# Runs an instant query and prints the first series' sample value. Returns 1
# (nothing printed) on a transport failure, a non-200 status, a non-success
# API response, or an empty result set. Used for the operator-supplied height
# queries, so the query text is data here, never inspected.
query_first_value() {
  local query="$1"
  local raw

  if ! raw=$(curl -sS -G --max-time "${PROMETHEUS_TIMEOUT_SECONDS:-10}" --data-urlencode "query=${query}" -w '\n%{http_code}' "${PROMETHEUS_URL}/api/v1/query" 2>&1); then
    log_error "prometheus query failed: ${raw}"
    return 1
  fi

  local http_code="${raw##*$'\n'}"
  local body="${raw%$'\n'*}"

  if [[ "$http_code" != "200" ]]; then
    log_error "prometheus returned HTTP ${http_code}: ${body}"
    return 1
  fi

  if [[ "$(jq -r '.status' <<<"$body" 2>/dev/null)" != "success" ]]; then
    log_error "prometheus returned a non-success response: ${body}"
    return 1
  fi

  local value
  value=$(jq -r '.data.result[0].value[1] // empty' <<<"$body" 2>/dev/null)

  if [[ -z "$value" ]]; then
    log_error "prometheus query returned no result: ${query}"
    return 1
  fi

  printf '%s\n' "$value"
  return 0
}

# verify_node_label_match
# Startup sanity check on the ALERT_NODE_LABEL/NODE_ID pair. PromQL's `=` is an
# exact string match, so a NODE_ID that does not equal the label value
# Prometheus actually carries makes query_alert_state's ALERTS lookup return an
# empty set forever -- which is indistinguishable from "this node is healthy".
# The daemon would poll for years, capture nothing and never complain, so the
# mismatch is worth one loud line at startup. `up` stands in for ALERTS here
# because it exists for every scrape target at all times, while ALERTS is
# legitimately empty whenever nothing is firing. This assumes ALERT_NODE_LABEL
# is a target label, true for the `instance` default; a label attached only by
# the alert rule would not appear on `up` and would be reported as a mismatch.
# Returns 1 on both a mismatch and an unreachable Prometheus: the caller treats
# this as advisory, never as a reason to refuse to start.
verify_node_label_match() {
  if query_first_value "up{${ALERT_NODE_LABEL}=\"${NODE_ID}\"}" >/dev/null; then
    log_info "node label check: ${ALERT_NODE_LABEL}=\"${NODE_ID}\" matches a Prometheus target"
    return 0
  fi

  log_error "node label check failed: no Prometheus target matches ${ALERT_NODE_LABEL}=\"${NODE_ID}\" (the preceding error gives the cause)"
  log_error "if this is a NODE_ID mismatch rather than an unreachable Prometheus, the alert query will always come back empty and no incident will ever be captured"
  return 1
}

query_alert_state() {
  local query="ALERTS{alertname=\"${ALERT_NAME}\", ${ALERT_NODE_LABEL}=\"${NODE_ID}\"}"
  local raw

  if ! raw=$(curl -sS -G --max-time "${PROMETHEUS_TIMEOUT_SECONDS:-10}" --data-urlencode "query=${query}" -w '\n%{http_code}' "${PROMETHEUS_URL}/api/v1/query" 2>&1); then
    log_error "prometheus query failed: ${raw}"
    echo "error"
    return 1
  fi

  local http_code="${raw##*$'\n'}"
  local body="${raw%$'\n'*}"

  if [[ "$http_code" != "200" ]]; then
    log_error "prometheus returned HTTP ${http_code}: ${body}"
    echo "error"
    return 1
  fi

  local status
  status=$(jq -r '.status' <<<"$body" 2>/dev/null)

  if [[ "$status" != "success" ]]; then
    log_error "prometheus returned a non-success response: ${body}"
    echo "error"
    return 1
  fi

  local states
  states=$(jq -r '.data.result[]?.metric.alertstate // empty' <<<"$body" 2>/dev/null)

  if [[ -z "$states" ]]; then
    echo "absent"
    return 0
  fi

  if grep -qx "firing" <<<"$states"; then
    echo "firing"
    return 0
  fi

  if grep -qx "pending" <<<"$states"; then
    log_info "alert ${ALERT_NAME} for ${NODE_ID} is pending, not firing - excluded"
    echo "pending"
    return 0
  fi

  echo "absent"
  return 0
}
