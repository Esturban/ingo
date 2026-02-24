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

make_mock_bin() {
  local dir="$1"

  cat > "$dir/curl" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
  cat > "$dir/jq" <<'EOF'
#!/usr/bin/env bash
exit 0
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

  chmod +x "$dir/curl" "$dir/jq" "$dir/awk" "$dir/grep" "$dir/pdftotext" "$dir/pdftoppm"
}

test_doctor_fails_when_lang_missing() {
  local mock_bin out status
  mock_bin="$(mktemp -d)"
  make_mock_bin "$mock_bin"

  cat > "$mock_bin/tesseract" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--list-langs" ]; then
  cat <<'OUT'
List of available languages in "/tmp/tessdata/" (2):
eng
spa_old
OUT
  exit 0
fi
exit 0
EOF
  chmod +x "$mock_bin/tesseract"

  set +e
  out="$(
    PATH="$mock_bin:$PATH" \
    UPSTASH_VECTOR_REST_URL="https://example.test" \
    UPSTASH_VECTOR_REST_TOKEN="token" \
    INGO_ROLE="all" \
    INGO_LANG="spa" \
    "$ROOT_DIR/bin/ingo" doctor 2>&1
  )"
  status=$?
  set -e

  assert_eq "$status" "5" "doctor exits non-zero when OCR language is missing"
  assert_contains "$out" "missing OCR language data for INGO_LANG=spa" "doctor error mentions missing INGO_LANG"
}

test_doctor_passes_when_lang_present_exact_match() {
  local mock_bin out
  mock_bin="$(mktemp -d)"
  make_mock_bin "$mock_bin"

  cat > "$mock_bin/tesseract" <<'EOF'
#!/usr/bin/env bash
if [ "${1:-}" = "--list-langs" ]; then
  cat <<'OUT'
List of available languages in "/tmp/tessdata/" (3):
eng
spa
spa_old
OUT
  exit 0
fi
exit 0
EOF
  chmod +x "$mock_bin/tesseract"

  out="$(
    PATH="$mock_bin:$PATH" \
    UPSTASH_VECTOR_REST_URL="https://example.test" \
    UPSTASH_VECTOR_REST_TOKEN="token" \
    INGO_ROLE="all" \
    INGO_LANG="spa" \
    "$ROOT_DIR/bin/ingo" doctor 2>&1
  )"
  assert_eq "$out" "ok" "doctor prints ok when OCR language is installed"
}

main() {
  test_doctor_fails_when_lang_missing
  test_doctor_passes_when_lang_present_exact_match
  echo "ok"
}

main "$@"
