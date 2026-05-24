#!/usr/bin/env bash

set -euo pipefail

ingo_vector_qdrant_base_url() {
  printf "%s" "${INGO_VECTOR_URL%/}"
}

ingo_vector_qdrant_api_key_args() {
  if [ -n "${INGO_VECTOR_TOKEN:-}" ]; then
    printf "%s\n" "-H" "api-key: ${INGO_VECTOR_TOKEN}"
  fi
}

ingo_vector_qdrant_require_env() {
  if [ -z "${INGO_VECTOR_URL:-}" ]; then
    echo "missing env var: INGO_VECTOR_URL" >&2
    return 4
  fi
}

ingo_vector_qdrant_require_text_inference() {
  if [ -z "${INGO_VECTOR_MODEL:-}" ]; then
    echo "vector backend 'qdrant' requires INGO_VECTOR_MODEL for provider-side text inference; bring-your-own embeddings are not implemented yet" >&2
    return 7
  fi
}

ingo_vector_qdrant_doctor() {
  ingo_vector_qdrant_require_env || return $?
  ingo_vector_qdrant_require_text_inference || return $?
  printf "vector: backend=qdrant collection=%s url=%s api_key=%s inference_model=%s\n" \
    "$INGO_NAMESPACE" \
    "$(ingo_vector_qdrant_base_url)" \
    "$([ -n "${INGO_VECTOR_TOKEN:-}" ] && printf "present" || printf "absent")" \
    "$INGO_VECTOR_MODEL"
}

ingo_vector_qdrant_build_payload_fields() {
  local line="$1"
  local meta_file="${2:-}"
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

  printf "%s" "$line" | jq \
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
      source: .source,
      section: .section,
      article: .article,
      start: .start,
      end: .end,
      text: (.text | tostring | .[0:2000]),
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
    '
}

ingo_vector_qdrant_upsert_line() {
  local line="$1"
  local namespace="$2"
  local meta_file="${3:-}"
  local payload_fields payload response status body
  local -a headers

  ingo_vector_qdrant_require_env || return $?
  ingo_vector_qdrant_require_text_inference || return $?

  headers=()
  if [ -n "${INGO_VECTOR_TOKEN:-}" ]; then
    headers+=(-H "api-key: ${INGO_VECTOR_TOKEN}")
  fi
  payload_fields="$(ingo_vector_qdrant_build_payload_fields "$line" "$meta_file")"
  payload="$(printf "%s" "$line" | jq \
    --argjson payload "$payload_fields" \
    --arg model "$INGO_VECTOR_MODEL" \
    '
    {
      points: [
        {
          id: .id,
          vector: {
            text: .text,
            model: $model
          },
          payload: $payload
        }
      ]
    }'
  )"

  response="$(ingo_http_curl -sS -w "\n%{http_code}" \
    -X PUT "$(ingo_vector_qdrant_base_url)/collections/${namespace}/points?wait=true" \
    -H "Content-Type: application/json" \
    "${headers[@]}" \
    -d "$payload")"

  status="$(printf "%s" "$response" | tail -n 1)"
  body="$(printf "%s" "$response" | sed '$d')"

  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "upsert failed (status $status): $body" >&2
    return 5
  fi
}

ingo_vector_qdrant_embed_jsonl() {
  local jsonl="$1"
  local namespace="$2"
  local raw_dir="${3:-}"
  local count=0
  local base meta_file line

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    line="$(printf "%s" "$line" | LC_ALL=C tr -d '\000-\011\013\014\016-\037\177')"
    if [ -n "$raw_dir" ]; then
      base="$(basename "$jsonl" .jsonl)"
      meta_file="$raw_dir/$base.meta"
    else
      meta_file=""
    fi
    ingo_vector_qdrant_upsert_line "$line" "$namespace" "$meta_file"
    count=$((count + 1))
  done < "$jsonl"

  printf "%s\n" "$count"
}

ingo_vector_qdrant_query_text() {
  local question="$1"
  local top_k="$2"
  local namespace="$3"
  local payload response status body
  local -a headers

  ingo_vector_qdrant_require_env || return $?
  ingo_vector_qdrant_require_text_inference || return $?

  headers=()
  if [ -n "${INGO_VECTOR_TOKEN:-}" ]; then
    headers+=(-H "api-key: ${INGO_VECTOR_TOKEN}")
  fi
  payload="$(jq -n \
    --arg question "$question" \
    --arg model "$INGO_VECTOR_MODEL" \
    --argjson top_k "$top_k" \
    '{
      query: {
        text: $question,
        model: $model
      },
      limit: $top_k,
      with_payload: true
    }')"

  response="$(ingo_http_curl -sS -w "\n%{http_code}" \
    -X POST "$(ingo_vector_qdrant_base_url)/collections/${namespace}/points/query" \
    -H "Content-Type: application/json" \
    "${headers[@]}" \
    -d "$payload")"

  status="$(printf "%s" "$response" | tail -n 1)"
  body="$(printf "%s" "$response" | sed '$d')"

  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "query failed (status $status): $body" >&2
    return 5
  fi

  printf "%s\n" "$body" | jq '
    def rs: (.result.points // .result // .points // []);
    {
      match_count: (rs | length),
      matches: (
        rs | map({
          id: (.id | tostring // ""),
          score: (.score // 0),
          text: (.payload.text // ""),
          source: (.payload.source // ""),
          section: (.payload.section // ""),
          article: (.payload.article // ""),
          page: (.payload.page // null),
          date_indexed: (.payload.date_indexed // "")
        })
      )
    }'
}
