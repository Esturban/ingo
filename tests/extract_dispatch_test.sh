#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/manifest.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/manifest.sh"
# shellcheck source=../lib/extract.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/extract.sh"

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

setup_mocks() {
  local dir="$1"
  cat > "$dir/pdftotext" <<'MOCK'
#!/usr/bin/env bash
printf "pdf text" > "$3"
MOCK
  cat > "$dir/pandoc" <<'MOCK'
#!/usr/bin/env bash
out=""
while [ "$#" -gt 0 ]; do
  [ "$1" = "-o" ] && shift && out="$1"
  shift
done
printf "pandoc text" > "$out"
MOCK
  cat > "$dir/python3" <<'MOCK'
#!/usr/bin/env bash
out="$3"
printf "## SHEET: Mock\na\tb\n" > "$out"
MOCK
  chmod +x "$dir/pdftotext" "$dir/pandoc" "$dir/python3"
}

test_extract_routing() {
  local tmp manifest extracted summary
  tmp="$(mktemp -d)"
  manifest="$tmp/documents.ndjson"
  extracted="$tmp/extracted"
  ROOT_DIR="$tmp"

  mkdir -p "$tmp/downloads"
  printf "x" > "$tmp/downloads/a.pdf"
  printf "x" > "$tmp/downloads/b.docx"
  printf "<html>x</html>" > "$tmp/downloads/c.html"
  printf "x" > "$tmp/downloads/d.xlsm"

  cat > "$manifest" <<'JSON'
{"doc_id":"sha256:a","status":"downloaded","file_ext":"pdf","local_path":"downloads/a.pdf"}
{"doc_id":"sha256:b","status":"downloaded","file_ext":"docx","local_path":"downloads/b.docx"}
{"doc_id":"sha256:c","status":"downloaded","file_ext":"html","local_path":"downloads/c.html"}
{"doc_id":"sha256:d","status":"downloaded","file_ext":"xlsm","local_path":"downloads/d.xlsm"}
JSON

  setup_mocks "$tmp"
  PATH="$tmp:$PATH"
  summary="$(ingo_extract_manifest_documents "$manifest" "$extracted")"

  assert_contains "$summary" "extracted=4" "supported formats extracted"
  assert_contains "$summary" "unsupported=0" "no unsupported formats in fixture"
  assert_contains "$(cat "$manifest")" '"status":"extracted"' "manifest updates extracted status"
}

main() {
  test_extract_routing
  echo "ok"
}

main "$@"
