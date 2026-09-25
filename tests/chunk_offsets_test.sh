#!/usr/bin/env bash
# REUSE_CHECKED: /Users/EVA/Desktop/eva/03_development/_dev/repos/3_utilities/sh/ingo/tests/query_top_k_validation_test.sh
# matched its fail/assert_eq/assert_contains/test_*/main() style; no
# existing test already covers the DEV-6550 page/paragraph/line offset
# engine in lib/chunk.sh.

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/chunk.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/chunk.sh"

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

# A small synthetic 3-page document exercising: an ALL-CAPS accented
# CAPITULO heading (regression for the LC_ALL=C tolower() UTF-8 bug), an
# ARTICULO spanning a page boundary's neighbourhood, a PARAGRAFO, two
# numeral items, and one page (2) that has zero extractable text -- like a
# scanned figure -- to exercise the back-to-back form-feed case.
make_fixture() {
  local out="$1"
  printf 'CAPÍTULO I\n\nArtículo 1°. Objeto.\n\nEsta norma regula el vertimiento de aguas residuales.\n\nPARAGRAFO 1. Se exceptúan los vertimientos domésticos rurales.\n\n1. Primer criterio de excepción.\n\n2. Segundo criterio de excepción.\n' > "$out"
  printf '\014' >> "$out"
  printf '\014' >> "$out"
  printf 'Artículo 2°. Definiciones.\n\nPara los efectos de este decreto se entiende por vertimiento la descarga final.\n' >> "$out"
  printf '\014' >> "$out"
}

test_page_tracking_survives_a_blank_page() {
  local tmp txt out
  tmp="$(mktemp -d)"
  txt="$tmp/doc.txt"
  out="$tmp/chunks.jsonl"
  make_fixture "$txt"

  INGO_SECTION_PATTERN='^[[:space:]]*(seccion|sección|capitulo|capítulo|titulo|título)[[:space:]]+' \
  INGO_ARTICLE_PATTERN='^[[:space:]]*(articulo|artículo)[[:space:]]+[0-9][0-9a-z°.-]*' \
  INGO_PARAGRAPH_PATTERN='^[[:space:]]*(paragrafo|parágrafo)([[:space:]]+(transitorio|[0-9][0-9a-z°.-]*))?[.:]?' \
  INGO_NUMERAL_PATTERN='^[[:space:]]*([0-9]{1,3}|[a-z])[.)][[:space:]]+' \
    ingo_chunk_txt "$txt" "$out" 1400 40

  [ -s "$out" ] || fail "chunker produced no output"

  local max_page
  max_page="$(jq -r '.page' "$out" | sort -n | tail -1)"
  assert_eq "$max_page" "3" "the blank page (2) still advances the page counter to 3, not 2"

  local article2_page
  article2_page="$(jq -r 'select(.article | test("Art.*culo 2")) | .page' "$out" | head -1)"
  assert_eq "$article2_page" "3" "Articulo 2 (after the blank page) is attributed to page 3"

  local section_val
  section_val="$(jq -r 'select(.article | test("Art.*culo 1")) | .section' "$out" | head -1)"
  case "$section_val" in
    *"CAPÍTULO I"*) : ;;
    *) fail "ALL-CAPS accented 'CAPÍTULO I' heading was not detected as a section (got '$section_val') -- LC_ALL=C tolower() UTF-8 regression" ;;
  esac
}

test_article_is_never_split_across_chunks() {
  local tmp txt out
  tmp="$(mktemp -d)"
  txt="$tmp/doc.txt"
  out="$tmp/chunks.jsonl"
  make_fixture "$txt"

  INGO_SECTION_PATTERN='^[[:space:]]*(seccion|sección|capitulo|capítulo|titulo|título)[[:space:]]+' \
  INGO_ARTICLE_PATTERN='^[[:space:]]*(articulo|artículo)[[:space:]]+[0-9][0-9a-z°.-]*' \
  INGO_PARAGRAPH_PATTERN='^[[:space:]]*(paragrafo|parágrafo)([[:space:]]+(transitorio|[0-9][0-9a-z°.-]*))?[.:]?' \
  INGO_NUMERAL_PATTERN='^[[:space:]]*([0-9]{1,3}|[a-z])[.)][[:space:]]+' \
    ingo_chunk_txt "$txt" "$out" 1400 40

  local distinct_articles
  distinct_articles="$(jq -r 'select(.article != "") | .article' "$out" | sort -u | wc -l | tr -d ' ')"
  assert_eq "$distinct_articles" "2" "exactly two distinct 'articulo' values appear across all chunks"

  local numeral_count
  numeral_count="$(jq -c 'select(.numeral_marker != "")' "$out" | wc -l | tr -d ' ')"
  [ "$numeral_count" -ge 2 ] || fail "expected at least 2 chunks carrying a numeral_marker, got $numeral_count"

  local paragraph_marker_count
  paragraph_marker_count="$(jq -c 'select(.paragraph_marker != "")' "$out" | wc -l | tr -d ' ')"
  [ "$paragraph_marker_count" -ge 1 ] || fail "expected at least 1 chunk carrying the PARAGRAFO marker"
}

test_offsets_open_to_the_exact_verbatim_text() {
  local tmp txt out
  tmp="$(mktemp -d)"
  txt="$tmp/doc.txt"
  out="$tmp/chunks.jsonl"
  make_fixture "$txt"

  INGO_SECTION_PATTERN='^[[:space:]]*(seccion|sección|capitulo|capítulo|titulo|título)[[:space:]]+' \
  INGO_ARTICLE_PATTERN='^[[:space:]]*(articulo|artículo)[[:space:]]+[0-9][0-9a-z°.-]*' \
  INGO_PARAGRAPH_PATTERN='^[[:space:]]*(paragrafo|parágrafo)([[:space:]]+(transitorio|[0-9][0-9a-z°.-]*))?[.:]?' \
  INGO_NUMERAL_PATTERN='^[[:space:]]*([0-9]{1,3}|[a-z])[.)][[:space:]]+' \
    ingo_chunk_txt "$txt" "$out" 1400 40

  python3 "$ROOT_DIR/tests/fixtures/verify_offsets.py" "$txt" "$out" \
    || fail "one or more chunks' (page, line_start, line_end) do not open to their own verbatim text"
}

main() {
  test_page_tracking_survives_a_blank_page
  test_article_is_never_split_across_chunks
  test_offsets_open_to_the_exact_verbatim_text
  echo "ok"
}

main "$@"
