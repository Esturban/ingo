#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/fetch.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

main() {
  INGO_INCLUDE_EXTENSIONS="pdf,docx,xlsx,xlsm"
  INGO_EXCLUDE_EXTENSIONS="zip,png,jpg,jpeg,gif,webp,svg,ico,js,css,map,woff,woff2,ttf,eot,mp3,mp4,mov,avi"
  if ingo_url_is_document_candidate "https://www.anla.gov.co/a.zip"; then
    fail "zip should be excluded"
  fi
  echo ok
}

main "$@"
