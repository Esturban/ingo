#!/usr/bin/env bash

set -euo pipefail

ingo_file_size_bytes() {
  local file="$1"
  if stat -f %z "$file" >/dev/null 2>&1; then
    stat -f %z "$file"
    return 0
  fi
  if stat -c %s "$file" >/dev/null 2>&1; then
    stat -c %s "$file"
    return 0
  fi
  printf "0\n"
}

ingo_file_mtime() {
  local file="$1"
  if stat -f %m "$file" >/dev/null 2>&1; then
    stat -f %m "$file"
    return 0
  fi
  if stat -c %Y "$file" >/dev/null 2>&1; then
    stat -c %Y "$file"
    return 0
  fi
  printf "0\n"
}

ingo_file_sha256() {
  local file="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$file" | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$file" | awk '{print $1}'
    return 0
  fi
  printf "\n"
}

ingo_hash_text() {
  local text="$1"
  if command -v sha256sum >/dev/null 2>&1; then
    printf "%s" "$text" | sha256sum | awk '{print $1}'
    return 0
  fi
  if command -v shasum >/dev/null 2>&1; then
    printf "%s" "$text" | shasum -a 256 | awk '{print $1}'
    return 0
  fi
  cksum <<<"$text" | awk '{print $1}'
}

ingo_pdf_rel_path() {
  local pdf="$1"
  local root="${2:-}"
  if [ -n "$root" ] && [ "${pdf#"$root"/}" != "$pdf" ]; then
    printf "%s\n" "${pdf#"$root"/}"
    return 0
  fi
  printf "%s\n" "$pdf"
}

ingo_pdf_artifact_key() {
  local pdf="$1"
  local root="${2:-}"
  local base stem rel_path digest short_digest

  base="$(basename "$pdf")"
  stem="${base%.*}"
  rel_path="$(ingo_pdf_rel_path "$pdf" "$root")"
  digest="$(ingo_hash_text "$rel_path")"
  short_digest="$(printf "%s" "$digest" | cut -c1-10)"
  printf "%s-%s\n" "$stem" "$short_digest"
}

ingo_ocr_pdf() {
  local pdf="$1"
  local out_dir="$2"
  local lang="$3"
  local root="${4:-}"
  local stem out_base out_txt

  stem="$(ingo_pdf_artifact_key "$pdf" "$root")"
  out_base="$out_dir/$stem"
  out_txt="$out_base.txt"

  if [ -s "$out_txt" ]; then
    ingo_write_meta "$pdf" "$out_base" "$root"
    printf "%s\n" "$out_txt"
    return 0
  fi

  if command -v pdftotext >/dev/null 2>&1; then
    if ! pdftotext -layout "$pdf" "$out_txt" >/dev/null; then
      echo "ocr-error: pdftotext failed for $pdf" >&2
      return 5
    fi
  fi

  if [ ! -s "$out_txt" ]; then
    if ! command -v pdftoppm >/dev/null 2>&1; then
      echo "ocr-error: pdftoppm not found for $pdf" >&2
      return 5
    fi

    local tmpdir page_img page_base page_txt
    tmpdir="$(mktemp -d "$out_dir/.ocr-${stem}.XXXX")"
    trap 'rm -rf "$tmpdir"' RETURN

    if ! pdftoppm -r 300 -png "$pdf" "$tmpdir/$stem" >/dev/null; then
      echo "ocr-error: pdftoppm failed for $pdf" >&2
      return 5
    fi

    : > "$out_txt"
    for page_img in "$tmpdir"/"$stem"-*.png; do
      [ -e "$page_img" ] || continue
      page_base="${page_img%.png}"
      if ! tesseract "$page_img" "$page_base" -l "$lang" >/dev/null; then
        echo "ocr-error: tesseract failed for $page_img" >&2
        return 5
      fi
      page_txt="$page_base.txt"
      if [ -s "$page_txt" ]; then
        cat "$page_txt" >> "$out_txt"
        printf "\n" >> "$out_txt"
      fi
    done
  fi

  if [ ! -s "$out_txt" ]; then
    echo "ocr-empty: $pdf -> $out_txt" >&2
    return 6
  fi

  ingo_write_meta "$pdf" "$out_base" "$root"

  printf "%s\n" "$out_txt"
}

ingo_write_meta() {
  local pdf="$1"
  local out_base="$2"
  local root="${3:-}"
  local base rel_path folder_path file_size_bytes file_mtime file_hash meta

  base="$(basename "$pdf")"
  rel_path="$(ingo_pdf_rel_path "$pdf" "$root")"
  folder_path="$(dirname "$rel_path")"
  file_size_bytes="$(ingo_file_size_bytes "$pdf")"
  file_mtime="$(ingo_file_mtime "$pdf")"
  file_hash="$(ingo_file_sha256 "$pdf")"

  meta="$out_base.meta"
  {
    printf "file_path=%s\n" "$rel_path"
    printf "folder_path=%s\n" "$folder_path"
    printf "file_name=%s\n" "$base"
    printf "file_size_bytes=%s\n" "$file_size_bytes"
    printf "file_mtime=%s\n" "$file_mtime"
    printf "file_hash=%s\n" "$file_hash"
  } > "$meta"
}
