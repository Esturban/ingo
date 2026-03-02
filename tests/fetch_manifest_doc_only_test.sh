#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/manifest.sh"
source "$ROOT_DIR/lib/fetch.sh"
source "$ROOT_DIR/lib/ocr.sh"
source "$ROOT_DIR/lib/crawl.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

curl() {
  local out=""
  local write=""
  local url=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -o) shift; out="$1" ;;
      -w) shift; write="$1" ;;
      http://*|https://*) url="$1" ;;
    esac
    shift
  done
  if [ -n "$write" ]; then
    case "$url" in
      *.pdf) printf "200\tapplication/pdf\t%s" "$url" ;;
      *.png) printf "200\timage/png\t%s" "$url" ;;
      *) printf "200\ttext/html\t%s" "$url" ;;
    esac
    return 0
  fi
  printf "doc" > "$out"
}

ingo_http_curl() {
  local out=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-o" ]; then
      shift
      out="$1"
    fi
    shift
  done
  printf "doc" > "$out"
}

test_manifest_doc_only() {
  local tmp urls manifest skipped errors
  tmp="$(mktemp -d)"
  ROOT_DIR="$tmp"
  urls="$tmp/urls.txt"
  manifest="$tmp/docs.ndjson"
  skipped="$tmp/skipped.ndjson"
  errors="$tmp/errors.ndjson"
  mkdir -p "$tmp/downloads"

  INGO_INCLUDE_EXTENSIONS="pdf,docx,xlsx,xlsm"
  INGO_EXCLUDE_EXTENSIONS="zip,png,jpg,jpeg,gif,webp,svg,ico,js,css,map,woff,woff2,ttf,eot,mp3,mp4,mov,avi"

  cat > "$urls" <<'URLS'
https://a.gov.co/doc.pdf
https://a.gov.co/logo.png
https://a.gov.co/home.html
https://a.gov.co/doc bad.pdf
https://a.gov.co/doc%GZ.pdf
URLS

  ingo_crawl_collect_documents "$urls" "$manifest" "$tmp/downloads" "" "$skipped" "$errors" >/dev/null

  [ -s "$manifest" ] || fail "manifest should have accepted docs"
  if jq -e '.file_ext != "pdf"' "$manifest" >/dev/null; then
    fail "manifest should only include pdf in fixture"
  fi
  jq -e 'select(.reason=="malformed_url")' "$skipped" >/dev/null || fail "malformed URLs should be skipped with reason"
  [ "$(jq -r 'select(.reason=="malformed_url") | .url' "$skipped" | wc -l | tr -d ' ')" -ge 2 ] || fail "expected malformed_url entries for space and bad percent encoding"
}

main() { test_manifest_doc_only; echo ok; }
main "$@"
