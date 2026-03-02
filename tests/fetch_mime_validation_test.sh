#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/crawl.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

main() {
  ingo_crawl_mime_is_document "application/pdf" || fail "pdf mime should pass"
  ingo_crawl_mime_is_document "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" || fail "xlsx mime should pass"
  if ingo_crawl_mime_is_document "text/html; charset=utf-8"; then
    fail "html mime should fail"
  fi
  echo ok
}

main "$@"
