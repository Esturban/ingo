#!/usr/bin/env bash

set -euo pipefail

VECTOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:=$(cd "$VECTOR_LIB_DIR/.." && pwd)}"

# shellcheck source=vector/upstash.sh
# shellcheck disable=SC1091
source "$VECTOR_LIB_DIR/vector/upstash.sh"
# shellcheck source=vector/qdrant.sh
# shellcheck disable=SC1091
source "$VECTOR_LIB_DIR/vector/qdrant.sh"

ingo_vector_backend_resolve() {
  local backend="${INGO_VECTOR_BACKEND:-upstash}"
  case "$backend" in
    upstash|qdrant)
      printf "%s\n" "$backend"
      ;;
    *)
      echo "unknown vector backend: $backend (supported: upstash, qdrant)" >&2
      return 2
      ;;
  esac
}

ingo_vector_backend_doctor() {
  local backend
  backend="$(ingo_vector_backend_resolve)"
  case "$backend" in
    upstash)
      ingo_vector_upstash_doctor
      ;;
    qdrant)
      ingo_vector_qdrant_doctor
      ;;
  esac
}

ingo_vector_backend_embed_jsonl() {
  local jsonl="$1"
  local namespace="$2"
  local raw_dir="${3:-}"
  local backend

  backend="$(ingo_vector_backend_resolve)"
  case "$backend" in
    upstash)
      ingo_vector_upstash_embed_jsonl "$jsonl" "$namespace" "$raw_dir"
      ;;
    qdrant)
      ingo_vector_qdrant_embed_jsonl "$jsonl" "$namespace" "$raw_dir"
      ;;
  esac
}

ingo_vector_require_normalized_query_json() {
  local backend="$1"
  local json="$2"

  if ! printf "%s\n" "$json" | jq -e '
    (.match_count | type) == "number" and
    (.matches | type) == "array" and
    ((.matches | all(
      (.id | type) == "string" and
      (.score | type) == "number" and
      (.text | type) == "string" and
      (.source | type) == "string" and
      (.section | type) == "string" and
      (.article | type) == "string"
    )))
  ' >/dev/null 2>&1; then
    echo "query contract failed: backend $backend returned invalid normalized payload" >&2
    return 5
  fi

  printf "%s\n" "$json"
}

ingo_vector_backend_query_text() {
  local question="$1"
  local top_k="$2"
  local namespace="$3"
  local backend json status

  backend="$(ingo_vector_backend_resolve)"
  case "$backend" in
    upstash)
      set +e
      json="$(ingo_vector_upstash_query_text "$question" "$top_k" "$namespace")"
      status=$?
      set -e
      ;;
    qdrant)
      set +e
      json="$(ingo_vector_qdrant_query_text "$question" "$top_k" "$namespace")"
      status=$?
      set -e
      ;;
  esac

  if [ "$status" -ne 0 ]; then
    return "$status"
  fi

  ingo_vector_require_normalized_query_json "$backend" "$json"
}
