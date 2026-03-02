#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/fetch.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

main() {
  INGO_EXCLUDE_EXTENSIONS="zip,png,jpg,jpeg,gif,webp,svg,ico,js,css,map,woff,woff2,ttf,eot,mp3,mp4,mov,avi"
  ingo_is_excluded_extension png || fail "png should be excluded"
  ingo_is_excluded_extension js || fail "js should be excluded"
  ingo_is_excluded_extension css || fail "css should be excluded"
  echo ok
}

main "$@"
