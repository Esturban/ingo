#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/manifest.sh"
source "$ROOT_DIR/lib/fetch.sh"
source "$ROOT_DIR/lib/ocr.sh"
source "$ROOT_DIR/lib/crawl.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

ingo_http_curl() {
  local out=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-o" ]; then
      shift
      out="$1"
    fi
    shift
  done
  [ -n "$out" ] && printf "doc" > "$out"
}

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
    printf "200\tapplication/pdf\t%s" "$url"
  fi
}

main() {
  local tmp manifest urls downloads skipped errors summary
  tmp="$(mktemp -d)"
  ROOT_DIR="$tmp"
  manifest="$tmp/docs.ndjson"
  urls="$tmp/urls.txt"
  downloads="$tmp/downloads"
  skipped="$tmp/skipped.ndjson"
  errors="$tmp/errors.ndjson"
  mkdir -p "$downloads"

  cat > "$urls" <<'URLS'
https://a.gov.co/doc.pdf
URLS

  # First run downloads once.
  summary="$(ingo_crawl_collect_documents "$urls" "$manifest" "$downloads" "" "$skipped" "$errors")"
  echo "$summary" | grep -F "downloaded=1" >/dev/null || fail "first run should download"

  # Second run should skip by manifest URL identity.
  summary="$(ingo_crawl_collect_documents "$urls" "$manifest" "$downloads" "" "$skipped" "$errors")"
  echo "$summary" | grep -F "downloaded=0" >/dev/null || fail "second run should not redownload"
  echo "$summary" | grep -F "skipped=1" >/dev/null || fail "second run should skip seen url"
  jq -e 'select(.reason=="already_seen_url")' "$skipped" >/dev/null || fail "skip ledger should record already_seen_url"
}

main
echo ok
