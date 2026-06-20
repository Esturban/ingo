#!/usr/bin/env bash

set -euo pipefail

VECTOR_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
: "${ROOT_DIR:=$(cd "$VECTOR_LIB_DIR/.." && pwd)}"

# Built-in adapters are sourced eagerly so shellcheck can trace them.
# shellcheck source=vector/upstash.sh
# shellcheck disable=SC1091
source "$VECTOR_LIB_DIR/vector/upstash.sh"
# shellcheck source=vector/qdrant.sh
# shellcheck disable=SC1091
source "$VECTOR_LIB_DIR/vector/qdrant.sh"
# shellcheck source=vector/pinecone.sh
# shellcheck disable=SC1091
source "$VECTOR_LIB_DIR/vector/pinecone.sh"

# Convert a backend name to a function-name slug (hyphens become underscores).
_ingo_vector_slug() {
  local name="$1"
  case "$name" in
    *[!a-zA-Z0-9_-]*)
      echo "invalid backend name: '$name' (only a-z, 0-9, hyphens, underscores)" >&2
      return 2
      ;;
  esac
  printf "%s" "${name//-/_}"
}

# Load the adapter for a backend if not already loaded.
# Resolution order:
#   1. Already-loaded (no-op — built-ins are sourced at module load time above)
#   2. INGO_VECTOR_ADAPTER=/path/to/adapter.sh  (external, user-supplied)
#   3. lib/vector/<backend>.sh                  (built-in discovered by name)
_ingo_vector_load_adapter() {
  local backend="$1"
  local slug
  slug="$(_ingo_vector_slug "$backend")"

  # Already loaded.
  if declare -F "ingo_vector_${slug}_doctor" >/dev/null 2>&1; then
    return 0
  fi

  # External adapter supplied by caller.
  if [ -n "${INGO_VECTOR_ADAPTER:-}" ]; then
    if [ ! -f "$INGO_VECTOR_ADAPTER" ]; then
      echo "INGO_VECTOR_ADAPTER file not found: $INGO_VECTOR_ADAPTER" >&2
      return 2
    fi
    # shellcheck disable=SC1090
    source "$INGO_VECTOR_ADAPTER"
    return 0
  fi

  # Auto-discover a built-in by filename.
  local adapter_file="$VECTOR_LIB_DIR/vector/${backend}.sh"
  if [ -f "$adapter_file" ]; then
    # shellcheck disable=SC1090
    source "$adapter_file"
    return 0
  fi

  local available
  available="$(find "$VECTOR_LIB_DIR/vector" -maxdepth 1 -name '*.sh' \
    | sed 's|.*/||; s|\.sh$||' | sort | tr '\n' ',' | sed 's/,$//')"
  echo "unknown vector backend: '$backend'" >&2
  echo "  built-ins: $available" >&2
  echo "  or set INGO_VECTOR_ADAPTER=/path/to/adapter.sh for a custom backend" >&2
  return 2
}

# Assert that an adapter function is defined after loading.
_ingo_vector_require_fn() {
  local backend="$1"
  local fn="$2"
  if ! declare -F "$fn" >/dev/null 2>&1; then
    echo "adapter for backend '$backend' does not implement ${fn}()" >&2
    echo "  see docs/adapter-contract.md for the required function signatures" >&2
    return 2
  fi
}

ingo_vector_backend_resolve() {
  local backend="${INGO_VECTOR_BACKEND:-upstash}"
  case "$backend" in
    *[!a-zA-Z0-9_-]*)
      echo "invalid INGO_VECTOR_BACKEND value: '$backend'" >&2
      return 2
      ;;
  esac
  printf "%s\n" "$backend"
}

ingo_vector_backend_doctor() {
  local backend slug fn
  backend="$(ingo_vector_backend_resolve)"
  _ingo_vector_load_adapter "$backend"
  slug="$(_ingo_vector_slug "$backend")"
  fn="ingo_vector_${slug}_doctor"
  _ingo_vector_require_fn "$backend" "$fn"
  "$fn"
}

ingo_vector_backend_embed_jsonl() {
  local jsonl="$1"
  local namespace="$2"
  local raw_dir="${3:-}"
  local backend slug fn
  backend="$(ingo_vector_backend_resolve)"
  _ingo_vector_load_adapter "$backend"
  slug="$(_ingo_vector_slug "$backend")"
  fn="ingo_vector_${slug}_embed_jsonl"
  _ingo_vector_require_fn "$backend" "$fn"
  "$fn" "$jsonl" "$namespace" "$raw_dir"
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
    echo "query contract failed: backend '$backend' returned invalid normalized payload" >&2
    echo "  see docs/adapter-contract.md for the expected query response shape" >&2
    return 5
  fi

  printf "%s\n" "$json"
}

ingo_vector_backend_query_text() {
  local question="$1"
  local top_k="$2"
  local namespace="$3"
  local backend slug fn json status

  backend="$(ingo_vector_backend_resolve)"
  _ingo_vector_load_adapter "$backend"
  slug="$(_ingo_vector_slug "$backend")"
  fn="ingo_vector_${slug}_query_text"
  _ingo_vector_require_fn "$backend" "$fn"

  set +e
  json="$("$fn" "$question" "$top_k" "$namespace")"
  status=$?
  set -e

  if [ "$status" -ne 0 ]; then
    return "$status"
  fi

  ingo_vector_require_normalized_query_json "$backend" "$json"
}
