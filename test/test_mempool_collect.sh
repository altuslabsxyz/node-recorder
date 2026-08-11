#!/usr/bin/env bash
# test/test_mempool_collect.sh
TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$(cd "$TEST_DIR/../lib" && pwd)"
source "$LIB_DIR/common.sh"
source "$LIB_DIR/cometbft.sh"
source "$LIB_DIR/mempool.sh"

_make_daemon_home() {
  local port="$1"
  local daemon_home
  daemon_home="$(mktemp -d)"
  mkdir -p "$daemon_home/config"
  printf '[rpc]\nladdr = "tcp://127.0.0.1:%s"\n' "$port" > "$daemon_home/config/config.toml"
  printf '%s\n' "$daemon_home"
}

_start_fake_rpc() {
  local mode="$1"
  local server_out
  server_out="$(mktemp)"
  FAKE_RPC_MODE="$mode" python3 "$TEST_DIR/fakes/fake_cometbft_rpc_server.py" 0 > "$server_out" &
  echo "$!" > "${server_out}.pid"
  sleep 0.3
  printf '%s\n' "$server_out"
}

_stop_fake_rpc() {
  local server_out="$1"
  local pid
  pid="$(cat "${server_out}.pid")"
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  rm -f "$server_out" "${server_out}.pid"
}

out_dir="$(mktemp -d)"
results_file="$out_dir/results.tsv"

# Case 1: success.
server_out="$(_start_fake_rpc ok)"
port="$(cat "$server_out")"
daemon_home="$(_make_daemon_home "$port")"

mempool_collect "$results_file" "$daemon_home" "$out_dir/mempool.json" 5
assert_exit_code 0 "$?" "mempool_collect succeeds on 200 with valid JSON"
assert_file_exists "$out_dir/mempool.json" "mempool.json written on success"
line="$(grep '^mempool_status' "$results_file")"
assert_eq "ok" "$(printf '%s' "$line" | cut -f2)" "mempool_status recorded as ok"

_stop_fake_rpc "$server_out"
rm -rf "$daemon_home"

# Case 2: malformed JSON body.
: > "$results_file"
server_out="$(_start_fake_rpc malformed)"
port="$(cat "$server_out")"
daemon_home="$(_make_daemon_home "$port")"

mempool_collect "$results_file" "$daemon_home" "$out_dir/mempool2.json" 5
assert_exit_code 1 "$?" "mempool_collect fails on malformed JSON"
assert_file_absent "$out_dir/mempool2.json" "no file left behind on malformed JSON"
line2="$(grep '^mempool_status' "$results_file")"
assert_eq "error" "$(printf '%s' "$line2" | cut -f2)" "malformed JSON recorded as error"
printf '%s' "$line2" | cut -f3 | grep -q "malformed JSON"
assert_exit_code 0 "$?" "error reason names the malformed JSON"

_stop_fake_rpc "$server_out"
rm -rf "$daemon_home"

# Case 3: HTTP 500.
: > "$results_file"
server_out="$(_start_fake_rpc error)"
port="$(cat "$server_out")"
daemon_home="$(_make_daemon_home "$port")"

mempool_collect "$results_file" "$daemon_home" "$out_dir/mempool3.json" 5
assert_exit_code 1 "$?" "mempool_collect fails on HTTP 500"
assert_file_absent "$out_dir/mempool3.json" "no file left behind on http error"

_stop_fake_rpc "$server_out"
rm -rf "$daemon_home"

# Case 4: empty body.
: > "$results_file"
server_out="$(_start_fake_rpc empty)"
port="$(cat "$server_out")"
daemon_home="$(_make_daemon_home "$port")"

mempool_collect "$results_file" "$daemon_home" "$out_dir/mempool4.json" 5
assert_exit_code 1 "$?" "mempool_collect fails on an empty body"
assert_file_absent "$out_dir/mempool4.json" "no file left behind on empty body"

_stop_fake_rpc "$server_out"
rm -rf "$daemon_home"

# Case 5: curl times out before the server responds.
: > "$results_file"
server_out="$(_start_fake_rpc slow)"
port="$(cat "$server_out")"
daemon_home="$(_make_daemon_home "$port")"

mempool_collect "$results_file" "$daemon_home" "$out_dir/mempool5.json" 1
assert_exit_code 1 "$?" "mempool_collect fails when curl times out first"
assert_file_absent "$out_dir/mempool5.json" "no file left behind on timeout"
assert_file_absent "$out_dir/mempool5.json.tmp" "no tmp file left behind on timeout"

_stop_fake_rpc "$server_out"
rm -rf "$daemon_home"

# Case 6: the RPC address cannot be resolved (no config.toml at all) -- no
# network call is even attempted.
: > "$results_file"
no_config_daemon_home="$(mktemp -d)"

mempool_collect "$results_file" "$no_config_daemon_home" "$out_dir/mempool6.json" 5
assert_exit_code 1 "$?" "mempool_collect fails when the RPC address cannot be resolved"
assert_file_absent "$out_dir/mempool6.json" "no file written when the RPC address cannot be resolved"
line6="$(grep '^mempool_status' "$results_file")"
assert_eq "error" "$(printf '%s' "$line6" | cut -f2)" "resolution failure recorded as error"

rm -rf "$no_config_daemon_home" "$out_dir"
