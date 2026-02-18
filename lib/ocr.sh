#!/usr/bin/env bash

set -euo pipefail

ingo_ocr_pdf() {
  local pdf="$1"
  local out_dir="$2"
  local lang="$3"
  local base stem out_base out_txt

  base="$(basename "$pdf")"
  stem="${base%.pdf}"
  out_base="$out_dir/$stem"
  out_txt="$out_base.txt"

  tesseract "$pdf" "$out_base" -l "$lang" >/dev/null 2>&1
  printf "%s\n" "$out_txt"
}
