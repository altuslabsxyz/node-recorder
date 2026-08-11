#!/usr/bin/env bash
# test/test_cometbft_config.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/cometbft.sh"

_write_config_toml() {
  local daemon_home="$1"
  shift
  mkdir -p "$daemon_home/config"
  printf '%s\n' "$@" > "$daemon_home/config/config.toml"
}

daemon_home="$(mktemp -d)"

# _cometbft_toml_value: finds a key inside its own section.
_write_config_toml "$daemon_home" \
  '[rpc]' \
  'laddr = "tcp://0.0.0.0:26657"' \
  'pprof_laddr = "localhost:6060"'
value="$(_cometbft_toml_value "$daemon_home/config/config.toml" "rpc" "laddr")"
assert_eq "tcp://0.0.0.0:26657" "$value" "_cometbft_toml_value finds a key inside its section"

# _cometbft_toml_value: a same-named key in a different section is not
# matched.
_write_config_toml "$daemon_home" \
  '[p2p]' \
  'laddr = "tcp://0.0.0.0:26656"' \
  '[rpc]' \
  'pprof_laddr = "localhost:6060"'
value2="$(_cometbft_toml_value "$daemon_home/config/config.toml" "rpc" "laddr")"
assert_eq "" "$value2" "_cometbft_toml_value does not match a same-named key from a different section"

# _cometbft_toml_value: missing config file.
value3="$(_cometbft_toml_value "/nonexistent/config.toml" "rpc" "laddr" 2>/dev/null)"
assert_exit_code 1 "$?" "_cometbft_toml_value fails on a missing config file"
assert_eq "" "$value3" "nothing is printed for a missing config file"

# _cometbft_normalize_host
assert_eq "127.0.0.1:26657" "$(_cometbft_normalize_host "0.0.0.0:26657")" "0.0.0.0 is normalized to 127.0.0.1"
assert_eq "127.0.0.1:6060" "$(_cometbft_normalize_host ":6060")" "an empty host is normalized to 127.0.0.1"
assert_eq "localhost:6060" "$(_cometbft_normalize_host "localhost:6060")" "a concrete host passes through unchanged"

# cometbft_rpc_url: happy path, bind-all address is normalized.
_write_config_toml "$daemon_home" '[rpc]' 'laddr = "tcp://0.0.0.0:26657"' 'pprof_laddr = "localhost:6060"'
url="$(cometbft_rpc_url "$daemon_home")"
assert_exit_code 0 "$?" "cometbft_rpc_url succeeds when laddr is set"
assert_eq "http://127.0.0.1:26657" "$url" "cometbft_rpc_url normalizes 0.0.0.0 and adds the http scheme"

# cometbft_rpc_url: unsupported scheme (unix socket).
_write_config_toml "$daemon_home" '[rpc]' 'laddr = "unix:///tmp/cometbft.sock"'
out_unix="$(cometbft_rpc_url "$daemon_home" 2>/dev/null)"
assert_exit_code 1 "$?" "cometbft_rpc_url fails on a non-tcp:// scheme"
assert_eq "" "$out_unix" "nothing is printed for an unsupported scheme"

# cometbft_pprof_url: happy path.
_write_config_toml "$daemon_home" '[rpc]' 'laddr = "tcp://0.0.0.0:26657"' 'pprof_laddr = "localhost:6060"'
purl="$(cometbft_pprof_url "$daemon_home")"
assert_exit_code 0 "$?" "cometbft_pprof_url succeeds when pprof_laddr is set"
assert_eq "http://localhost:6060/debug/pprof" "$purl" "cometbft_pprof_url adds the http scheme and /debug/pprof suffix"

# cometbft_pprof_url: an empty pprof_laddr (operator disabled pprof) fails
# the same way any other unresolvable address does.
_write_config_toml "$daemon_home" '[rpc]' 'laddr = "tcp://0.0.0.0:26657"' 'pprof_laddr = ""'
out_empty="$(cometbft_pprof_url "$daemon_home" 2>/dev/null)"
assert_exit_code 1 "$?" "cometbft_pprof_url fails when pprof_laddr is empty"
assert_eq "" "$out_empty" "nothing is printed when pprof_laddr is empty"

rm -rf "$daemon_home"

# cometbft_rpc_url / cometbft_pprof_url: config.toml does not exist at all.
missing_daemon_home="$(mktemp -d)"
out_missing="$(cometbft_rpc_url "$missing_daemon_home" 2>/dev/null)"
assert_exit_code 1 "$?" "cometbft_rpc_url fails when config.toml does not exist"
assert_eq "" "$out_missing" "nothing is printed when config.toml does not exist"
rm -rf "$missing_daemon_home"
