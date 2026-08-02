# shellcheck shell=bash

query_alert_state() {
  local query="ALERTS{alertname=\"${ALERT_NAME}\", ${ALERT_NODE_LABEL}=\"${NODE_ID}\"}"
  local raw

  if ! raw=$(curl -sS -G --data-urlencode "query=${query}" -w '\n%{http_code}' "${PROMETHEUS_URL}/api/v1/query" 2>&1); then
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
    log_info "alert ${ALERT_NAME} for ${NODE_ID} is pending, not firing - excluded" >&2
    echo "pending"
    return 0
  fi

  echo "absent"
  return 0
}
