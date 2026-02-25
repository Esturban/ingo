#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# shellcheck source=../lib/ocr.sh
source "$ROOT_DIR/lib/ocr.sh"
# shellcheck source=../lib/chunk.sh
source "$ROOT_DIR/lib/chunk.sh"
# shellcheck source=../lib/embed.sh
source "$ROOT_DIR/lib/embed.sh"

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

assert_non_empty() {
  local value="$1"
  local msg="$2"
  if [ -z "$value" ]; then
    fail "$msg"
  fi
}

assert_ne() {
  local left="$1"
  local right="$2"
  local msg="$3"
  if [ "$left" = "$right" ]; then
    fail "$msg (both='$left')"
  fi
}

test_collision_safe_keys_and_embed_meta_lookup() {
  local tmp mock_bin root inbox raw chunks txt_a txt_b key_a key_b
  local first_raw_txt second_raw_txt
  tmp="$(mktemp -d)"
  mock_bin="$tmp/mock-bin"
  root="$tmp/repo"
  inbox="$root/data/ingest"
  raw="$root/data/raw"
  chunks="$root/data/chunks"

  mkdir -p "$mock_bin" "$inbox/a" "$inbox/b" "$raw" "$chunks"

  cat > "$mock_bin/pdftotext" <<'EOF'
#!/usr/bin/env bash
in="$2"
out="$3"
printf "source=%s\n" "$in" > "$out"
EOF
  chmod +x "$mock_bin/pdftotext"

  cat > "$mock_bin/sha256sum" <<'EOF'
#!/usr/bin/env bash
/usr/bin/shasum -a 256 "$@"
EOF
  chmod +x "$mock_bin/sha256sum"

  touch "$inbox/a/report.pdf" "$inbox/b/report.pdf"

  PATH="$mock_bin:$PATH"

  txt_a="$(ingo_ocr_pdf "$inbox/a/report.pdf" "$raw" "spa" "$root")"
  txt_b="$(ingo_ocr_pdf "$inbox/b/report.pdf" "$raw" "spa" "$root")"
  key_a="$(basename "$txt_a" .txt)"
  key_b="$(basename "$txt_b" .txt)"
  assert_ne "$key_a" "$key_b" "artifact keys must differ for same basename in different dirs"

  assert_non_empty "$(ls "$raw"/"$key_a".txt 2>/dev/null)" "raw txt exists for first file"
  assert_non_empty "$(ls "$raw"/"$key_b".txt 2>/dev/null)" "raw txt exists for second file"
  assert_non_empty "$(ls "$raw"/"$key_a".meta 2>/dev/null)" "raw meta exists for first file"
  assert_non_empty "$(ls "$raw"/"$key_b".meta 2>/dev/null)" "raw meta exists for second file"

  assert_eq "$(grep '^file_path=' "$raw/$key_a.meta" | cut -d= -f2-)" "data/ingest/a/report.pdf" "meta keeps original relative path for first file"
  assert_eq "$(grep '^file_path=' "$raw/$key_b.meta" | cut -d= -f2-)" "data/ingest/b/report.pdf" "meta keeps original relative path for second file"
  assert_eq "$(grep '^file_name=' "$raw/$key_a.meta" | cut -d= -f2-)" "report.pdf" "meta keeps original file name for first file"
  assert_eq "$(grep '^file_name=' "$raw/$key_b.meta" | cut -d= -f2-)" "report.pdf" "meta keeps original file name for second file"

  ingo_chunk_txt "$txt_a" "$chunks/$key_a.jsonl" "80" "0"
  ingo_chunk_txt "$txt_b" "$chunks/$key_b.jsonl" "80" "0"

  assert_non_empty "$(ls "$chunks/$key_a.jsonl" 2>/dev/null)" "chunk jsonl exists for first file"
  assert_non_empty "$(ls "$chunks/$key_b.jsonl" 2>/dev/null)" "chunk jsonl exists for second file"

  first_raw_txt="$(find "$raw" -maxdepth 1 -type f -name '*.txt' | sort)"
  ingo_ocr_pdf "$inbox/a/report.pdf" "$raw" "spa" "$root" >/dev/null
  ingo_ocr_pdf "$inbox/b/report.pdf" "$raw" "spa" "$root" >/dev/null
  second_raw_txt="$(find "$raw" -maxdepth 1 -type f -name '*.txt' | sort)"
  assert_eq "$second_raw_txt" "$first_raw_txt" "artifact keys stay stable across reruns"

  local seen_a=0 seen_b=0
  ingo_upsert_line() {
    local line="$1"
    local _namespace="$2"
    local meta_file="$3"
    local line_source meta_source line_rel
    line_source="$(printf "%s\n" "$line" | jq -r '.text' | sed -n 's/^source=//p')"
    meta_source="$(grep '^file_path=' "$meta_file" | cut -d= -f2-)"
    line_rel="${line_source#"$root"/}"
    assert_eq "$meta_source" "$line_rel" "embed should read matching meta file for chunk source"
    case "$meta_source" in
      data/ingest/a/report.pdf) seen_a=1 ;;
      data/ingest/b/report.pdf) seen_b=1 ;;
    esac
  }

  ingo_embed_jsonl "$chunks/$key_a.jsonl" "ns" "$raw" >/dev/null
  ingo_embed_jsonl "$chunks/$key_b.jsonl" "ns" "$raw" >/dev/null
  assert_eq "$seen_a" "1" "embed processed first source path"
  assert_eq "$seen_b" "1" "embed processed second source path"
}

main() {
  test_collision_safe_keys_and_embed_meta_lookup
  echo "ok"
}

main "$@"
