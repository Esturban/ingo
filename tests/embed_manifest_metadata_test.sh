#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/embed.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/embed.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if ! printf "%s" "$haystack" | grep -F -- "$needle" >/dev/null; then
    fail "$msg (missing '$needle')"
  fi
}

CAPTURED_PAYLOAD_FILE=""
ingo_http_curl() {
  local data=""
  while [ "$#" -gt 0 ]; do
    if [ "$1" = "-d" ]; then
      shift
      data="$1"
    fi
    shift
  done
  printf "%s" "$data" > "$CAPTURED_PAYLOAD_FILE"
  printf '{"ok":true}\n200\n'
}

test_embed_metadata_fields() {
  local tmp meta line payload
  tmp="$(mktemp -d)"
  meta="$tmp/sample.meta"
  CAPTURED_PAYLOAD_FILE="$tmp/payload.json"
  line='{"id":"id-1","text":"hola","source":"s","section":"sec","article":"art","start":1,"end":2}'

  cat > "$meta" <<'META'
doc_id=sha256:abc
source_url=https://seed.gov.co/doc.pdf
canonical_url=https://seed.gov.co/doc.pdf
content_sha256=abc
issuer=ANLA
category=normativa
sector=energia
norm_type=decreto
norm_number=1076
norm_year=2015
tags=anla,energia
META

  UPSTASH_VECTOR_REST_URL="https://vector.example.test"
  UPSTASH_VECTOR_REST_TOKEN="token"
  ingo_upsert_line "$line" "ns" "$meta"
  payload="$(cat "$CAPTURED_PAYLOAD_FILE")"

  assert_contains "$payload" '"doc_id": "sha256:abc"' "payload should include doc_id"
  assert_contains "$payload" '"norm_year": 2015' "payload should include numeric norm_year"
  assert_contains "$payload" '"tags": [' "payload should include parsed tags"
}

main() {
  test_embed_metadata_fields
  echo "ok"
}

main "$@"
