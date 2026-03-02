#!/usr/bin/env bash

set -euo pipefail

ingo_manifest_init() {
  local manifest="$1"
  mkdir -p "$(dirname "$manifest")"
  touch "$manifest"
}

ingo_manifest_append_record() {
  local manifest="$1"
  local record_json="$2"
  ingo_manifest_init "$manifest"
  printf "%s\n" "$record_json" | jq -c '.' >> "$manifest"
}

ingo_manifest_find_first_by_hash() {
  local manifest="$1"
  local content_sha256="$2"
  [ -s "$manifest" ] || return 1

  jq -c -n --arg hash "$content_sha256" --slurpfile rows "$manifest" '
    ($rows[] | select(.content_sha256 == $hash and ((.duplicate_of // "") == ""))) as $match
    | $match
  ' 2>/dev/null | head -n 1
}

ingo_manifest_find_doc_by_id() {
  local manifest="$1"
  local doc_id="$2"
  [ -s "$manifest" ] || return 1

  jq -c -n --arg doc_id "$doc_id" --slurpfile rows "$manifest" '
    ($rows[] | select((.doc_id // "") == $doc_id)) as $match
    | $match
  ' 2>/dev/null | head -n 1
}

ingo_manifest_resolve_duplicate_doc_id() {
  local manifest="$1"
  local content_sha256="$2"
  local existing
  if ! existing="$(ingo_manifest_find_first_by_hash "$manifest" "$content_sha256")"; then
    return 1
  fi
  printf "%s\n" "$existing" | jq -r '.doc_id // empty'
}

ingo_manifest_update_aliases() {
  local manifest="$1"
  local doc_id="$2"
  local alias_url="$3"
  local tmp

  [ -s "$manifest" ] || return 1
  tmp="$(mktemp)"
  jq -c --arg doc_id "$doc_id" --arg alias "$alias_url" '
    if (.doc_id // "") == $doc_id then
      .aliases = (((.aliases // []) + [$alias]) | unique)
    else
      .
    end
  ' "$manifest" > "$tmp"
  mv "$tmp" "$manifest"
}

ingo_manifest_update_doc() {
  local manifest="$1"
  local doc_id="$2"
  local patch_json="$3"
  local tmp

  [ -s "$manifest" ] || return 1
  tmp="$(mktemp)"
  jq -c --arg doc_id "$doc_id" --argjson patch "$patch_json" '
    if (.doc_id // "") == $doc_id then
      . + $patch
    else
      .
    end
  ' "$manifest" > "$tmp"
  mv "$tmp" "$manifest"
}
