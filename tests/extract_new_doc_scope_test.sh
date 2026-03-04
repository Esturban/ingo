#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/manifest.sh"
source "$ROOT_DIR/lib/extract.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

main() {
  local tmp manifest extracted ids summary
  tmp="$(mktemp -d)"
  ROOT_DIR="$tmp"
  manifest="$tmp/documents.ndjson"
  extracted="$tmp/extracted"
  ids="$tmp/new_doc_ids.txt"

  mkdir -p "$tmp/downloads"
  printf "pdf1" > "$tmp/downloads/one.pdf"
  printf "pdf2" > "$tmp/downloads/two.pdf"
  cat > "$manifest" <<'JSON'
{"doc_id":"sha256:one","status":"downloaded","file_ext":"pdf","local_path":"downloads/one.pdf"}
{"doc_id":"sha256:two","status":"downloaded","file_ext":"pdf","local_path":"downloads/two.pdf"}
JSON
  printf "sha256:two\n" > "$ids"

  pdftotext() {
    local input="$2"
    local output="$3"
    printf "text for %s" "$input" > "$output"
  }

  summary="$(ingo_extract_manifest_documents "$manifest" "$extracted" "$ids")"
  echo "$summary" | grep -F "extracted=1" >/dev/null || fail "should only extract newly downloaded doc ids"
  [ -f "$extracted/two.txt" ] || fail "scoped doc should be extracted"
  [ ! -f "$extracted/one.txt" ] || fail "non-scoped downloaded doc should not be extracted"
}

main
echo ok
