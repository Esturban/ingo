#!/usr/bin/env bash
# External embedding module — produces float vectors from plain text.
#
# Activated when INGO_EMBEDDING_MODE=external.
#
# Required env:
#   INGO_EMBEDDER_BACKEND  — ollama | openai | voyage | cohere | together
#
# Per-backend env (see ingo_embedder_doctor for defaults):
#   INGO_EMBEDDER_URL     — API base URL (default varies by backend)
#   INGO_EMBEDDER_MODEL   — model name  (default varies by backend)
#   INGO_EMBEDDER_TOKEN   — Bearer token (required for cloud backends)
#
# ingo_http_curl must be available in the calling shell (lib/http.sh).

set -euo pipefail

_ingo_embedder_openai_compat() {
  local text="$1"
  local url="${INGO_EMBEDDER_URL}"
  local model="${INGO_EMBEDDER_MODEL}"
  local token="${INGO_EMBEDDER_TOKEN:-}"
  local payload response status body

  payload="$(jq -n --arg model "$model" --arg input "$text" '{model:$model,input:$input}')"

  local -a auth_args=()
  if [ -n "$token" ]; then
    auth_args=(-H "Authorization: Bearer ${token}")
  fi

  response="$(ingo_http_curl -sS -w "\n%{http_code}" \
    -X POST "${url}/v1/embeddings" \
    -H "Content-Type: application/json" \
    "${auth_args[@]}" \
    -d "$payload")"

  status="$(printf "%s" "$response" | tail -n 1)"
  body="$(printf "%s" "$response" | sed '$d')"

  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "embedder error (status $status): $body" >&2
    return 5
  fi

  printf "%s" "$body" | jq -c '.data[0].embedding'
}

_ingo_embedder_ollama() {
  local text="$1"
  local url="${INGO_EMBEDDER_URL:-http://localhost:11434}"
  local model="${INGO_EMBEDDER_MODEL:-nomic-embed-text}"
  local payload response status body

  payload="$(jq -n --arg model "$model" --arg input "$text" '{model:$model,input:$input}')"

  response="$(ingo_http_curl -sS -w "\n%{http_code}" \
    -X POST "${url}/api/embed" \
    -H "Content-Type: application/json" \
    -d "$payload")"

  status="$(printf "%s" "$response" | tail -n 1)"
  body="$(printf "%s" "$response" | sed '$d')"

  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "embedder error (status $status): $body" >&2
    return 5
  fi

  printf "%s" "$body" | jq -c '.embeddings[0]'
}

_ingo_embedder_voyage() {
  local text="$1"
  local mode="${2:-document}"
  local url="${INGO_EMBEDDER_URL:-https://api.voyageai.com}"
  local model="${INGO_EMBEDDER_MODEL:-voyage-multilingual-2}"
  local token="${INGO_EMBEDDER_TOKEN:-}"
  local input_type payload response status body

  [ -n "$token" ] || { echo "missing env var: INGO_EMBEDDER_TOKEN" >&2; return 4; }

  input_type="$([ "$mode" = "query" ] && printf "query" || printf "document")"

  # Voyage requires an array for "input", not a bare string.
  payload="$(jq -n \
    --arg model      "$model" \
    --arg input      "$text" \
    --arg input_type "$input_type" \
    '{model:$model,input:[$input],input_type:$input_type}')"

  response="$(ingo_http_curl -sS -w "\n%{http_code}" \
    -X POST "${url}/v1/embeddings" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${token}" \
    -d "$payload")"

  status="$(printf "%s" "$response" | tail -n 1)"
  body="$(printf "%s" "$response" | sed '$d')"

  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "embedder error (status $status): $body" >&2
    return 5
  fi

  printf "%s" "$body" | jq -c '.data[0].embedding'
}

_ingo_embedder_cohere() {
  local text="$1"
  local mode="${2:-document}"
  local url="${INGO_EMBEDDER_URL:-https://api.cohere.com}"
  local model="${INGO_EMBEDDER_MODEL:-embed-v4.0}"
  local token="${INGO_EMBEDDER_TOKEN:-}"
  local input_type payload response status body

  [ -n "$token" ] || { echo "missing env var: INGO_EMBEDDER_TOKEN" >&2; return 4; }

  # Cohere uses different input_type names than Voyage.
  input_type="$([ "$mode" = "query" ] && printf "search_query" || printf "search_document")"

  payload="$(jq -n \
    --arg model      "$model" \
    --arg text       "$text" \
    --arg input_type "$input_type" \
    '{model:$model,texts:[$text],input_type:$input_type,embedding_types:["float"]}')"

  response="$(ingo_http_curl -sS -w "\n%{http_code}" \
    -X POST "${url}/v2/embed" \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer ${token}" \
    -d "$payload")"

  status="$(printf "%s" "$response" | tail -n 1)"
  body="$(printf "%s" "$response" | sed '$d')"

  if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
    echo "embedder error (status $status): $body" >&2
    return 5
  fi

  # Cohere nests under embeddings.float[0], unlike OpenAI-shaped APIs.
  printf "%s" "$body" | jq -c '.embeddings.float[0]'
}

# Public API ----------------------------------------------------------------

# Return a compact JSON float array for the given text.
# mode: "document" (default, for upsert) | "query" (for retrieval)
ingo_embedder_text() {
  local text="$1"
  local mode="${2:-document}"
  local backend="${INGO_EMBEDDER_BACKEND:-ollama}"

  case "$backend" in
    ollama)
      _ingo_embedder_ollama "$text"
      ;;
    openai)
      INGO_EMBEDDER_URL="${INGO_EMBEDDER_URL:-https://api.openai.com}"
      INGO_EMBEDDER_MODEL="${INGO_EMBEDDER_MODEL:-text-embedding-3-small}"
      [ -n "${INGO_EMBEDDER_TOKEN:-}" ] || { echo "missing env var: INGO_EMBEDDER_TOKEN" >&2; return 4; }
      _ingo_embedder_openai_compat "$text"
      ;;
    together)
      INGO_EMBEDDER_URL="${INGO_EMBEDDER_URL:-https://api.together.xyz}"
      INGO_EMBEDDER_MODEL="${INGO_EMBEDDER_MODEL:-intfloat/multilingual-e5-large-instruct}"
      [ -n "${INGO_EMBEDDER_TOKEN:-}" ] || { echo "missing env var: INGO_EMBEDDER_TOKEN" >&2; return 4; }
      _ingo_embedder_openai_compat "$text"
      ;;
    voyage)
      _ingo_embedder_voyage "$text" "$mode"
      ;;
    cohere)
      _ingo_embedder_cohere "$text" "$mode"
      ;;
    *)
      echo "unknown embedder backend: '$backend'" >&2
      echo "  supported: ollama, openai, voyage, cohere, together" >&2
      return 2
      ;;
  esac
}

ingo_embedder_doctor() {
  local backend="${INGO_EMBEDDER_BACKEND:-ollama}"
  case "$backend" in
    ollama)
      printf "embedder: backend=ollama url=%s model=%s auth=none\n" \
        "${INGO_EMBEDDER_URL:-http://localhost:11434}" \
        "${INGO_EMBEDDER_MODEL:-nomic-embed-text}"
      ;;
    openai)
      [ -n "${INGO_EMBEDDER_TOKEN:-}" ] || { echo "missing env var: INGO_EMBEDDER_TOKEN" >&2; return 4; }
      printf "embedder: backend=openai url=%s model=%s auth=bearer\n" \
        "${INGO_EMBEDDER_URL:-https://api.openai.com}" \
        "${INGO_EMBEDDER_MODEL:-text-embedding-3-small}"
      ;;
    together)
      [ -n "${INGO_EMBEDDER_TOKEN:-}" ] || { echo "missing env var: INGO_EMBEDDER_TOKEN" >&2; return 4; }
      printf "embedder: backend=together url=%s model=%s auth=bearer\n" \
        "${INGO_EMBEDDER_URL:-https://api.together.xyz}" \
        "${INGO_EMBEDDER_MODEL:-intfloat/multilingual-e5-large-instruct}"
      ;;
    voyage)
      [ -n "${INGO_EMBEDDER_TOKEN:-}" ] || { echo "missing env var: INGO_EMBEDDER_TOKEN" >&2; return 4; }
      printf "embedder: backend=voyage url=%s model=%s auth=bearer\n" \
        "${INGO_EMBEDDER_URL:-https://api.voyageai.com}" \
        "${INGO_EMBEDDER_MODEL:-voyage-multilingual-2}"
      ;;
    cohere)
      [ -n "${INGO_EMBEDDER_TOKEN:-}" ] || { echo "missing env var: INGO_EMBEDDER_TOKEN" >&2; return 4; }
      printf "embedder: backend=cohere url=%s model=%s auth=bearer\n" \
        "${INGO_EMBEDDER_URL:-https://api.cohere.com}" \
        "${INGO_EMBEDDER_MODEL:-embed-v4.0}"
      ;;
    *)
      echo "unknown embedder backend: '$backend'" >&2
      echo "  supported: ollama, openai, voyage, cohere, together" >&2
      return 2
      ;;
  esac
}
