# lib/cometbft.sh - config.toml [rpc] address resolution shared by pprof
# collection (Capture Flow steps 6-7 in docs/spec/node-recorder.md) and
# mempool status collection (Capture Flow step 8).
# shellcheck shell=bash

# _cometbft_toml_value <config_file> <section> <key>
# Prints the double-quoted string value of <key> inside the first
# "[section]" table in config_file. Prints nothing (but still returns 0) if
# the section or key isn't present -- callers distinguish "found vs. not
# found" themselves via an empty check, since every value this module reads
# (an address) is invalid when empty anyway. Returns 1 only when
# config_file itself can't be read.
_cometbft_toml_value() {
  local config_file="$1"
  local section="$2"
  local key="$3"

  [[ -r "$config_file" ]] || return 1

  awk -v section="[$section]" -v key="$key" '
    $0 == section { in_section = 1; next }
    /^\[/ { in_section = 0 }
    in_section && $0 ~ "^[[:space:]]*" key "[[:space:]]*=" {
      line = $0
      sub(/^[^"]*"/, "", line)
      sub(/".*$/, "", line)
      print line
      exit
    }
  ' "$config_file"
  return 0
}

# _cometbft_normalize_host <host:port>
# Replaces an empty or "0.0.0.0" host with "127.0.0.1" (a bind-all address
# isn't dialable); passes any other host through unchanged. Node Recorder
# always polls its own local node, so this substitution is always safe.
_cometbft_normalize_host() {
  local hostport="$1"
  local host="${hostport%%:*}"
  local port="${hostport##*:}"

  if [[ -z "$host" || "$host" == "0.0.0.0" ]]; then
    host="127.0.0.1"
  fi

  printf '%s:%s\n' "$host" "$port"
}

# cometbft_rpc_url <daemon_home>
# Prints the RPC base URL (e.g. "http://127.0.0.1:26657") built from
# "[rpc].laddr" in <daemon_home>/config/config.toml. Returns 1 if the config
# file is unreadable, laddr is unset, or laddr isn't a "tcp://" address
# (e.g. a unix socket) -- unsupported, same failure as any other resolution
# problem.
cometbft_rpc_url() {
  local daemon_home="$1"
  local config_file="$daemon_home/config/config.toml"

  local raw
  raw="$(_cometbft_toml_value "$config_file" "rpc" "laddr")" || return 1

  if [[ "$raw" != tcp://* ]]; then
    return 1
  fi

  local normalized
  normalized="$(_cometbft_normalize_host "${raw#tcp://}")"

  printf 'http://%s\n' "$normalized"
  return 0
}

# cometbft_pprof_url <daemon_home>
# Prints the pprof base URL (e.g. "http://127.0.0.1:6060/debug/pprof") built
# from "[rpc].pprof_laddr" in <daemon_home>/config/config.toml (a bare
# "host:port", unlike laddr's "tcp://" prefix). Returns 1 if the config file
# is unreadable or pprof_laddr is empty -- an operator can leave
# pprof_laddr blank to disable it, which this treats the same as any other
# can't-find-the-address failure.
cometbft_pprof_url() {
  local daemon_home="$1"
  local config_file="$daemon_home/config/config.toml"

  local raw
  raw="$(_cometbft_toml_value "$config_file" "rpc" "pprof_laddr")" || return 1

  if [[ -z "$raw" ]]; then
    return 1
  fi

  local normalized
  normalized="$(_cometbft_normalize_host "$raw")"

  printf 'http://%s/debug/pprof\n' "$normalized"
  return 0
}
