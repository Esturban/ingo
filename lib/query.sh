#!/usr/bin/env bash

set -euo pipefail

ingo_query_text() {
  local question="$1"
  local top_k="$2"
  local namespace="$3"
  local payload response status body

  payload="$(jq -n \
    --arg data "$question" \
    --argjson top_k "$top_k" \
    --arg namespace "$namespace" \
    '{data: $data, topK: $top_k, namespace: $namespace, includeMetadata: true, includeData: true}')"

  response="$(ingo_http_curl -sS -w "\n%{http_code}" \
    -X POST "${UPSTASH_VECTOR_REST_URL%/}/query-data" \
    -H "Authorization: Bearer ${UPSTASH_VECTOR_REST_TOKEN}" \
    -H "Content-Type: application/json" \
    -d "$payload")"

  status="$(printf "%s" "$response" | tail -n 1)"
  body="$(printf "%s" "$response" | sed '$d')"

  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "query failed (status $status): $body" >&2
    return 5
  fi

  printf "%s\n" "$body" | jq '
    def rs: (.result // .matches // .vectors // []);
    {
      match_count: (rs | length),
      matches: (
        rs | map({
          id: (.id // ""),
          score: (.score // 0),
          text: (.metadata.text // (if ((.data // null) | type) == "string" then .data else "" end)),
          source: (.metadata.source // ""),
          section: (.metadata.section // ""),
          article: (.metadata.article // ""),
          page: (.metadata.page // null),
          date_indexed: (.metadata.date_indexed // "")
        })
      )
    }'
}
