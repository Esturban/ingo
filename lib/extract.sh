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
    *)
      return 10
      ;;
  esac

  [ -s "$output_file" ] || return 1
}

ingo_extract_manifest_documents() {
  local manifest_file="$1"
  local extracted_dir="$2"
  local extracted_count=0 unsupported_count=0 failed_count=0
  local line doc_id local_path file_ext abs_input out_file rel_text_path

  mkdir -p "$extracted_dir"
  [ -s "$manifest_file" ] || { printf "extracted=0 unsupported=0 failed=0\n"; return 0; }

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
    if ingo_extract_file_text "$abs_input" "$file_ext" "$out_file"; then
      rel_text_path="${out_file#"$ROOT_DIR"/}"
      extracted_count=$((extracted_count + 1))
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
