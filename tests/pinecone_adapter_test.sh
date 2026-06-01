#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/env.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/env.sh"
# shellcheck source=../lib/http.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/http.sh"
# shellcheck source=../lib/vector.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/vector.sh"
# shellcheck source=../lib/embed.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/embed.sh"
# shellcheck source=../lib/query.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/query.sh"

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

assert_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if ! printf "%s" "$haystack" | grep -F -- "$needle" >/dev/null; then
    fail "$msg (missing '$needle')"
  fi
}

CAPTURED_URL=""
CAPTURED_DATA=""
CAPTURED_HEADERS=""
CAPTURED_FILE="$(mktemp)"

ingo_http_curl() {
  local arg
  CAPTURED_URL=""
  CAPTURED_DATA=""
  CAPTURED_HEADERS=""
  : > "$CAPTURED_FILE"

  while [ "$#" -gt 0 ]; do
    arg="$1"
    case "$arg" in
      -d)
        shift
        CAPTURED_DATA="$1"
        printf 'DATA=%s\n' "$1" >> "$CAPTURED_FILE"
        ;;
      -H)
        shift
        CAPTURED_HEADERS="${CAPTURED_HEADERS}${1}"$'\n'
        printf 'HEADER=%s\n' "$1" >> "$CAPTURED_FILE"
        ;;
      http://*|https://*)
        CAPTURED_URL="$arg"
        printf 'URL=%s\n' "$arg" >> "$CAPTURED_FILE"
        ;;
    esac
    shift
  done

  if printf "%s" "$CAPTURED_URL" | grep -F "/search" >/dev/null; then
    printf '{"result":{"hits":[{"_id":"rec-1","_score":0.91,"fields":{"chunk_text":"ok","source":"src","section":"sec","article":"art","date_indexed":"today"}}]}}\n200\n'
    return 0
  fi

  printf '{"upsertedCount":1}\n201\n'
}

test_pinecone_query_normalizes_contract() {
  export INGO_VECTOR_BACKEND="pinecone"
  export INGO_VECTOR_URL="https://example-index.pinecone.io"
  export INGO_VECTOR_TOKEN="secret"
  export INGO_PINECONE_TEXT_FIELD="chunk_text"
  export INGO_PINECONE_API_VERSION="2025-10"

  local json_file json
  json_file="$(mktemp)"
  ingo_query_text "hola" 3 "legal-co" > "$json_file"
  json="$(cat "$json_file")"

  assert_contains "$(cat "$CAPTURED_FILE")" "URL=https://example-index.pinecone.io/records/namespaces/legal-co/search" "pinecone query uses records search endpoint"
  assert_contains "$(cat "$CAPTURED_FILE")" "HEADER=Api-Key: secret" "pinecone query forwards API key"
  assert_contains "$(cat "$CAPTURED_FILE")" '"text": "hola"' "pinecone query sends text search payload"
  assert_eq "$(printf "%s" "$json" | jq -r '.match_count')" "1" "pinecone query normalizes match_count"
  assert_eq "$(printf "%s" "$json" | jq -r '.matches[0].text')" "ok" "pinecone query normalizes chunk text field"
}

test_pinecone_embed_uses_ndjson_records() {
  local tmp raw chunk count captured
  tmp="$(mktemp -d)"
  raw="$tmp/raw"
  chunk="$tmp/sample.jsonl"
  mkdir -p "$raw"

  cat > "$chunk" <<'EOF'
{"id":"id-1","text":"hola","source":"src","section":"s","article":"a","start":1,"end":2}
EOF
  cat > "$raw/sample.meta" <<'EOF'
doc_id=sha256:abc
source_url=https://example.test/doc.pdf
EOF

  export INGO_VECTOR_BACKEND="pinecone"
  export INGO_VECTOR_URL="https://example-index.pinecone.io"
  export INGO_VECTOR_TOKEN="secret"
  export INGO_PINECONE_TEXT_FIELD="chunk_text"
  export INGO_PINECONE_API_VERSION="2025-10"

  count="$(ingo_embed_jsonl "$chunk" "legal-co" "$raw")"
  captured="$(cat "$CAPTURED_FILE")"

  assert_eq "$count" "1" "pinecone embed returns numeric count"
  assert_contains "$captured" "URL=https://example-index.pinecone.io/records/namespaces/legal-co/upsert" "pinecone embed uses namespace upsert endpoint"
  assert_contains "$captured" "HEADER=Content-Type: application/x-ndjson" "pinecone embed uses ndjson content type"
  assert_contains "$captured" '"chunk_text": "hola"' "pinecone embed uses configured text field"
  assert_contains "$captured" '"source": "src"' "pinecone embed includes metadata fields"
}

main() {
  test_pinecone_query_normalizes_contract
  test_pinecone_embed_uses_ndjson_records
  echo "ok"
}

main "$@"
