#!/usr/bin/env bash
# Tests for lib/embedder.sh and INGO_EMBEDDING_MODE=external routing in lib/vector.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local got="$1" want="$2" msg="$3"
  if [ "$got" != "$want" ]; then
    fail "$msg (got='$got' want='$want')"
  fi
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  printf "%s" "$haystack" | grep -F -- "$needle" >/dev/null || fail "$msg (missing '$needle')"
}

# --- ingo_embedder_doctor tests ---

test_doctor_ollama_defaults() {
  local out
  out="$(
    INGO_EMBEDDER_BACKEND=ollama \
    bash -c "
      source '$ROOT_DIR/lib/embedder.sh'
      ingo_embedder_doctor
    "
  )"
  assert_contains "$out" "backend=ollama"                  "ollama doctor reports backend"
  assert_contains "$out" "http://localhost:11434"          "ollama doctor reports default url"
  assert_contains "$out" "nomic-embed-text"                "ollama doctor reports default model"
}

test_doctor_ollama_custom_url() {
  local out
  out="$(
    INGO_EMBEDDER_BACKEND=ollama \
    INGO_EMBEDDER_URL=http://my-ollama:11434 \
    INGO_EMBEDDER_MODEL=mxbai-embed-large \
    bash -c "
      source '$ROOT_DIR/lib/embedder.sh'
      ingo_embedder_doctor
    "
  )"
  assert_contains "$out" "http://my-ollama:11434" "ollama doctor reflects custom url"
  assert_contains "$out" "mxbai-embed-large"      "ollama doctor reflects custom model"
}

test_doctor_openai_missing_token() {
  local out status
  set +e
  out="$(
    INGO_EMBEDDER_BACKEND=openai \
    bash -c "
      source '$ROOT_DIR/lib/embedder.sh'
      ingo_embedder_doctor
    " 2>&1
  )"
  status=$?
  set -e
  assert_eq "$status" "4"                       "openai doctor exits 4 on missing token"
  assert_contains "$out" "INGO_EMBEDDER_TOKEN"  "openai doctor names the missing var"
}

test_doctor_openai_with_token() {
  local out
  out="$(
    INGO_EMBEDDER_BACKEND=openai \
    INGO_EMBEDDER_TOKEN=sk-test \
    bash -c "
      source '$ROOT_DIR/lib/embedder.sh'
      ingo_embedder_doctor
    "
  )"
  assert_contains "$out" "backend=openai"          "openai doctor reports backend"
  assert_contains "$out" "text-embedding-3-small"  "openai doctor reports default model"
}

test_doctor_together_with_token() {
  local out
  out="$(
    INGO_EMBEDDER_BACKEND=together \
    INGO_EMBEDDER_TOKEN=test-token \
    bash -c "
      source '$ROOT_DIR/lib/embedder.sh'
      ingo_embedder_doctor
    "
  )"
  assert_contains "$out" "backend=together"                         "together doctor reports backend"
  assert_contains "$out" "intfloat/multilingual-e5-large-instruct" "together doctor reports default model"
}

test_doctor_voyage_with_token() {
  local out
  out="$(
    INGO_EMBEDDER_BACKEND=voyage \
    INGO_EMBEDDER_TOKEN=voyage-test \
    bash -c "
      source '$ROOT_DIR/lib/embedder.sh'
      ingo_embedder_doctor
    "
  )"
  assert_contains "$out" "backend=voyage"        "voyage doctor reports backend"
  assert_contains "$out" "voyage-multilingual-2" "voyage doctor reports default model"
}

test_doctor_cohere_with_token() {
  local out
  out="$(
    INGO_EMBEDDER_BACKEND=cohere \
    INGO_EMBEDDER_TOKEN=co-test \
    bash -c "
      source '$ROOT_DIR/lib/embedder.sh'
      ingo_embedder_doctor
    "
  )"
  assert_contains "$out" "backend=cohere" "cohere doctor reports backend"
  assert_contains "$out" "embed-v4.0"     "cohere doctor reports default model"
}

test_doctor_unknown_backend() {
  local out status
  set +e
  out="$(
    INGO_EMBEDDER_BACKEND=bogus \
    bash -c "
      source '$ROOT_DIR/lib/embedder.sh'
      ingo_embedder_doctor
    " 2>&1
  )"
  status=$?
  set -e
  assert_eq "$status" "2"             "unknown backend exits 2"
  assert_contains "$out" "bogus"      "error names the unknown backend"
  assert_contains "$out" "supported:" "error lists supported backends"
}

# --- INGO_EMBEDDING_MODE=external routing tests ---

test_external_mode_requires_upsert_vector_jsonl() {
  local tmp_dir tmp_jsonl out status
  tmp_dir="$(mktemp -d)"
  tmp_jsonl="$tmp_dir/test.jsonl"
  printf '{"id":"c1","text":"hello","source":"a.pdf","section":"I","article":"1"}\n' > "$tmp_jsonl"

  set +e
  out="$(
    INGO_EMBEDDING_MODE=external \
    INGO_VECTOR_BACKEND=mymock \
    bash -c "
      ingo_embedder_text() { printf '[0.1,0.2,0.3]\n'; }
      ingo_vector_mymock_doctor()      { printf 'vector: backend=mymock\n'; }
      ingo_vector_mymock_embed_jsonl() { printf '0\n'; }
      source '$ROOT_DIR/lib/vector.sh'
      ingo_vector_backend_embed_jsonl '$tmp_jsonl' 'test-ns'
    " 2>&1
  )"
  status=$?
  set -e

  assert_eq "$status" "2"                      "missing upsert_vector_jsonl exits 2"
  assert_contains "$out" "upsert_vector_jsonl" "error names the missing function"
  rm -rf "$tmp_dir"
}

test_external_mode_embed_dispatches_with_vector_field() {
  local tmp_dir tmp_jsonl out
  tmp_dir="$(mktemp -d)"
  tmp_jsonl="$tmp_dir/test.jsonl"
  printf '{"id":"c1","text":"El agua","source":"a.pdf","section":"I","article":"1"}\n' > "$tmp_jsonl"

  out="$(
    INGO_EMBEDDING_MODE=external \
    INGO_VECTOR_BACKEND=mymock \
    bash -c "
      ingo_embedder_text() { printf '[0.1,0.2,0.3]\n'; }
      ingo_vector_mymock_doctor() { printf 'vector: backend=mymock\n'; }
      ingo_vector_mymock_embed_jsonl() { printf '0\n'; }
      ingo_vector_mymock_upsert_vector_jsonl() {
        local jsonl=\$1
        local line
        while IFS= read -r line; do
          [ -n \"\$line\" ] || continue
          printf '%s' \"\$line\" | grep -q '\"vector\"' || { echo 'MISSING VECTOR' >&2; exit 1; }
          printf '%s' \"\$line\" | grep -q '0.1' || { echo 'WRONG VECTOR' >&2; exit 1; }
        done < \"\$jsonl\"
        printf '1\n'
      }
      source '$ROOT_DIR/lib/vector.sh'
      ingo_vector_backend_embed_jsonl '$tmp_jsonl' 'test-ns'
    "
  )"

  assert_eq "$out" "1" "external embed returns count of vectorized chunks"
  rm -rf "$tmp_dir"
}

test_external_mode_query_requires_query_vector() {
  local out status
  set +e
  out="$(
    INGO_EMBEDDING_MODE=external \
    INGO_VECTOR_BACKEND=mymock \
    bash -c "
      ingo_embedder_text() { printf '[0.1,0.2,0.3]\n'; }
      ingo_vector_mymock_doctor()      { printf 'vector: backend=mymock\n'; }
      ingo_vector_mymock_embed_jsonl() { printf '0\n'; }
      source '$ROOT_DIR/lib/vector.sh'
      ingo_vector_backend_query_text 'pregunta' 5 'ns'
    " 2>&1
  )"
  status=$?
  set -e

  assert_eq "$status" "2"                   "missing query_vector exits 2"
  assert_contains "$out" "query_vector"     "error names the missing function"
}

test_external_mode_query_dispatches_vector() {
  local out
  out="$(
    INGO_EMBEDDING_MODE=external \
    INGO_VECTOR_BACKEND=mymock \
    bash -c "
      ingo_embedder_text() { printf '[0.9,0.8,0.7]\n'; }
      ingo_vector_mymock_doctor()      { printf 'vector: backend=mymock\n'; }
      ingo_vector_mymock_embed_jsonl() { printf '0\n'; }
      ingo_vector_mymock_query_vector() {
        printf '{\"match_count\":1,\"matches\":[{\"id\":\"c1\",\"score\":0.99,\"text\":\"El agua\",\"source\":\"a.pdf\",\"section\":\"I\",\"article\":\"1\"}]}\n'
      }
      source '$ROOT_DIR/lib/vector.sh'
      ingo_vector_backend_query_text 'pregunta' 5 'ns'
    "
  )"

  assert_contains "$out" '"match_count":1' "external query returns normalized JSON"
  assert_contains "$out" '"score":0.99'    "external query includes match score"
}

main() {
  test_doctor_ollama_defaults
  test_doctor_ollama_custom_url
  test_doctor_openai_missing_token
  test_doctor_openai_with_token
  test_doctor_together_with_token
  test_doctor_voyage_with_token
  test_doctor_cohere_with_token
  test_doctor_unknown_backend
  test_external_mode_requires_upsert_vector_jsonl
  test_external_mode_embed_dispatches_with_vector_field
  test_external_mode_query_requires_query_vector
  test_external_mode_query_dispatches_vector
  echo "ok"
}

main "$@"
