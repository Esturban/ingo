#!/usr/bin/env bash

set -euo pipefail

ingo_upsert_line() {
  if ! declare -F ingo_vector_upstash_upsert_line_impl >/dev/null 2>&1; then
    # shellcheck source=vector.sh
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vector.sh"
  fi
  ingo_vector_upstash_upsert_line_impl "$@"
}

ingo_embed_jsonl() {
  if ! declare -F ingo_vector_backend_embed_jsonl >/dev/null 2>&1; then
    # shellcheck source=vector.sh
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vector.sh"
  fi
  ingo_vector_backend_embed_jsonl "$@"
}
