#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/fetch.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/fetch.sh"

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

setup_isolated_repo() {
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
[ -n "$out" ] || exit 9
printf "pdf" > "$out"
MOCK
  chmod +x "$mock_bin/curl"
}

test_cmd_fetch_creates_custom_dir_before_download() {
  local tmp repo mock_bin custom_dir out
  tmp="$(mktemp -d)"
  repo="$tmp/repo"
  mock_bin="$tmp/mock-bin"
  custom_dir="$repo/does/not/exist/yet"

  setup_isolated_repo "$tmp"
  write_mock_curl "$mock_bin"

  out="$({
    cd "$repo"
    PATH="$mock_bin:$PATH" \
      INGO_ROLE="all" \
      INGO_RAW_DIR="data/raw" \
      INGO_CHUNK_DIR="data/chunks" \
      INGO_REJECTED_DIR="data/rejected" \
      ./bin/ingo fetch --url "https://example.test/a.pdf" --dir "$custom_dir"
  } 2>&1)"

  [ -d "$custom_dir" ] || fail "custom --dir should be created before fetch"
  assert_contains "$out" "fetched: $custom_dir/" "fetch reports output file in custom dir"
}

test_reserve_fails_fast_for_missing_or_unwritable_inbox() {
  local missing tmp unwritable out status

  missing="$(mktemp -u)"
  set +e
  out="$(ingo_reserve_fetch_output "$missing" 2>&1)"
  status=$?
  set -e
  assert_eq "$status" "2" "missing inbox should fail with exit code 2"
  assert_contains "$out" "does not exist" "missing inbox should report clear error"

  tmp="$(mktemp -d)"
  unwritable="$tmp/unwritable"
  mkdir -p "$unwritable"
  chmod 0555 "$unwritable"

  set +e
  out="$(ingo_reserve_fetch_output "$unwritable" 2>&1)"
  status=$?
  set -e

  if [ "$(id -u)" -ne 0 ]; then
    assert_eq "$status" "2" "unwritable inbox should fail with exit code 2"
    assert_contains "$out" "not writable" "unwritable inbox should report clear error"
  fi
}

test_reserve_works_when_bashpid_is_unset() {
  local tmp out
  tmp="$(mktemp -d)"

  unset BASHPID || true
  out="$(ingo_reserve_fetch_output "$tmp")"

  [ -f "$out" ] || fail "reservation should create file when BASHPID is unavailable"
  assert_contains "$out" "-$$-" "fallback should use $$ when BASHPID is unset"
}

main() {
  test_cmd_fetch_creates_custom_dir_before_download
  test_reserve_fails_fast_for_missing_or_unwritable_inbox
  test_reserve_works_when_bashpid_is_unset
  echo "ok"
}

main "$@"
