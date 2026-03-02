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

assert_not_contains() {
  local haystack="$1"
  local needle="$2"
  local msg="$3"
  if printf "%s" "$haystack" | grep -F -- "$needle" >/dev/null; then
    fail "$msg (unexpected '$needle')"
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
headers_file=""
out_file=""
url=""
while [ "$#" -gt 0 ]; do
  case "$1" in
    -D)
      shift
      headers_file="$1"
      ;;
    -o)
      shift
      out_file="$1"
      ;;
    http://*|https://*)
      url="$1"
      ;;
  esac
  shift
done
[ -n "$headers_file" ] && printf "HTTP/1.1 200 OK\r\n\r\n" > "$headers_file"
case "$url" in
  https://seed.gov.co/index.html)
    cat > "$out_file" <<'HTML'
<html>
  <a href="/doc.pdf">Doc</a>
  <a href="/level1.html">Level1</a>
  <a href="https://example.com/nope.txt">Off-domain page</a>
</html>
HTML
    ;;
  https://seed.gov.co/level1.html)
    cat > "$out_file" <<'HTML'
<html><a href="/level2/deep.pdf">Deep</a></html>
HTML
    ;;
  https://seed.gov.co/doc.pdf)
    printf "doc-1" > "$out_file"
    ;;
  https://seed.gov.co/level2/deep.pdf)
    printf "doc-2" > "$out_file"
    ;;
  *)
    printf "" > "$out_file"
    ;;
esac
MOCK
  chmod +x "$mock_bin/curl"
}

test_depth_policy() {
  local tmp repo mock_bin seeds allow_hosts out discovered latest
  tmp="$(mktemp -d)"
  repo="$tmp/repo"
  mock_bin="$tmp/mock-bin"
  setup_repo "$tmp"
  write_mock_curl "$mock_bin"

  mkdir -p "$repo/data/corpus/seeds" "$repo/data/corpus/config"
  seeds="$repo/data/corpus/seeds/seed_urls.txt"
  allow_hosts="$repo/data/corpus/config/allow_hosts.txt"
  printf "https://seed.gov.co/index.html\n" > "$seeds"
  : > "$allow_hosts"

  out="$(
    cd "$repo" &&
    PATH="$mock_bin:$PATH" \
      INGO_ROLE="all" \
      INGO_INBOX="$repo/inbox" \
      INGO_RAW_DIR="data/raw" \
      INGO_CHUNK_DIR="data/chunks" \
      INGO_REJECTED_DIR="data/rejected" \
      UPSTASH_VECTOR_REST_URL="https://vector.example.test" \
      UPSTASH_VECTOR_REST_TOKEN="token" \
      ./bin/ingo fetch --seeds "$seeds" --crawl-depth 1 --allow-hosts "$allow_hosts"
  )"

  assert_contains "$out" "crawl-depth: 1" "crawl depth should be reported"
  latest="$(ls -1 "$repo/data/corpus/crawl"/discovered-*.txt | sort | tail -n 1)"
  discovered="$(cat "$latest")"
  assert_contains "$discovered" "https://seed.gov.co/doc.pdf" "depth 1 should discover first-level doc"
  assert_not_contains "$discovered" "https://seed.gov.co/level2/deep.pdf" "depth 1 should not discover second-level doc"
}

main() {
  test_depth_policy
  echo "ok"
}

main "$@"
