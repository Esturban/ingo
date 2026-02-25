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
  local jq_calls="$2"
  local curl_calls="$3"

  mkdir -p "$dir"

  cat > "$dir/jq" <<EOF
#!/usr/bin/env bash
set -euo pipefail
printf "1\n" >> "$jq_calls"
if [ "\${1:-}" = "-n" ]; then
  printf '{"data":"ok","topK":1,"namespace":"ns","includeMetadata":true,"includeData":true}\n'
else
  cat >/dev/null
  printf '{"match_count":0,"matches":[]}\n'
fi
EOF

  cat > "$dir/curl" <<EOF
#!/usr/bin/env bash
set -euo pipefail
headers_file=""
while [ "\$#" -gt 0 ]; do
  if [ "\$1" = "-D" ]; then
    shift
    headers_file="\$1"
  fi
  shift
done
if [ -n "\$headers_file" ]; then
  printf "HTTP/1.1 200 OK\\r\\n\\r\\n" > "\$headers_file"
fi
printf "1\n" >> "$curl_calls"
printf '{"result":[]}\n200\n'
EOF

  chmod +x "$dir/jq" "$dir/curl"
}

run_query() {
  local mock_bin="$1"
  shift
  PATH="$mock_bin:$PATH" \
    UPSTASH_VECTOR_REST_URL="https://example.test" \
    UPSTASH_VECTOR_REST_TOKEN="token" \
    INGO_NAMESPACE="ns" \
    INGO_ROLE="all" \
    "$ROOT_DIR/bin/ingo" query "hola" "$@"
}

test_valid_top_k_values_are_accepted() {
  local tmp mock_bin jq_calls curl_calls out
  tmp="$(mktemp -d)"
  mock_bin="$tmp/mock-bin"
  jq_calls="$tmp/jq-calls"
  curl_calls="$tmp/curl-calls"
  make_mock_bin "$mock_bin" "$jq_calls" "$curl_calls"

  out="$(run_query "$mock_bin" --top-k 1 2>&1)"
  assert_contains "$out" '"match_count"' "query output is returned for --top-k=1"
  assert_eq "$(wc -l < "$jq_calls" | tr -d ' ')" "2" "jq is invoked twice for valid --top-k=1"
  assert_eq "$(wc -l < "$curl_calls" | tr -d ' ')" "1" "curl is invoked once for valid --top-k=1"

  : > "$jq_calls"
  : > "$curl_calls"
  out="$(run_query "$mock_bin" --top-k 8 2>&1)"
  assert_contains "$out" '"match_count"' "query output is returned for --top-k=8"
  assert_eq "$(wc -l < "$jq_calls" | tr -d ' ')" "2" "jq is invoked twice for valid --top-k=8"
  assert_eq "$(wc -l < "$curl_calls" | tr -d ' ')" "1" "curl is invoked once for valid --top-k=8"
}

assert_invalid_top_k() {
  local mock_bin="$1"
  local jq_calls="$2"
  local curl_calls="$3"
  local expected_message="$4"
  shift 4
  local out status

  set +e
  out="$(run_query "$mock_bin" "$@" 2>&1)"
  status=$?
  set -e

  assert_eq "$status" "2" "invalid --top-k exits with code 2 ($*)"
  assert_eq "$out" "$expected_message" "invalid --top-k prints exact error message ($*)"
  if [ -f "$jq_calls" ]; then
    assert_eq "$(wc -l < "$jq_calls" | tr -d ' ')" "0" "invalid --top-k does not invoke jq ($*)"
  fi
  if [ -f "$curl_calls" ]; then
    assert_eq "$(wc -l < "$curl_calls" | tr -d ' ')" "0" "invalid --top-k does not invoke curl ($*)"
  fi
}

test_invalid_top_k_values_are_rejected() {
  local tmp mock_bin jq_calls curl_calls
  tmp="$(mktemp -d)"
  mock_bin="$tmp/mock-bin"
  jq_calls="$tmp/jq-calls"
  curl_calls="$tmp/curl-calls"
  make_mock_bin "$mock_bin" "$jq_calls" "$curl_calls"

  : > "$jq_calls"; : > "$curl_calls"
  assert_invalid_top_k "$mock_bin" "$jq_calls" "$curl_calls" "invalid --top-k: must be a positive integer" --top-k 0

  : > "$jq_calls"; : > "$curl_calls"
  assert_invalid_top_k "$mock_bin" "$jq_calls" "$curl_calls" "invalid --top-k: must be a positive integer" --top-k -1

  : > "$jq_calls"; : > "$curl_calls"
  assert_invalid_top_k "$mock_bin" "$jq_calls" "$curl_calls" "invalid --top-k: must be a positive integer" --top-k abc

  : > "$jq_calls"; : > "$curl_calls"
  assert_invalid_top_k "$mock_bin" "$jq_calls" "$curl_calls" "invalid --top-k: must be a positive integer" --top-k 1.5

  : > "$jq_calls"; : > "$curl_calls"
  assert_invalid_top_k "$mock_bin" "$jq_calls" "$curl_calls" "invalid --top-k: must be a positive integer" --top-k ""

  : > "$jq_calls"; : > "$curl_calls"
  assert_invalid_top_k "$mock_bin" "$jq_calls" "$curl_calls" "missing value for --top-k" --top-k
}

main() {
  test_valid_top_k_values_are_accepted
  test_invalid_top_k_values_are_rejected
  echo "ok"
}

main "$@"
