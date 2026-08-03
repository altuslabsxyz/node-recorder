#!/usr/bin/env bash
# lib/haproxy.sh - HAProxy incident log extraction (Capture Flow step 8 in
# docs/spec/node-recorder.md).
# shellcheck shell=bash

# _haproxy_epoch_to_iso <epoch_seconds>
# Prints epoch_seconds as a UTC "YYYY-MM-DDTHH:MM:SS" string. Tries GNU
# date's "-d @<epoch>" syntax first (production/Linux); falls back to BSD
# date's "-r <epoch>" syntax (local dev on macOS) if that fails.
_haproxy_epoch_to_iso() {
  local epoch="$1"
  date -u -d "@${epoch}" +%Y-%m-%dT%H:%M:%S 2>/dev/null && return 0
  date -u -r "${epoch}" +%Y-%m-%dT%H:%M:%S
}
