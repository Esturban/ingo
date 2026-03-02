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
  local doc_id="" source_url="" canonical_url="" content_sha256="" issuer="" category="" sector=""
  local norm_type="" norm_number="" norm_year="" tags=""

  if [ -n "$meta_file" ] && [ -f "$meta_file" ]; then
    while IFS='=' read -r key value; do
      case "$key" in
        file_path) file_path="$value" ;;
        folder_path) folder_path="$value" ;;
        file_name) file_name="$value" ;;
        file_size_bytes) file_size_bytes="$value" ;;
        file_mtime) file_mtime="$value" ;;
        file_hash) file_hash="$value" ;;
        doc_id) doc_id="$value" ;;
        source_url) source_url="$value" ;;
        canonical_url) canonical_url="$value" ;;
        content_sha256) content_sha256="$value" ;;
        issuer) issuer="$value" ;;
        category) category="$value" ;;
        sector) sector="$value" ;;
        norm_type) norm_type="$value" ;;
        norm_number) norm_number="$value" ;;
        norm_year) norm_year="$value" ;;
        tags) tags="$value" ;;
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
    --arg doc_id "$doc_id" \
    --arg source_url "$source_url" \
    --arg canonical_url "$canonical_url" \
    --arg content_sha256 "$content_sha256" \
    --arg issuer "$issuer" \
    --arg category "$category" \
    --arg sector "$sector" \
    --arg norm_type "$norm_type" \
    --arg norm_number "$norm_number" \
    --arg norm_year "$norm_year" \
    --arg tags "$tags" \
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
          file_hash: (if $file_hash != "" then $file_hash else null end),
          doc_id: (if $doc_id != "" then $doc_id else null end),
          source_url: (if $source_url != "" then $source_url else null end),
          canonical_url: (if $canonical_url != "" then $canonical_url else null end),
          content_sha256: (if $content_sha256 != "" then $content_sha256 else null end),
          issuer: (if $issuer != "" then $issuer else null end),
          category: (if $category != "" then $category else null end),
          sector: (if $sector != "" then $sector else null end),
          norm_type: (if $norm_type != "" then $norm_type else null end),
          norm_number: (if $norm_number != "" then $norm_number else null end),
          norm_year: (if $norm_year != "" then ($norm_year | tonumber) else null end),
          tags: (if $tags != "" then ($tags | split(",") | map(gsub("^[[:space:]]+|[[:space:]]+$";"")) | map(select(length > 0))) else null end)
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

  # shellcheck disable=SC2094
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
