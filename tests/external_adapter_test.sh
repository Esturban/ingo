#!/usr/bin/env bash
# Tests for external adapter loading (INGO_VECTOR_ADAPTER) and the generic adapter.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_contains() {
  local haystack="$1" needle="$2" msg="$3"
  printf "%s" "$haystack" | grep -F -- "$needle" >/dev/null || fail "$msg (missing '$needle')"
}

# --- External adapter loading ---

test_external_adapter_loaded_via_env() {
  local adapter_dir
  adapter_dir="$(mktemp -d)"

  cat > "$adapter_dir/myadapter.sh" <<'ADAPTER'
#!/usr/bin/env bash
ingo_vector_myadapter_doctor()      { printf "vector: backend=myadapter url=http://localhost:8000\n"; }
ingo_vector_myadapter_embed_jsonl() { printf "0\n"; }
ingo_vector_myadapter_query_text()  { printf '{"match_count":0,"matches":[]}\n'; }
ADAPTER

  local out
  out="$(
    INGO_VECTOR_BACKEND=myadapter \
    INGO_VECTOR_ADAPTER="$adapter_dir/myadapter.sh" \
    bash -c "
      source '$ROOT_DIR/lib/vector.sh'
      ingo_vector_backend_doctor
    "
  )"

  assert_contains "$out" "backend=myadapter" "external adapter doctor output"
  rm -rf "$adapter_dir"
}

test_external_adapter_missing_file_errors() {
  local out
  out="$(
    INGO_VECTOR_BACKEND=ghost \
    INGO_VECTOR_ADAPTER="/nonexistent/ghost.sh" \
    bash -c "
      source '$ROOT_DIR/lib/vector.sh'
      ingo_vector_backend_doctor
    " 2>&1
  )" || true

  assert_contains "$out" "not found" "missing adapter file error"
}

test_unknown_builtin_lists_available() {
  local out
  out="$(
    INGO_VECTOR_BACKEND=bogusbackend \
    bash -c "
      source '$ROOT_DIR/lib/vector.sh'
      ingo_vector_backend_doctor
    " 2>&1
  )" || true

  assert_contains "$out" "bogusbackend"       "error names the unknown backend"
  assert_contains "$out" "built-ins:"         "error lists built-in options"
  assert_contains "$out" "INGO_VECTOR_ADAPTER" "error hints at external adapter path"
}

test_backend_name_with_hyphen_resolves() {
  local adapter_dir
  adapter_dir="$(mktemp -d)"

  cat > "$adapter_dir/my-backend.sh" <<'ADAPTER'
#!/usr/bin/env bash
ingo_vector_my_backend_doctor()      { printf "vector: backend=my-backend\n"; }
ingo_vector_my_backend_embed_jsonl() { printf "0\n"; }
ingo_vector_my_backend_query_text()  { printf '{"match_count":0,"matches":[]}\n'; }
ADAPTER

  local out
  out="$(
    INGO_VECTOR_BACKEND=my-backend \
    INGO_VECTOR_ADAPTER="$adapter_dir/my-backend.sh" \
    bash -c "
      source '$ROOT_DIR/lib/vector.sh'
      ingo_vector_backend_doctor
    "
  )"

  assert_contains "$out" "backend=my-backend" "hyphenated backend name resolves via slug"
  rm -rf "$adapter_dir"
}

# --- Generic adapter ---

test_generic_adapter_doctor() {
  local out
  out="$(
    INGO_VECTOR_URL="https://api.example.com" \
    INGO_VECTOR_TOKEN="tok" \
    bash -c "
      source '$ROOT_DIR/lib/http.sh'
      source '$ROOT_DIR/lib/vector/generic.sh'
      ingo_vector_generic_doctor
    "
  )"
  assert_contains "$out" "backend=generic"          "generic doctor reports backend"
  assert_contains "$out" "https://api.example.com"  "generic doctor reports url"
}

test_generic_adapter_doctor_missing_env() {
  local out
  out="$(
    bash -c "
      source '$ROOT_DIR/lib/vector/generic.sh'
      ingo_vector_generic_doctor
    " 2>&1
  )" || true
  assert_contains "$out" "INGO_VECTOR_URL" "generic doctor reports missing url var"
}

main() {
  test_external_adapter_loaded_via_env
  test_external_adapter_missing_file_errors
  test_unknown_builtin_lists_available
  test_backend_name_with_hyphen_resolves
  test_generic_adapter_doctor
  test_generic_adapter_doctor_missing_env
  echo "ok"
}

main "$@"
