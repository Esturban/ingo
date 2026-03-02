#!/usr/bin/env bash

set -euo pipefail

ingo_extract_html_fallback() {
  local input_file="$1"
  local output_file="$2"
  sed -E 's/<[^>]+>/ /g' "$input_file" | tr -s '[:space:]' ' ' > "$output_file"
}

ingo_extract_docx_fallback() {
  local input_file="$1"
  local output_file="$2"
  if command -v docx2txt >/dev/null 2>&1; then
    docx2txt "$input_file" - | tr -d '\r' > "$output_file"
    return 0
  fi
  return 1
}

ingo_extract_spreadsheet_with_python() {
  local input_file="$1"
  local output_file="$2"

  if ! command -v python3 >/dev/null 2>&1; then
    return 1
  fi

  if ! python3 - "$input_file" "$output_file" <<'PY'
import sys
from pathlib import Path

input_path = Path(sys.argv[1])
output_path = Path(sys.argv[2])

try:
    import openpyxl
except Exception:
    raise SystemExit(1)

try:
    wb = openpyxl.load_workbook(input_path, data_only=True, read_only=True)
except Exception:
    raise SystemExit(1)

with output_path.open("w", encoding="utf-8") as f:
    for sheet in wb.worksheets:
        f.write(f"## SHEET: {sheet.title}\n")
        for row in sheet.iter_rows(values_only=True):
            vals = []
            for cell in row:
                if cell is None:
                    vals.append("")
                else:
                    vals.append(str(cell).replace("\t", " ").replace("\n", " "))
            if any(v.strip() for v in vals):
                f.write("\t".join(vals).rstrip() + "\n")
        f.write("\n")
PY
  then
    return 1
  fi

  [ -s "$output_file" ] || return 1
}

ingo_extract_spreadsheet_with_cli() {
  local input_file="$1"
  local output_file="$2"

  if command -v xlsx2csv >/dev/null 2>&1; then
    if xlsx2csv "$input_file" "$output_file" >/dev/null 2>&1; then
      [ -s "$output_file" ] && return 0
    fi
    if xlsx2csv "$input_file" > "$output_file" 2>/dev/null; then
      [ -s "$output_file" ] && return 0
    fi
  fi

  if command -v in2csv >/dev/null 2>&1; then
    if in2csv "$input_file" > "$output_file" 2>/dev/null; then
      [ -s "$output_file" ] && return 0
    fi
  fi

  return 1
}

ingo_extract_file_text() {
  local input_file="$1"
  local file_ext="$2"
  local output_file="$3"

  case "$file_ext" in
    pdf)
      if command -v pdftotext >/dev/null 2>&1; then
        pdftotext -layout "$input_file" "$output_file" >/dev/null 2>&1 || return 1
      else
        return 1
      fi
      ;;
    docx)
      if command -v pandoc >/dev/null 2>&1; then
        pandoc "$input_file" -t plain -o "$output_file" >/dev/null 2>&1 || return 1
      elif ! ingo_extract_docx_fallback "$input_file" "$output_file"; then
        return 1
      fi
      ;;
    html|htm)
      if command -v pandoc >/dev/null 2>&1; then
        pandoc "$input_file" -t plain -o "$output_file" >/dev/null 2>&1 || ingo_extract_html_fallback "$input_file" "$output_file"
      else
        ingo_extract_html_fallback "$input_file" "$output_file"
      fi
      ;;
    xlsx|xlsm)
      if ! ingo_extract_spreadsheet_with_cli "$input_file" "$output_file"; then
        ingo_extract_spreadsheet_with_python "$input_file" "$output_file" || return 10
      fi
      ;;
    *)
      return 10
      ;;
  esac

  [ -s "$output_file" ] || return 1
}

ingo_extract_write_meta_from_manifest_line() {
  local manifest_line="$1"
  local meta_file="$2"
  local file_path folder_path file_name file_size_bytes file_hash
  local doc_id source_url canonical_url content_sha256 issuer category sector norm_type norm_number norm_year tags

  file_path="$(printf "%s" "$manifest_line" | jq -r '.local_path // ""')"
  folder_path="$(dirname "$file_path")"
  file_name="$(basename "$file_path")"
  file_size_bytes="$(printf "%s" "$manifest_line" | jq -r '.bytes // 0')"
  file_hash="$(printf "%s" "$manifest_line" | jq -r '.content_sha256 // ""')"
  doc_id="$(printf "%s" "$manifest_line" | jq -r '.doc_id // ""')"
  source_url="$(printf "%s" "$manifest_line" | jq -r '.source_url // ""')"
  canonical_url="$(printf "%s" "$manifest_line" | jq -r '.final_url // .source_url // ""')"
  content_sha256="$file_hash"
  issuer="$(printf "%s" "$manifest_line" | jq -r '.issuer // ""')"
  category="$(printf "%s" "$manifest_line" | jq -r '.category // ""')"
  sector="$(printf "%s" "$manifest_line" | jq -r '.sector // ""')"
  norm_type="$(printf "%s" "$manifest_line" | jq -r '.norm_type // ""')"
  norm_number="$(printf "%s" "$manifest_line" | jq -r '.norm_number // ""')"
  norm_year="$(printf "%s" "$manifest_line" | jq -r '.norm_year // ""')"
  tags="$(printf "%s" "$manifest_line" | jq -r '(.tags // []) | join(",")')"

  {
    printf "file_path=%s\n" "$file_path"
    printf "folder_path=%s\n" "$folder_path"
    printf "file_name=%s\n" "$file_name"
    printf "file_size_bytes=%s\n" "$file_size_bytes"
    printf "file_mtime=0\n"
    printf "file_hash=%s\n" "$file_hash"
    printf "doc_id=%s\n" "$doc_id"
    printf "source_url=%s\n" "$source_url"
    printf "canonical_url=%s\n" "$canonical_url"
    printf "content_sha256=%s\n" "$content_sha256"
    printf "issuer=%s\n" "$issuer"
    printf "category=%s\n" "$category"
    printf "sector=%s\n" "$sector"
    printf "norm_type=%s\n" "$norm_type"
    printf "norm_number=%s\n" "$norm_number"
    printf "norm_year=%s\n" "$norm_year"
    printf "tags=%s\n" "$tags"
  } > "$meta_file"
}

ingo_extract_manifest_documents() {
  local manifest_file="$1"
  local extracted_dir="$2"
  local doc_ids_file="${3:-}"
  local extracted_count=0 unsupported_count=0 failed_count=0
  local line doc_id local_path file_ext abs_input out_file rel_text_path meta_file
  local processed_count=0 total_count=0 progress_every verbose

  mkdir -p "$extracted_dir"
  [ -s "$manifest_file" ] || { printf "extracted=0 unsupported=0 failed=0\n"; return 0; }
  progress_every="${INGO_PROGRESS_EVERY:-25}"
  verbose="${INGO_CRAWL_VERBOSE:-0}"
  total_count="$(jq -r 'select((.status // "") == "downloaded") | .doc_id' "$manifest_file" 2>/dev/null | wc -l | tr -d ' ')"
  echo "extract-start: candidates=$total_count" >&2

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    if [ "$(printf "%s" "$line" | jq -r '.status // ""')" != "downloaded" ]; then
      continue
    fi

    doc_id="$(printf "%s" "$line" | jq -r '.doc_id // ""')"
    local_path="$(printf "%s" "$line" | jq -r '.local_path // ""')"
    file_ext="$(printf "%s" "$line" | jq -r '.file_ext // ""' | tr '[:upper:]' '[:lower:]')"
    [ -n "$doc_id" ] || continue
    [ -n "$local_path" ] || continue
    if [ -n "$doc_ids_file" ] && [ -s "$doc_ids_file" ]; then
      if ! grep -Fqx "$doc_id" "$doc_ids_file"; then
        continue
      fi
    fi
    processed_count=$((processed_count + 1))
    if [ "$verbose" = "1" ]; then
      echo "extract-doc: doc_id=$doc_id ext=$file_ext path=$local_path"
    fi
    if [ "$processed_count" -eq 1 ] || [ $((processed_count % progress_every)) -eq 0 ]; then
      echo "extract-progress: processed=$processed_count/$total_count extracted=$extracted_count unsupported=$unsupported_count failed=$failed_count" >&2
    fi

    if [[ "$local_path" = /* ]]; then
      abs_input="$local_path"
    else
      abs_input="$ROOT_DIR/$local_path"
    fi

    if [ ! -f "$abs_input" ]; then
      failed_count=$((failed_count + 1))
      ingo_manifest_update_doc "$manifest_file" "$doc_id" '{"status":"failed","error":"missing_local_file"}'
      continue
    fi

    out_file="$extracted_dir/${doc_id#sha256:}.txt"
    meta_file="${out_file%.txt}.meta"
    if ingo_extract_file_text "$abs_input" "$file_ext" "$out_file"; then
      rel_text_path="${out_file#"$ROOT_DIR"/}"
      extracted_count=$((extracted_count + 1))
      ingo_extract_write_meta_from_manifest_line "$line" "$meta_file"
      ingo_manifest_update_doc "$manifest_file" "$doc_id" "$(jq -cn --arg text_path "$rel_text_path" '{status:"extracted", text_path:$text_path}')"
    else
      case "$?" in
        10)
          unsupported_count=$((unsupported_count + 1))
          ingo_manifest_update_doc "$manifest_file" "$doc_id" '{"status":"unsupported"}'
          rm -f "$out_file"
          ;;
        *)
          failed_count=$((failed_count + 1))
          ingo_manifest_update_doc "$manifest_file" "$doc_id" '{"status":"failed","error":"extract_failed"}'
          rm -f "$out_file"
          ;;
      esac
    fi
  done < "$manifest_file"

  printf "extracted=%s unsupported=%s failed=%s\n" "$extracted_count" "$unsupported_count" "$failed_count"
}
