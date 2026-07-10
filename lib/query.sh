#!/usr/bin/env bash

set -euo pipefail

ingo_query_text() {
  if ! declare -F ingo_vector_backend_query_text >/dev/null 2>&1; then
    # shellcheck source=vector.sh
    # shellcheck disable=SC1091
    source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/vector.sh"
  fi
  ingo_vector_backend_query_text "$@"
}
