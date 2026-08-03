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

# _haproxy_filter_lines <start_iso> <end_iso>
# Reads lines from stdin, prints to stdout only those whose leading
# timestamp field (its first 19 characters) falls within
# [start_iso, end_iso] inclusive, compared as plain strings. start_iso and
# end_iso must each be exactly 19 characters ("YYYY-MM-DDTHH:MM:SS").
_haproxy_filter_lines() {
  local start_iso="$1"
  local end_iso="$2"
  awk -v start="$start_iso" -v end="$end_iso" '
    {
      ts = substr($1, 1, 19)
      if (ts >= start && ts <= end) print
    }
  '
}
