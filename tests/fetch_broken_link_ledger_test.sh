#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/manifest.sh"
source "$ROOT_DIR/lib/fetch.sh"
source "$ROOT_DIR/lib/ocr.sh"
source "$ROOT_DIR/lib/crawl.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

curl() {
  local write=""
  local url=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -w) shift; write="$1" ;;
      http://*|https://*) url="$1" ;;
    esac
    shift
  done
  if [ -n "$write" ]; then
    printf "404\ttext/html\t%s" "$url"
    return 0
  fi
  return 22
}

ingo_http_curl() {
  return 22
}

test_broken_link_ledger() {
  local tmp urls manifest skipped errors summary
  tmp="$(mktemp -d)"
  ROOT_DIR="$tmp"
  urls="$tmp/urls.txt"
  manifest="$tmp/docs.ndjson"
  skipped="$tmp/skipped.ndjson"
  errors="$tmp/errors.ndjson"
  mkdir -p "$tmp/downloads"
  printf "https://a.gov.co/bad.pdf\n" > "$urls"

  summary="$(ingo_crawl_collect_documents "$urls" "$manifest" "$tmp/downloads" "" "$skipped" "$errors")"
  echo "$summary" | grep -F "failed=1" >/dev/null || fail "should count failed link"
  [ -s "$errors" ] || fail "errors ledger should be written"
}

main() { test_broken_link_ledger; echo ok; }
main "$@"
