#!/usr/bin/env bash
# test/fakes/fake_stablevisor.sh <base_dir> <delay_seconds>
# Prints its own PID, then waits for SIGUSR1. On receipt, waits
# delay_seconds, then replays Stablevisor's atomic-write contract: writes
# `.tmp-<id>` under base_dir, renames it to `<id>`, then writes `.complete`
# inside it.

base_dir="$1"
delay_seconds="${2:-0}"

on_usr1() {
  local id="incident-fake-$$"
  local tmp_dir="$base_dir/.tmp-$id"
  mkdir -p "$tmp_dir"
  sleep "$delay_seconds"
  mv "$tmp_dir" "$base_dir/$id"
  touch "$base_dir/$id/.complete"
  exit 0
}

trap on_usr1 USR1
echo $$
while true; do
  sleep 0.2
done
