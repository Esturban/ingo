#!/usr/bin/env bash

set -euo pipefail

ingo_upstash_base_url() {
  printf "%s" "${UPSTASH_VECTOR_REST_URL%/}"
}

ingo_upsert_line() {
  local line="$1"
  local namespace="$2"
  local payload response status body

  payload="$(printf "%s" "$line" | jq --arg namespace "$namespace" '
    {
      id: .id,
      data: .text,
      metadata: {
        text: (.text | tostring | .[0:2000]),
        source: .source,
        section: .section,
        article: .article,
        start: .start,
        end: .end,
        date_indexed: (now | todate)
      },
      namespace: $namespace
    }'
  )"

  response="$(curl -sS -w "\n%{http_code}" \
    -X POST "$(ingo_upstash_base_url)/upsert" \
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
  local count=0

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    ingo_upsert_line "$line" "$namespace"
    count=$((count + 1))
  done < "$jsonl"

  printf "%s\n" "$count"
}
