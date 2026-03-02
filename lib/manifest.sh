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

ingo_manifest_reset() {
  local manifest="$1"
  mkdir -p "$(dirname "$manifest")"
  : > "$manifest"
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

ingo_manifest_has_url() {
  local manifest="$1"
  local url="$2"
  [ -s "$manifest" ] || return 1
  jq -e --arg url "$url" '
    select((.source_url // "") == $url or (.final_url // "") == $url or ((.aliases // []) | index($url) != null))
  ' "$manifest" >/dev/null 2>&1
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

ingo_manifest_append_doc_record() {
  local manifest="$1"
  local doc_id="$2"
  local status="$3"
  local source_url="$4"
  local final_url="$5"
  local discovered_from_url="$6"
  local host="$7"
  local mime_type="$8"
  local file_ext="$9"
  local local_path="${10}"
  local content_sha256="${11}"
  local bytes="${12}"
  local fetched_at="${13}"
  local last_seen_at="${14}"
  local duplicate_of="${15:-}"

  ingo_manifest_append_record "$manifest" "$(jq -cn \
    --arg doc_id "$doc_id" \
    --arg status "$status" \
    --arg source_url "$source_url" \
    --arg final_url "$final_url" \
    --arg discovered_from_url "$discovered_from_url" \
    --arg host "$host" \
    --arg mime_type "$mime_type" \
    --arg file_ext "$file_ext" \
    --arg local_path "$local_path" \
    --arg content_sha256 "$content_sha256" \
    --arg bytes "$bytes" \
    --arg fetched_at "$fetched_at" \
    --arg last_seen_at "$last_seen_at" \
    --arg duplicate_of "$duplicate_of" \
    '{
      doc_id: $doc_id,
      status: $status,
      source_url: $source_url,
      final_url: $final_url,
      discovered_from_url: $discovered_from_url,
      host: $host,
      mime_type: $mime_type,
      file_ext: $file_ext,
      local_path: $local_path,
      content_sha256: $content_sha256,
      bytes: ($bytes|tonumber),
      fetched_at: $fetched_at,
      last_seen_at: $last_seen_at
    } + (if $duplicate_of != "" then {duplicate_of: $duplicate_of} else {} end)')"
}
