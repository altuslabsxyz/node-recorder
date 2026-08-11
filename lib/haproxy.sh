#!/usr/bin/env bash
# lib/haproxy.sh - HAProxy incident log extraction (Capture Flow step 9 in
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

# _haproxy_candidate_files <log_path> <start_iso>
# Prints, oldest-first, the existing files that need scanning for a
# window starting at start_iso: the previous day's rotated file
# ("<log_path>.1.gz" if present, else "<log_path>.1" if present) only
# when the live file's first line's timestamp is already later than
# start_iso, then log_path itself. Caller must ensure log_path exists.
_haproxy_candidate_files() {
  local log_path="$1"
  local start_iso="$2"

  local first_line first_ts
  first_line="$(head -n 1 "$log_path" 2>/dev/null)"
  first_ts="${first_line:0:19}"

  if [[ -n "$first_ts" && "$first_ts" > "$start_iso" ]]; then
    if [[ -f "${log_path}.1.gz" ]]; then
      printf '%s\n' "${log_path}.1.gz"
    elif [[ -f "${log_path}.1" ]]; then
      printf '%s\n' "${log_path}.1"
    fi
  fi

  printf '%s\n' "$log_path"
}

# haproxy_extract_window <results_file> <log_path> <start_epoch> <end_epoch> <out_file> <max_bytes>
# Extracts lines from log_path (and, if needed, its previous day's
# rotated file) whose timestamp falls within [start_epoch, end_epoch]
# into out_file, oldest-first, truncated to the newest max_bytes bytes if
# the filtered result is larger. Always records the outcome via
# record_result under the "haproxy_log" key. Returns 0 on success (even
# with zero matching lines or truncation applied); returns 1 if log_path
# does not exist or is not readable, in which case out_file is not
# created.
haproxy_extract_window() {
  local results_file="$1"
  local log_path="$2"
  local start_epoch="$3"
  local end_epoch="$4"
  local out_file="$5"
  local max_bytes="$6"

  if [[ ! -r "$log_path" ]]; then
    record_result "$results_file" "haproxy_log" "error" "log file not found or not readable: $log_path"
    return 1
  fi

  local start_iso end_iso
  start_iso="$(_haproxy_epoch_to_iso "$start_epoch")"
  end_iso="$(_haproxy_epoch_to_iso "$end_epoch")"

  local tmp_file="${out_file}.tmp"
  rm -f "$tmp_file"
  : > "$tmp_file"

  local file
  while IFS= read -r file; do
    zcat -f "$file" 2>/dev/null | _haproxy_filter_lines "$start_iso" "$end_iso" >> "$tmp_file"
  done < <(_haproxy_candidate_files "$log_path" "$start_iso")

  local actual_bytes
  actual_bytes="$(wc -c < "$tmp_file" | tr -d ' ')"

  if (( actual_bytes > max_bytes )); then
    tail -c "$max_bytes" "$tmp_file" > "${tmp_file}.trunc"
    mv "${tmp_file}.trunc" "$tmp_file"
    mv "$tmp_file" "$out_file"
    record_result "$results_file" "haproxy_log" "ok" "truncated to ${max_bytes} bytes (window was ${actual_bytes} bytes)"
    return 0
  fi

  mv "$tmp_file" "$out_file"
  record_result "$results_file" "haproxy_log" "ok"
  return 0
}
