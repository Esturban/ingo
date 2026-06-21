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
CAPTURED_HEADERS=""
CAPTURED_FILE="$(mktemp)"

ingo_http_curl() {
  local arg
  CAPTURED_URL=""
  CAPTURED_HEADERS=""
  : > "$CAPTURED_FILE"

  while [ "$#" -gt 0 ]; do
    arg="$1"
    case "$arg" in
      -d)
        shift
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

  if printf "%s" "$CAPTURED_URL" | grep -F "/points/query" >/dev/null; then
    printf '{"result":{"points":[{"id":42,"score":0.75,"payload":{"text":"ok","source":"src","section":"sec","article":"art","date_indexed":"today"}}]}}\n200\n'
    return 0
  fi

  printf '{"status":"ok"}\n200\n'
}

test_qdrant_query_normalizes_contract() {
  export INGO_VECTOR_BACKEND="qdrant"
  export INGO_VECTOR_URL="http://localhost:6333"
  export INGO_VECTOR_TOKEN="secret"
  export INGO_VECTOR_MODEL="test-model"

  local json_file json
  json_file="$(mktemp)"
  ingo_query_text "hola" 3 "legal-co" > "$json_file"
  json="$(cat "$json_file")"

  assert_contains "$(cat "$CAPTURED_FILE")" "URL=http://localhost:6333/collections/legal-co/points/query" "qdrant query uses collection query endpoint"
  assert_contains "$(cat "$CAPTURED_FILE")" "HEADER=api-key: secret" "qdrant query forwards api-key header when token is set"
  assert_eq "$(printf "%s" "$json" | jq -r '.match_count')" "1" "qdrant query normalizes match_count"
  assert_eq "$(printf "%s" "$json" | jq -r '.matches[0].text')" "ok" "qdrant query normalizes payload text"
}

test_qdrant_embed_uses_inference_payload() {
  local tmp raw chunk count
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

  export INGO_VECTOR_BACKEND="qdrant"
  export INGO_VECTOR_URL="http://localhost:6333"
  export INGO_VECTOR_MODEL="test-model"
  unset INGO_VECTOR_TOKEN

  count="$(ingo_embed_jsonl "$chunk" "legal-co" "$raw")"

  assert_eq "$count" "1" "qdrant embed returns numeric count"
  assert_contains "$(cat "$CAPTURED_FILE")" "URL=http://localhost:6333/collections/legal-co/points?wait=true" "qdrant embed uses collection upsert endpoint"
  assert_contains "$(cat "$CAPTURED_FILE")" '"model": "test-model"' "qdrant embed sends inference model"
  assert_contains "$(cat "$CAPTURED_FILE")" '"payload": {' "qdrant embed stores payload object"
  assert_contains "$(cat "$CAPTURED_FILE")" '"source": "src"' "qdrant embed stores normalized payload fields"
}

test_qdrant_external_embed_passes_vector() {
  local tmp chunk count
  tmp="$(mktemp -d)"
  chunk="$tmp/sample.jsonl"

  cat > "$chunk" <<'EOF'
{"id":"id-1","text":"hola","source":"src","section":"s","article":"a","start":1,"end":2}
EOF

  export INGO_VECTOR_BACKEND="qdrant"
  export INGO_VECTOR_URL="http://localhost:6333"
  export INGO_EMBEDDING_MODE="external"
  unset INGO_VECTOR_TOKEN
  unset INGO_VECTOR_MODEL

  # Stub embedder — return a known float vector without hitting a real server.
  ingo_embedder_text() { printf '[0.1,0.2,0.3]'; }

  count="$(ingo_embed_jsonl "$chunk" "legal-co" "")"

  assert_eq "$count" "1" "qdrant external embed returns numeric count"
  assert_contains "$(cat "$CAPTURED_FILE")" \
    "URL=http://localhost:6333/collections/legal-co/points?wait=true" \
    "qdrant external embed calls upsert endpoint"
  assert_contains "$(cat "$CAPTURED_FILE")" '"vector":' \
    "qdrant external embed includes vector field in payload"
  assert_contains "$(cat "$CAPTURED_FILE")" '0.1' \
    "qdrant external embed sends the stubbed vector values"

  unset INGO_EMBEDDING_MODE
  unset -f ingo_embedder_text
  rm -rf "$tmp"
}

test_qdrant_external_query_passes_vector() {
  export INGO_VECTOR_BACKEND="qdrant"
  export INGO_VECTOR_URL="http://localhost:6333"
  export INGO_VECTOR_TOKEN="secret"
  export INGO_EMBEDDING_MODE="external"
  unset INGO_VECTOR_MODEL

  # Stub embedder — return a known float vector without hitting a real server.
  ingo_embedder_text() { printf '[0.1,0.2,0.3]'; }

  local json
  json="$(ingo_query_text "hola" 3 "legal-co")"

  assert_contains "$(cat "$CAPTURED_FILE")" \
    "URL=http://localhost:6333/collections/legal-co/points/query" \
    "qdrant external query calls query endpoint"
  assert_contains "$(cat "$CAPTURED_FILE")" '"query":' \
    "qdrant external query sends vector as query field"
  assert_contains "$(cat "$CAPTURED_FILE")" '0.1' \
    "qdrant external query sends the stubbed vector values"
  assert_eq "$(printf "%s" "$json" | jq -r '.match_count')" "1" \
    "qdrant external query normalizes match_count"

  unset INGO_EMBEDDING_MODE
  unset -f ingo_embedder_text
}

main() {
  test_qdrant_query_normalizes_contract
  test_qdrant_embed_uses_inference_payload
  test_qdrant_external_embed_passes_vector
  test_qdrant_external_query_passes_vector
  echo "ok"
}

main "$@"
