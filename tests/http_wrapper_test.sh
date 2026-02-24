#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/env.sh
source "$ROOT_DIR/lib/env.sh"
# shellcheck source=../lib/http.sh
source "$ROOT_DIR/lib/http.sh"
# shellcheck source=../lib/fetch.sh
source "$ROOT_DIR/lib/fetch.sh"
# shellcheck source=../lib/embed.sh
source "$ROOT_DIR/lib/embed.sh"
# shellcheck source=../lib/query.sh
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

test_http_defaults() {
  unset INGO_HTTP_CONNECT_TIMEOUT INGO_HTTP_READ_TIMEOUT INGO_HTTP_RETRY_ATTEMPTS INGO_HTTP_RETRY_BACKOFF_MIN INGO_HTTP_RETRY_BACKOFF_MAX INGO_HTTP_RETRY_BACKOFF_FACTOR INGO_HTTP_RETRY_MAX INGO_HTTP_RETRY_BACKOFF
  ingo_load_env
  assert_eq "$INGO_HTTP_CONNECT_TIMEOUT" "5" "default connect timeout"
  assert_eq "$INGO_HTTP_READ_TIMEOUT" "30" "default read timeout"
  assert_eq "$INGO_HTTP_RETRY_ATTEMPTS" "2" "default retry attempts"
  assert_eq "$INGO_HTTP_RETRY_BACKOFF_MIN" "1" "default retry backoff min"
  assert_eq "$INGO_HTTP_RETRY_BACKOFF_MAX" "8" "default retry backoff max"
  assert_eq "$INGO_HTTP_RETRY_BACKOFF_FACTOR" "2" "default retry backoff factor"
  assert_eq "$INGO_HTTP_RETRY_MAX" "2" "default retry max"
  assert_eq "$INGO_HTTP_RETRY_BACKOFF" "1" "default retry backoff"
}

test_http_overrides() {
  INGO_HTTP_CONNECT_TIMEOUT="9"
  INGO_HTTP_READ_TIMEOUT="44"
  INGO_HTTP_RETRY_ATTEMPTS="7"
  INGO_HTTP_RETRY_BACKOFF_MIN="3"
  INGO_HTTP_RETRY_BACKOFF_MAX="21"
  INGO_HTTP_RETRY_BACKOFF_FACTOR="4"
  ingo_load_env
  assert_eq "$INGO_HTTP_CONNECT_TIMEOUT" "9" "override connect timeout"
  assert_eq "$INGO_HTTP_READ_TIMEOUT" "44" "override read timeout"
  assert_eq "$INGO_HTTP_RETRY_ATTEMPTS" "7" "override retry attempts"
  assert_eq "$INGO_HTTP_RETRY_BACKOFF_MIN" "3" "override retry backoff min"
  assert_eq "$INGO_HTTP_RETRY_BACKOFF_MAX" "21" "override retry backoff max"
  assert_eq "$INGO_HTTP_RETRY_BACKOFF_FACTOR" "4" "override retry backoff factor"
  assert_eq "$INGO_HTTP_RETRY_MAX" "7" "override retry max"
  assert_eq "$INGO_HTTP_RETRY_BACKOFF" "3" "override retry backoff"
}

test_http_legacy_alias_overrides() {
  unset INGO_HTTP_RETRY_ATTEMPTS INGO_HTTP_RETRY_BACKOFF_MIN INGO_HTTP_RETRY_BACKOFF_MAX INGO_HTTP_RETRY_BACKOFF_FACTOR
  INGO_HTTP_RETRY_MAX="6"
  INGO_HTTP_RETRY_BACKOFF="4"
  ingo_load_env
  assert_eq "$INGO_HTTP_RETRY_ATTEMPTS" "6" "legacy retry max maps to attempts"
  assert_eq "$INGO_HTTP_RETRY_BACKOFF_MIN" "4" "legacy retry backoff maps to min"
  assert_eq "$INGO_HTTP_RETRY_BACKOFF_MAX" "8" "legacy override keeps default max"
  assert_eq "$INGO_HTTP_RETRY_BACKOFF_FACTOR" "2" "legacy override keeps default factor"
}

test_http_wrapper_curl_flags() {
  local args_file
  args_file="$(mktemp)"

  curl() {
    printf "%s\n" "$@" > "$args_file"
  }

  INGO_HTTP_CONNECT_TIMEOUT="11"
  INGO_HTTP_READ_TIMEOUT="22"
  INGO_HTTP_RETRY_ATTEMPTS="4"
  INGO_HTTP_RETRY_BACKOFF_MIN="2"
  ingo_http_curl -fsSL "https://example.com/a.pdf" -o "/tmp/out.pdf"

  local args
  args="$(cat "$args_file")"
  assert_contains "$args" "--connect-timeout" "wrapper adds connect-timeout flag"
  assert_contains "$args" "11" "wrapper uses connect-timeout value"
  assert_contains "$args" "--max-time" "wrapper adds max-time flag"
  assert_contains "$args" "22" "wrapper uses max-time value"
  assert_contains "$args" "--retry" "wrapper adds retry flag"
  assert_contains "$args" "4" "wrapper uses retry value"
  assert_contains "$args" "--retry-delay" "wrapper adds retry-delay flag"
  assert_contains "$args" "2" "wrapper uses retry-delay value"
  assert_contains "$args" "--retry-connrefused" "wrapper adds retry-connrefused flag"
  assert_contains "$args" "https://example.com/a.pdf" "wrapper keeps original curl args"
}

test_fetch_uses_http_wrapper() {
  local inbox args_file out
  inbox="$(mktemp -d)"
  args_file="$(mktemp)"

  ingo_http_curl() {
    printf "%s\n" "$@" > "$args_file"
    return 0
  }

  out="$(ingo_fetch_url "https://example.com/contract.pdf" "$inbox")"
  assert_contains "$out" "$inbox/" "fetch output path"
  assert_contains "$out" ".pdf" "fetch output suffix"

  local args
  args="$(cat "$args_file")"
  assert_contains "$args" "-fsSL" "fetch passes curl flags via wrapper"
  assert_contains "$args" "https://example.com/contract.pdf" "fetch passes URL via wrapper"
}

test_embed_and_query_use_http_wrapper() {
  local upsert_args query_args
  upsert_args="$(mktemp)"
  query_args="$(mktemp)"

  ingo_http_curl() {
    if printf "%s\n" "$@" | grep -F "/upsert-data" >/dev/null; then
      printf "%s\n" "$@" > "$upsert_args"
      printf '{"ok":true}\n200\n'
      return 0
    fi
    printf "%s\n" "$@" > "$query_args"
    printf '{"result":[{"id":"id-1","score":0.9,"metadata":{"text":"ok"}}]}\n200\n'
  }

  export UPSTASH_VECTOR_REST_URL="https://vector.example.test"
  export UPSTASH_VECTOR_REST_TOKEN="token"

  ingo_upsert_line '{"id":"id-1","text":"hola","source":"src","section":"s","article":"a","start":1,"end":2}' "ns"
  local query_json
  query_json="$(ingo_query_text "hola" 1 "ns")"

  local upsert_call
  upsert_call="$(cat "$upsert_args")"
  assert_contains "$upsert_call" "https://vector.example.test/upsert-data" "embed upsert URL via wrapper"

  local query_call
  query_call="$(cat "$query_args")"
  assert_contains "$query_call" "https://vector.example.test/query-data" "query URL via wrapper"

  assert_eq "$(printf "%s" "$query_json" | jq -r '.match_count')" "1" "query body contract preserved"
}

main() {
  test_http_defaults
  test_http_overrides
  test_http_legacy_alias_overrides
  test_http_wrapper_curl_flags
  test_fetch_uses_http_wrapper
  test_embed_and_query_use_http_wrapper
  echo "ok"
}

main "$@"
