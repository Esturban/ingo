#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/manifest.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/manifest.sh"
# shellcheck source=../lib/crawl.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/crawl.sh"
# shellcheck source=../lib/fetch.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/fetch.sh"
# shellcheck source=../lib/ocr.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/ocr.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local got="$1"
  local want="$2"
  local msg="$3"
  if [ "$got" != "$want" ]; then
    fail "$msg (got='$got' want='$want')"
  fi
}

ingo_http_curl() {
  local out=""
  local url=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      -o)
        shift
        out="$1"
        ;;
      http://*|https://*)
        url="$1"
        ;;
    esac
    shift
  done
  case "$url" in
    *a.pdf|*b.pdf) printf "same-content" > "$out" ;;
    *) printf "x" > "$out" ;;
  esac
}

test_dedupe_by_hash() {
  local tmp manifest urls downloads summary downloaded duplicates
  local canonical_id duplicate_id
  tmp="$(mktemp -d)"
  ROOT_DIR="$tmp"
  manifest="$tmp/documents.ndjson"
  urls="$tmp/urls.txt"
  downloads="$tmp/downloads"
  printf "https://seed.gov.co/a.pdf\nhttps://seed.gov.co/b.pdf\n" > "$urls"

  summary="$(ingo_crawl_collect_documents "$urls" "$manifest" "$downloads")"
  downloaded="$(printf "%s\n" "$summary" | sed -n 's/.*downloaded=\([0-9]*\).*/\1/p')"
  duplicates="$(printf "%s\n" "$summary" | sed -n 's/.*duplicate=\([0-9]*\).*/\1/p')"

  assert_eq "$downloaded" "1" "first hash should be canonical download"
  assert_eq "$duplicates" "1" "second same hash should be duplicate"
  assert_eq "$(jq -r 'select(.status=="duplicate") | .duplicate_of' "$manifest" | wc -l | tr -d ' ')" "1" "duplicate record points to canonical"
  canonical_id="$(jq -r 'select(.status=="downloaded") | .doc_id' "$manifest" | head -n 1)"
  duplicate_id="$(jq -r 'select(.status=="duplicate") | .doc_id' "$manifest" | head -n 1)"
  [ -n "$canonical_id" ] || fail "canonical doc id should exist"
  [ -n "$duplicate_id" ] || fail "duplicate doc id should exist"
  if [ "$canonical_id" = "$duplicate_id" ]; then
    fail "duplicate rows must use unique doc_id to avoid cross-row status updates"
  fi
}

main() {
  test_dedupe_by_hash
  echo "ok"
}

main "$@"
