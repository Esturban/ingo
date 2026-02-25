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

setup_isolated_repo() {
  local tmp="$1"
  mkdir -p "$tmp/repo"
  cp -R "$ROOT_DIR/bin" "$tmp/repo/bin"
  cp -R "$ROOT_DIR/lib" "$tmp/repo/lib"
  mkdir -p "$tmp/repo/data/chunks" "$tmp/repo/data/raw" "$tmp/repo/data/rejected" "$tmp/repo/inbox"
}

write_mock_curl() {
  local mock_bin="$1"
  local counter_file="$2"
  mkdir -p "$mock_bin"
  cat > "$mock_bin/curl" <<EOF
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
count=0
if [ -f "$counter_file" ]; then
  count="\$(cat "$counter_file")"
fi
printf "%s\\n" "\$((count + 1))" > "$counter_file"
printf '{"ok":true}\\n200\\n'
EOF
  chmod +x "$mock_bin/curl"
}

test_embed_marker_rerun_behavior() {
  local tmp repo mock_bin counter chunk marker out
  tmp="$(mktemp -d)"
  repo="$tmp/repo"
  mock_bin="$tmp/mock-bin"
  counter="$tmp/curl-count"

  setup_isolated_repo "$tmp"
  write_mock_curl "$mock_bin" "$counter"

  chunk="$repo/data/chunks/sample.jsonl"
  marker="$chunk.embedded"
  cat > "$chunk" <<'EOF'
{"id":"c1","text":"alpha","source":"s","section":"sec","article":"art","start":0,"end":5}
EOF

  out="$(
    cd "$repo" && \
    PATH="$mock_bin:$PATH" \
    INGO_ROLE="all" \
    INGO_INBOX="$repo/inbox" \
    INGO_RAW_DIR="data/raw" \
    INGO_CHUNK_DIR="data/chunks" \
    INGO_REJECTED_DIR="data/rejected" \
    INGO_NAMESPACE="ns-a" \
    UPSTASH_VECTOR_REST_URL="https://vector.example.test" \
    UPSTASH_VECTOR_REST_TOKEN="token" \
    ./bin/ingo embed 2>&1
  )"
  assert_contains "$out" "embed: $repo/data/chunks/sample.jsonl -> 1 vectors" "first run embeds chunk"
  assert_eq "$(cat "$counter")" "1" "first run performs one upsert"
  assert_contains "$(cat "$marker")" "chunk_hash=" "marker stores chunk hash"
  assert_contains "$(cat "$marker")" "namespace=ns-a" "marker stores namespace"

  out="$(
    cd "$repo" && \
    PATH="$mock_bin:$PATH" \
    INGO_ROLE="all" \
    INGO_INBOX="$repo/inbox" \
    INGO_RAW_DIR="data/raw" \
    INGO_CHUNK_DIR="data/chunks" \
    INGO_REJECTED_DIR="data/rejected" \
    INGO_NAMESPACE="ns-a" \
    UPSTASH_VECTOR_REST_URL="https://vector.example.test" \
    UPSTASH_VECTOR_REST_TOKEN="token" \
    ./bin/ingo embed 2>&1
  )"
  assert_contains "$out" "embed-skip: $repo/data/chunks/sample.jsonl" "matching marker skips embed"
  assert_eq "$(cat "$counter")" "1" "skip does not perform extra upserts"

  cat > "$chunk" <<'EOF'
{"id":"c1","text":"beta","source":"s","section":"sec","article":"art","start":0,"end":4}
EOF
  out="$(
    cd "$repo" && \
    PATH="$mock_bin:$PATH" \
    INGO_ROLE="all" \
    INGO_INBOX="$repo/inbox" \
    INGO_RAW_DIR="data/raw" \
    INGO_CHUNK_DIR="data/chunks" \
    INGO_REJECTED_DIR="data/rejected" \
    INGO_NAMESPACE="ns-a" \
    UPSTASH_VECTOR_REST_URL="https://vector.example.test" \
    UPSTASH_VECTOR_REST_TOKEN="token" \
    ./bin/ingo embed 2>&1
  )"
  assert_contains "$out" "embed: $repo/data/chunks/sample.jsonl -> 1 vectors" "changed chunk triggers re-embed"
  assert_eq "$(cat "$counter")" "2" "content change performs upsert again"

  out="$(
    cd "$repo" && \
    PATH="$mock_bin:$PATH" \
    INGO_ROLE="all" \
    INGO_INBOX="$repo/inbox" \
    INGO_RAW_DIR="data/raw" \
    INGO_CHUNK_DIR="data/chunks" \
    INGO_REJECTED_DIR="data/rejected" \
    INGO_NAMESPACE="ns-a" \
    UPSTASH_VECTOR_REST_URL="https://vector.example.test" \
    UPSTASH_VECTOR_REST_TOKEN="token" \
    ./bin/ingo embed --force 2>&1
  )"
  assert_contains "$out" "embed: $repo/data/chunks/sample.jsonl -> 1 vectors" "force bypasses matching marker"
  assert_eq "$(cat "$counter")" "3" "force performs upsert even with unchanged content"

  printf "1\n" > "$marker"
  out="$(
    cd "$repo" && \
    PATH="$mock_bin:$PATH" \
    INGO_ROLE="all" \
    INGO_INBOX="$repo/inbox" \
    INGO_RAW_DIR="data/raw" \
    INGO_CHUNK_DIR="data/chunks" \
    INGO_REJECTED_DIR="data/rejected" \
    INGO_NAMESPACE="ns-a" \
    UPSTASH_VECTOR_REST_URL="https://vector.example.test" \
    UPSTASH_VECTOR_REST_TOKEN="token" \
    ./bin/ingo embed 2>&1
  )"
  assert_contains "$out" "embed: $repo/data/chunks/sample.jsonl -> 1 vectors" "legacy marker is treated as stale and re-embedded"
  assert_eq "$(cat "$counter")" "4" "legacy marker compatibility re-embeds"
}

main() {
  test_embed_marker_rerun_behavior
  echo "ok"
}

main "$@"
