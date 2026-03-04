#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/manifest.sh"
source "$ROOT_DIR/lib/fetch.sh"
source "$ROOT_DIR/lib/ocr.sh"
source "$ROOT_DIR/lib/crawl.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

PROBE_COUNTER_FILE=""

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
    if [ -n "$PROBE_COUNTER_FILE" ]; then
      printf "1\n" >> "$PROBE_COUNTER_FILE"
    fi
    case "$url" in
      *"/noext")
        printf "200\tapplication/pdf\t%s" "$url"
        ;;
      *)
        printf "200\ttext/html\t%s" "$url"
        ;;
    esac
  fi
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

main() {
  local tmp urls manifest skipped errors summary
  tmp="$(mktemp -d)"
  ROOT_DIR="$tmp"
  urls="$tmp/urls.txt"
  manifest="$tmp/docs.ndjson"
  skipped="$tmp/skipped.ndjson"
  errors="$tmp/errors.ndjson"
  PROBE_COUNTER_FILE="$tmp/probe-count.log"
  mkdir -p "$tmp/downloads"
  : > "$PROBE_COUNTER_FILE"

  cat > "$urls" <<'URLS'
https://a.gov.co/known.pdf
https://a.gov.co/noext
URLS

  INGO_SKIP_PROBE_FOR_ALLOWED_EXTENSIONS="1"
  summary="$(ingo_crawl_collect_documents "$urls" "$manifest" "$tmp/downloads" "" "$skipped" "$errors")"
  echo "$summary" | grep -F "downloaded=1" >/dev/null || fail "known extension should fast-path download"
  echo "$summary" | grep -F "duplicate=1" >/dev/null || fail "fixture should produce one duplicate by content hash"
  [ "$(wc -l < "$PROBE_COUNTER_FILE" | tr -d ' ')" -eq 1 ] || fail "only non-extension URL should be probed"
}

main
echo ok
