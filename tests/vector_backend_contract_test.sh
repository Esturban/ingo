#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

reset_runtime_env() {
  local name
  while IFS= read -r name; do
    unset "$name"
  done < <(compgen -A variable INGO_)
  unset UPSTASH_VECTOR_REST_URL UPSTASH_VECTOR_REST_TOKEN
}

make_mock_bin() {
  local dir="$1"
  mkdir -p "$dir"

  cat > "$dir/curl" <<'EOF'
#!/usr/bin/env bash
printf '{"result":[]}\n200\n'
EOF
  cat > "$dir/jq" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "-n" ]; then
  printf '{}\n'
else
  cat >/dev/null
  printf '{"match_count":0,"matches":[]}\n'
fi
EOF
  cat > "$dir/awk" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$dir/grep" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$dir/pdftotext" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$dir/pdftoppm" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$dir/tesseract" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--list-langs" ]; then
  cat <<'OUT'
List of available languages in "/tmp/tessdata/" (2):
eng
spa
OUT
fi
EOF

  chmod +x "$dir/curl" "$dir/jq" "$dir/awk" "$dir/grep" "$dir/pdftotext" "$dir/pdftoppm" "$dir/tesseract"
}

test_default_backend_is_upstash() {
  # shellcheck source=../lib/env.sh
  # shellcheck disable=SC1091
  source "$ROOT_DIR/lib/env.sh"
  # shellcheck source=../lib/vector.sh
  # shellcheck disable=SC1091
  source "$ROOT_DIR/lib/vector.sh"

  reset_runtime_env
  unset INGO_VECTOR_MODEL
  ingo_load_env
  assert_eq "$(ingo_vector_backend_resolve)" "upstash" "default backend resolves to upstash"
}

test_generic_vector_env_precedence() {
  # shellcheck source=../lib/env.sh
  # shellcheck disable=SC1091
  source "$ROOT_DIR/lib/env.sh"

  reset_runtime_env
  unset INGO_VECTOR_MODEL
  INGO_VECTOR_URL="https://vector.generic.test"
  INGO_VECTOR_TOKEN="generic-token"
  UPSTASH_VECTOR_REST_URL="https://vector.legacy.test"
  UPSTASH_VECTOR_REST_TOKEN="legacy-token"

  ingo_load_env

  assert_eq "$INGO_VECTOR_URL" "https://vector.generic.test" "generic URL wins"
  assert_eq "$INGO_VECTOR_TOKEN" "generic-token" "generic token wins"
  assert_eq "$UPSTASH_VECTOR_REST_URL" "https://vector.legacy.test" "pre-existing legacy URL is preserved"
  assert_eq "$UPSTASH_VECTOR_REST_TOKEN" "legacy-token" "pre-existing legacy token is preserved"
}

test_unknown_backend_fails_fast() {
  local mock_bin out status
  mock_bin="$(mktemp -d)"
  make_mock_bin "$mock_bin"

  set +e
  out="$(
    PATH="$mock_bin:$PATH" \
    INGO_VECTOR_BACKEND="bogus" \
    INGO_VECTOR_URL="https://vector.example.test" \
    INGO_VECTOR_TOKEN="token" \
    INGO_VECTOR_MODEL="" \
    "$ROOT_DIR/bin/ingo" query "hola" 2>&1
  )"
  status=$?
  set -e

  assert_eq "$status" "2" "unknown backend exits with config error"
  assert_contains "$out" "unknown vector backend: bogus" "unknown backend message is actionable"
}

test_qdrant_missing_model_uses_capability_error() {
  local mock_bin out status
  mock_bin="$(mktemp -d)"
  make_mock_bin "$mock_bin"

  set +e
  out="$(
    PATH="$mock_bin:$PATH" \
    INGO_VECTOR_BACKEND="qdrant" \
    INGO_VECTOR_URL="http://localhost:6333" \
    INGO_VECTOR_MODEL="" \
    "$ROOT_DIR/bin/ingo" query "hola" 2>&1
  )"
  status=$?
  set -e

  assert_eq "$status" "7" "missing qdrant inference model exits with capability error"
  assert_contains "$out" "requires INGO_VECTOR_MODEL" "qdrant error explains missing model"
}

test_doctor_reports_active_backend() {
  local mock_bin out
  mock_bin="$(mktemp -d)"
  make_mock_bin "$mock_bin"

  out="$(
    PATH="$mock_bin:$PATH" \
    INGO_VECTOR_BACKEND="qdrant" \
    INGO_VECTOR_URL="http://localhost:6333" \
    INGO_VECTOR_MODEL="test-model" \
    INGO_ROLE="all" \
    "$ROOT_DIR/bin/ingo" doctor 2>&1
  )"

  assert_contains "$out" "vector: backend=qdrant" "doctor prints backend-aware status"
  assert_contains "$out" "inference_model=test-model" "doctor prints qdrant model guidance"
}

main() {
  test_default_backend_is_upstash
  test_generic_vector_env_precedence
  test_unknown_backend_fails_fast
  test_qdrant_missing_model_uses_capability_error
  test_doctor_reports_active_backend
  echo "ok"
}

main "$@"
