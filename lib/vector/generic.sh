#!/usr/bin/env bash
# Generic REST adapter for ingo — wire any HTTP vector API with env vars only.
#
# Required env vars:
#   INGO_VECTOR_URL    — base URL of your vector API (no trailing slash)
#   INGO_VECTOR_TOKEN  — bearer token (set to any value if auth not needed)
#
# Optional env vars:
#   INGO_GENERIC_UPSERT_PATH  — path for upsert  (default: /upsert)
#   INGO_GENERIC_QUERY_PATH   — path for query   (default: /query)
#
# Upsert request (POST application/json):
#   { "id": "...", "text": "...", "namespace": "...", "metadata": { ... } }
#
# Query request (POST application/json):
#   { "query": "...", "top_k": N, "namespace": "..." }
#
# Query response — your endpoint MUST return the ingo normalized shape:
#   {
#     "match_count": N,
#     "matches": [
#       { "id": "...", "score": 0.9, "text": "...",
#         "source": "...", "section": "...", "article": "..." }
#     ]
#   }
#
# Usage:
#   INGO_VECTOR_BACKEND=generic \
#   INGO_VECTOR_URL=https://my-vector-api.internal \
#   INGO_VECTOR_TOKEN=secret \
#   ingo query "pregunta aqui"
#
# See docs/adapter-contract.md to build a fully custom adapter in shell.

set -euo pipefail

ingo_vector_generic_require_env() {
  local missing=0
  if [ -z "${INGO_VECTOR_URL:-}" ]; then
    echo "missing env var: INGO_VECTOR_URL" >&2
    missing=1
  fi
  if [ -z "${INGO_VECTOR_TOKEN:-}" ]; then
    echo "missing env var: INGO_VECTOR_TOKEN" >&2
    missing=1
  fi
  if [ "$missing" -ne 0 ]; then
    return 4
  fi
}

ingo_vector_generic_doctor() {
  ingo_vector_generic_require_env || return $?
  local upsert_path="${INGO_GENERIC_UPSERT_PATH:-/upsert}"
  local query_path="${INGO_GENERIC_QUERY_PATH:-/query}"
  printf "vector: backend=generic url=%s upsert=%s query=%s auth=bearer\n" \
    "${INGO_VECTOR_URL}" "$upsert_path" "$query_path"
}

ingo_vector_generic_upsert_line() {
  local line="$1"
  local namespace="$2"
  local payload response status body
  local id text source section article

  ingo_vector_generic_require_env || return $?

  id="$(printf "%s" "$line" | jq -r '.id // ""')"
  text="$(printf "%s" "$line" | jq -r '.text // ""')"
  source="$(printf "%s" "$line" | jq -r '.source // ""')"
  section="$(printf "%s" "$line" | jq -r '.section // ""')"
  article="$(printf "%s" "$line" | jq -r '.article // ""')"

  payload="$(jq -n \
    --arg id        "$id" \
    --arg text      "$text" \
    --arg namespace "$namespace" \
    --arg source    "$source" \
    --arg section   "$section" \
    --arg article   "$article" \
    '{
      id: $id,
      text: $text,
      namespace: $namespace,
      metadata: { source: $source, section: $section, article: $article }
    }')"

  response="$(ingo_http_curl -sS -w "\n%{http_code}" \
    -X POST "${INGO_VECTOR_URL}${INGO_GENERIC_UPSERT_PATH:-/upsert}" \
    -H "Authorization: Bearer ${INGO_VECTOR_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$payload")"

  status="$(printf "%s" "$response" | tail -n 1)"
  body="$(printf "%s" "$response" | sed '$d')"

  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "upsert failed (status $status): $body" >&2
    return 5
  fi
}

ingo_vector_generic_embed_jsonl() {
  local jsonl="$1"
  local namespace="$2"
  local count=0
  local line

  # shellcheck disable=SC2094
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    line="$(printf "%s" "$line" | LC_ALL=C tr -d '\000-\011\013\014\016-\037\177')"
    ingo_vector_generic_upsert_line "$line" "$namespace"
    count=$((count + 1))
  done < "$jsonl"

  printf "%s\n" "$count"
}

ingo_vector_generic_query_text() {
  local question="$1"
  local top_k="$2"
  local namespace="$3"
  local payload response status body

  ingo_vector_generic_require_env || return $?

  payload="$(jq -n \
    --arg query     "$question" \
    --argjson top_k "$top_k" \
    --arg namespace "$namespace" \
    '{query: $query, top_k: $top_k, namespace: $namespace}')"

  response="$(ingo_http_curl -sS -w "\n%{http_code}" \
    -X POST "${INGO_VECTOR_URL}${INGO_GENERIC_QUERY_PATH:-/query}" \
    -H "Authorization: Bearer ${INGO_VECTOR_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$payload")"

  status="$(printf "%s" "$response" | tail -n 1)"
  body="$(printf "%s" "$response" | sed '$d')"

  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "query failed (status $status): $body" >&2
    return 5
  fi

  printf "%s\n" "$body"
}
