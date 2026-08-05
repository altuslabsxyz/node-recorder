# shellcheck shell=bash

# query_first_value <promql>
# Runs an instant query and prints the first series' sample value. Returns 1
# (nothing printed) on a transport failure, a non-200 status, a non-success
# API response, or an empty result set. Used for the operator-supplied height
# queries, so the query text is data here, never inspected.
query_first_value() {
  local query="$1"
  local raw

  if ! raw=$(curl -sS -G --data-urlencode "query=${query}" -w '\n%{http_code}' "${PROMETHEUS_URL}/api/v1/query" 2>&1); then
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
    log_info "alert ${ALERT_NAME} for ${NODE_ID} is pending, not firing - excluded"
    echo "pending"
    return 0
  fi

  echo "absent"
  return 0
}
