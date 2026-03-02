#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/fetch.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

assert_ok() { "$@" || fail "expected success: $*"; }
assert_fail() { if "$@"; then fail "expected failure: $*"; fi; }

test_doc_allowlist() {
  INGO_INCLUDE_EXTENSIONS="pdf,docx,xlsx,xlsm"
  INGO_EXCLUDE_EXTENSIONS="zip,png,jpg,jpeg,gif,webp,svg,ico,js,css,map,woff,woff2,ttf,eot,mp3,mp4,mov,avi"

  assert_ok ingo_url_is_document_candidate "https://a.gov.co/file.pdf"
  assert_ok ingo_url_is_document_candidate "https://a.gov.co/file.docx"
  assert_ok ingo_url_is_document_candidate "https://a.gov.co/file.xlsx"
  assert_ok ingo_url_is_document_candidate "https://a.gov.co/file.xlsm"
  assert_fail ingo_url_is_document_candidate "https://a.gov.co/file.html"
}

main() { test_doc_allowlist; echo ok; }
main "$@"
