#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

setup_repo() {
  local tmp="$1"
  mkdir -p "$tmp/repo"
  cp -R "$ROOT_DIR/bin" "$tmp/repo/bin"
  cp -R "$ROOT_DIR/lib" "$tmp/repo/lib"
}

write_mock_curl() {
  local mock_bin="$1"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/curl" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
out=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "-o" ]; then
    shift
    out="$1"
  fi
  shift
done
printf "pdf" > "$out"
MOCK
  chmod +x "$mock_bin/curl"
}

test_fetch_legacy_modes() {
  local tmp repo mock_bin inbox out list
  tmp="$(mktemp -d)"
  repo="$tmp/repo"
  mock_bin="$tmp/mock-bin"
  inbox="$repo/inbox"

  setup_repo "$tmp"
  write_mock_curl "$mock_bin"
  mkdir -p "$inbox"
  printf "a" > "$inbox/existing.pdf"

  list="$(
    cd "$repo" &&
    PATH="$mock_bin:$PATH" \
      INGO_ROLE="all" \
      INGO_INBOX="$inbox" \
      INGO_RAW_DIR="data/raw" \
      INGO_CHUNK_DIR="data/chunks" \
      INGO_REJECTED_DIR="data/rejected" \
      UPSTASH_VECTOR_REST_URL="https://vector.example.test" \
      UPSTASH_VECTOR_REST_TOKEN="token" \
      ./bin/ingo fetch
  )"
  assert_contains "$list" "$inbox/existing.pdf" "fetch without args still lists PDFs"

  out="$(
    cd "$repo" &&
    PATH="$mock_bin:$PATH" \
      INGO_ROLE="all" \
      INGO_RAW_DIR="data/raw" \
      INGO_CHUNK_DIR="data/chunks" \
      INGO_REJECTED_DIR="data/rejected" \
      UPSTASH_VECTOR_REST_URL="https://vector.example.test" \
      UPSTASH_VECTOR_REST_TOKEN="token" \
      ./bin/ingo fetch --url "https://seed.gov.co/a.pdf" --dir "$inbox"
  )"
  assert_contains "$out" "fetched: $inbox/" "fetch --url still downloads into inbox"
}

main() {
  test_fetch_legacy_modes
  echo "ok"
}

main "$@"
