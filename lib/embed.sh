#!/usr/bin/env bash

set -euo pipefail

ingo_upstash_base_url() {
  printf "%s" "${UPSTASH_VECTOR_REST_URL%/}"
}

ingo_upsert_line() {
  local line="$1"
  local namespace="$2"
  local meta_file="${3:-}"
  local payload response status body
  local file_path="" folder_path="" file_name="" file_size_bytes="" file_mtime="" file_hash=""

  if [ -n "$meta_file" ] && [ -f "$meta_file" ]; then
    while IFS='=' read -r key value; do
      case "$key" in
        file_path) file_path="$value" ;;
        folder_path) folder_path="$value" ;;
        file_name) file_name="$value" ;;
        file_size_bytes) file_size_bytes="$value" ;;
        file_mtime) file_mtime="$value" ;;
        file_hash) file_hash="$value" ;;
      esac
    done < "$meta_file"
  fi

  payload="$(printf "%s" "$line" | jq \
    --arg namespace "$namespace" \
    --arg file_path "$file_path" \
    --arg folder_path "$folder_path" \
    --arg file_name "$file_name" \
    --arg file_size_bytes "$file_size_bytes" \
    --arg file_mtime "$file_mtime" \
    --arg file_hash "$file_hash" \
    '
    {
      id: .id,
      data: .text,
      metadata: (
        {
          text: (.text | tostring | .[0:2000]),
          source: .source,
          section: .section,
          article: .article,
          start: .start,
          end: .end,
          date_indexed: (now | todate),
          file_path: (if $file_path != "" then $file_path else null end),
          folder_path: (if $folder_path != "" then $folder_path else null end),
          file_name: (if $file_name != "" then $file_name else null end),
          file_size_bytes: (if $file_size_bytes != "" then ($file_size_bytes | tonumber) else null end),
          file_mtime: (if $file_mtime != "" then ($file_mtime | tonumber) else null end),
          file_hash: (if $file_hash != "" then $file_hash else null end)
        } | with_entries(select(.value != null))
      ),
      namespace: $namespace
    }'
  )"

  response="$(ingo_http_curl -sS -w "\n%{http_code}" \
    -X POST "$(ingo_upstash_base_url)/upsert-data" \
    -H "Authorization: Bearer ${UPSTASH_VECTOR_REST_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$payload")"

  status="$(printf "%s" "$response" | tail -n 1)"
  body="$(printf "%s" "$response" | sed '$d')"

  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "upsert failed (status $status): $body" >&2
    return 5
  fi
}

ingo_embed_jsonl() {
  local jsonl="$1"
  local namespace="$2"
  local raw_dir="${3:-}"
  local count=0
  local base meta_file

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    line="$(printf "%s" "$line" | LC_ALL=C tr -d '\000-\011\013\014\016-\037\177')"
    if [ -n "$raw_dir" ]; then
      base="$(basename "$jsonl" .jsonl)"
      meta_file="$raw_dir/$base.meta"
    else
      meta_file=""
    fi
    ingo_upsert_line "$line" "$namespace" "$meta_file"
    count=$((count + 1))
  done < "$jsonl"

  printf "%s\n" "$count"
}
