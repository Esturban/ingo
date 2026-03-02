#!/usr/bin/env bash

set -euo pipefail

ingo_crawl_trim_fragment() {
  local url="$1"
  printf "%s\n" "${url%%#*}"
}

ingo_crawl_resolve_path() {
  local path="$1"
  local part
  local -a stack=()
  local out

  path="${path//\/\//\/}"
  IFS='/' read -r -a parts <<< "$path"
  for part in "${parts[@]}"; do
    case "$part" in
      ""|".") continue ;;
      "..")
        if [ "${#stack[@]}" -gt 0 ]; then
          unset 'stack[${#stack[@]}-1]'
        fi
        ;;
      *) stack+=("$part") ;;
    esac
  done

  if [ "${#stack[@]}" -eq 0 ]; then
    printf "/\n"
    return 0
  fi
  out="/$(IFS='/'; printf "%s" "${stack[*]}")"
  printf "%s\n" "$out"
}

ingo_crawl_extract_scheme_host() {
  local url="$1"
  if [[ "$url" =~ ^(https?)://([^/]+) ]]; then
    printf "%s\t%s\n" "${BASH_REMATCH[1]}" "$(printf "%s" "${BASH_REMATCH[2]}" | tr '[:upper:]' '[:lower:]')"
    return 0
  fi
  return 1
}

ingo_crawl_host_allowed() {
  local host="$1"
  local allow_file="${2:-}"
  local line

  case "$host" in
    *.gov.co|gov.co) return 0 ;;
  esac

  [ -f "$allow_file" ] || return 1
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(printf "%s" "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    if [ "$line" = "$host" ]; then
      return 0
    fi
  done < "$allow_file"
  return 1
}

ingo_crawl_normalize_url() {
  local base_url="$1"
  local raw_url="$2"
  local parsed scheme host root path base_dir query path_only combined

  raw_url="$(ingo_crawl_trim_fragment "$raw_url")"
  [ -n "$raw_url" ] || return 1

  if [[ "$raw_url" =~ ^https?:// ]]; then
    parsed="$(ingo_crawl_extract_scheme_host "$raw_url" || true)"
    [ -n "$parsed" ] || return 1
    scheme="${parsed%%$'\t'*}"
    host="${parsed#*$'\t'}"
    root="$scheme://$host"
    combined="${raw_url#"$root"}"
    [ -n "$combined" ] || combined="/"
    if [[ "$combined" == *\?* ]]; then
      query="?${combined#*\?}"
      path_only="${combined%%\?*}"
    else
      query=""
      path_only="$combined"
    fi
    path_only="$(ingo_crawl_resolve_path "$path_only")"
    printf "%s%s%s\n" "$root" "$path_only" "$query"
    return 0
  fi

  if ! parsed="$(ingo_crawl_extract_scheme_host "$base_url")"; then
    return 1
  fi
  scheme="${parsed%%$'\t'*}"
  host="${parsed#*$'\t'}"
  root="$scheme://$host"

  if [[ "$raw_url" =~ ^// ]]; then
    printf "%s:%s\n" "$scheme" "$(printf "%s" "$raw_url" | tr '[:upper:]' '[:lower:]')"
    return 0
  fi
  if [[ "$raw_url" =~ ^/ ]]; then
    if [[ "$raw_url" == *\?* ]]; then
      query="?${raw_url#*\?}"
      path_only="${raw_url%%\?*}"
    else
      query=""
      path_only="$raw_url"
    fi
    path_only="$(ingo_crawl_resolve_path "$path_only")"
    printf "%s%s%s\n" "$root" "$path_only" "$query"
    return 0
  fi
  if [[ "$raw_url" =~ ^mailto:|^javascript:|^data: ]]; then
    return 1
  fi

  path="${base_url#"$root"}"
  if [ "$path" = "$base_url" ]; then
    return 1
  fi
  base_dir="${path%/*}"
  [ -n "$base_dir" ] || base_dir="/"
  combined="$root${base_dir%/}/$raw_url"
  if [[ "$combined" == *\?* ]]; then
    query="?${combined#*\?}"
    path_only="${combined%%\?*}"
  else
    query=""
    path_only="$combined"
  fi
  path_only="${path_only#"$root"}"
  path_only="$(ingo_crawl_resolve_path "$path_only")"
  printf "%s%s%s\n" "$root" "$path_only" "$query"
}

ingo_crawl_extract_links() {
  local html_file="$1"
  (grep -Eoi '(href|src)=["'\''][^"'\'']+["'\'']' "$html_file" || true) \
    | sed -E 's/^(href|src)=["'\'']([^"'\'']+)["'\'']$/\2/' \
    | awk 'NF' \
    | sort -u
}

ingo_crawl_fetch_page() {
  local url="$1"
  local out_file="$2"
  ingo_http_curl -fsSL "$url" -o "$out_file"
}

ingo_crawl_discover_urls() {
  local seeds_file="$1"
  local max_depth="$2"
  local allow_hosts_file="$3"
  local out_urls_file="$4"
  local work_dir="$5"
  local queue_file visited_file pages_dir
  local line depth url parent parsed host page_file next_depth candidate raw

  queue_file="$work_dir/queue.tsv"
  visited_file="$work_dir/visited.txt"
  pages_dir="$work_dir/pages"
  mkdir -p "$work_dir" "$pages_dir"
  : > "$queue_file"
  : > "$visited_file"
  : > "$out_urls_file"

  while IFS= read -r raw; do
    raw="${raw%%#*}"
    raw="$(printf "%s" "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$raw" ] || continue
    printf "0\t%s\t\n" "$raw" >> "$queue_file"
  done < "$seeds_file"

  while IFS=$'\t' read -r depth url parent; do
    [ -n "$url" ] || continue
    if grep -Fqx "$url" "$visited_file"; then
      continue
    fi
    printf "%s\n" "$url" >> "$visited_file"
    printf "%s\n" "$url" >> "$out_urls_file"

    if [ "$depth" -ge "$max_depth" ]; then
      continue
    fi

    parsed="$(ingo_crawl_extract_scheme_host "$url" || true)"
    [ -n "$parsed" ] || continue
    host="${parsed#*$'\t'}"
    if ! ingo_crawl_host_allowed "$host" "$allow_hosts_file"; then
      continue
    fi

    page_file="$pages_dir/page-$(printf "%s" "$url" | shasum -a 256 | awk '{print $1}').html"
    if ! ingo_crawl_fetch_page "$url" "$page_file" >/dev/null 2>&1; then
      continue
    fi

    next_depth=$((depth + 1))
    while IFS= read -r raw; do
      candidate="$(ingo_crawl_normalize_url "$url" "$raw" || true)"
      [ -n "$candidate" ] || continue
      if grep -Fqx "$candidate" "$visited_file"; then
        continue
      fi
      printf "%s\t%s\t%s\n" "$next_depth" "$candidate" "$url" >> "$queue_file"
    done < <(ingo_crawl_extract_links "$page_file")
  done < "$queue_file"

  local corpus_root manifest_file downloads_dir collect_summary
  corpus_root="$(cd "$work_dir/.." && pwd)"
  manifest_file="${INGO_MANIFEST_FILE:-$corpus_root/manifests/documents.ndjson}"
  local skipped_file errors_file
  skipped_file="${INGO_SKIPPED_FILE:-$corpus_root/manifests/gdb_skipped.ndjson}"
  errors_file="${INGO_ERRORS_FILE:-$corpus_root/manifests/gdb_errors.ndjson}"
  downloads_dir="${INGO_DOWNLOADS_DIR:-$corpus_root/downloads}"
  collect_summary="$(ingo_crawl_collect_documents "$out_urls_file" "$manifest_file" "$downloads_dir" "" "$skipped_file" "$errors_file")"
  printf "%s\n" "$collect_summary" > "$work_dir/collect-summary.txt"
}

ingo_crawl_url_host() {
  local parsed
  parsed="$(ingo_crawl_extract_scheme_host "$1" || true)"
  [ -n "$parsed" ] || { printf "\n"; return 0; }
  printf "%s\n" "${parsed#*$'\t'}"
}

ingo_crawl_download_file_name() {
  local url="$1"
  local path base
  path="${url%%\?*}"
  path="${path%%#*}"
  base="${path##*/}"
  [ -n "$base" ] || base="document"
  base="$(printf "%s" "$base" | tr -cd '[:alnum:]._-')"
  [ -n "$base" ] || base="document"
  printf "%s\n" "$base"
}

ingo_crawl_timestamp_utc() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

ingo_crawl_probe_url() {
  local url="$1"
  local out
  out="$(
    curl -sSIL -o /dev/null \
      --connect-timeout "${INGO_HTTP_CONNECT_TIMEOUT:-5}" \
      --max-time "${INGO_HTTP_READ_TIMEOUT:-30}" \
      -w '%{http_code}\t%{content_type}\t%{url_effective}' \
      "$url" 2>/dev/null || true
  )"
  [ -n "$out" ] || out=$'000\t\t'
  printf "%s\n" "$out"
}

ingo_crawl_mime_is_document() {
  local content_type
  content_type="$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')"
  case "$content_type" in
    application/pdf*|\
    application/vnd.openxmlformats-officedocument*|\
    application/vnd.ms-excel*|\
    application/msword*)
      return 0
      ;;
  esac
  return 1
}

ingo_crawl_ext_from_content_type() {
  local content_type
  content_type="$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')"
  case "$content_type" in
    application/pdf*) printf "pdf\n" ;;
    application/vnd.openxmlformats-officedocument.wordprocessingml.document*) printf "docx\n" ;;
    application/vnd.openxmlformats-officedocument.spreadsheetml.sheet*) printf "xlsx\n" ;;
    application/vnd.ms-excel*) printf "xlsx\n" ;;
    *) printf "\n" ;;
  esac
}

ingo_crawl_append_skipped() {
  local skipped_file="$1"
  local url="$2"
  local canonical_url="$3"
  local source_page="$4"
  local reason="$5"
  local file_ext="$6"
  local content_type="${7:-}"
  local ts
  ts="$(ingo_crawl_timestamp_utc)"
  ingo_manifest_append_record "$skipped_file" "$(jq -cn \
    --arg url "$url" \
    --arg canonical_url "$canonical_url" \
    --arg source_page "$source_page" \
    --arg reason "$reason" \
    --arg file_ext "$file_ext" \
    --arg content_type "$content_type" \
    --arg timestamp "$ts" \
    '{
      url: $url,
      canonical_url: $canonical_url,
      source_page: $source_page,
      reason: $reason,
      file_ext: $file_ext,
      content_type: $content_type,
      timestamp: $timestamp
    }')"
}

ingo_crawl_append_error() {
  local errors_file="$1"
  local url="$2"
  local canonical_url="$3"
  local source_page="$4"
  local http_status="$5"
  local error="$6"
  local ts
  ts="$(ingo_crawl_timestamp_utc)"
  ingo_manifest_append_record "$errors_file" "$(jq -cn \
    --arg url "$url" \
    --arg canonical_url "$canonical_url" \
    --arg source_page "$source_page" \
    --arg http_status "$http_status" \
    --arg error "$error" \
    --arg timestamp "$ts" \
    '{
      url: $url,
      canonical_url: $canonical_url,
      source_page: $source_page,
      http_status: (if $http_status == "" then 0 else ($http_status|tonumber) end),
      error: $error,
      timestamp: $timestamp
    }')"
}

ingo_crawl_collect_documents() {
  local urls_file="$1"
  local manifest_file="$2"
  local downloads_dir="$3"
  local discovered_from="${4:-}"
  local skipped_file="${5:-}"
  local errors_file="${6:-}"
  local url ext host out_name out_path fetched_at
  local content_sha doc_id duplicate_of mime_type bytes status local_path
  local probe_status probe_content_type probe
  local downloaded_count=0 duplicate_count=0 failed_count=0 skipped_count=0
  local canonical_doc_id

  mkdir -p "$downloads_dir"
  ingo_manifest_init "$manifest_file"
  [ -n "$skipped_file" ] && ingo_manifest_init "$skipped_file"
  [ -n "$errors_file" ] && ingo_manifest_init "$errors_file"

  while IFS= read -r url; do
    [ -n "$url" ] || continue
    if ingo_url_matches_deny_pattern "$url"; then
      skipped_count=$((skipped_count + 1))
      [ -n "$skipped_file" ] && ingo_crawl_append_skipped "$skipped_file" "$url" "$url" "$discovered_from" "deny_pattern" "$ext" ""
      continue
    fi

    ext="$(ingo_file_ext_from_url "$url")"
    if [ -n "$ext" ] && ingo_is_excluded_extension "$ext"; then
      skipped_count=$((skipped_count + 1))
      [ -n "$skipped_file" ] && ingo_crawl_append_skipped "$skipped_file" "$url" "$url" "$discovered_from" "excluded_extension" "$ext" ""
      continue
    fi
    if [ -z "$ext" ] || ! ingo_is_document_extension "$ext"; then
      probe="$(ingo_crawl_probe_url "$url")"
      probe_status="${probe%%$'\t'*}"
      probe_content_type="${probe#*$'\t'}"
      probe_content_type="${probe_content_type%%$'\t'*}"
      if [ -n "$probe_status" ] && [ "$probe_status" -ge 400 ]; then
        failed_count=$((failed_count + 1))
        [ -n "$errors_file" ] && ingo_crawl_append_error "$errors_file" "$url" "$url" "$discovered_from" "$probe_status" "http_error"
        continue
      fi
      if ! ingo_crawl_mime_is_document "$probe_content_type"; then
        skipped_count=$((skipped_count + 1))
        [ -n "$skipped_file" ] && ingo_crawl_append_skipped "$skipped_file" "$url" "$url" "$discovered_from" "not_document" "$ext" "$probe_content_type"
        continue
      fi
      ext="$(ingo_crawl_ext_from_content_type "$probe_content_type")"
      if [ -z "$ext" ]; then
        skipped_count=$((skipped_count + 1))
        [ -n "$skipped_file" ] && ingo_crawl_append_skipped "$skipped_file" "$url" "$url" "$discovered_from" "unknown_mime" "" "$probe_content_type"
        continue
      fi
    else
      probe="$(ingo_crawl_probe_url "$url")"
      probe_status="${probe%%$'\t'*}"
      probe_content_type="${probe#*$'\t'}"
      probe_content_type="${probe_content_type%%$'\t'*}"
      if [ -n "$probe_status" ] && [ "$probe_status" -ge 400 ]; then
        failed_count=$((failed_count + 1))
        [ -n "$errors_file" ] && ingo_crawl_append_error "$errors_file" "$url" "$url" "$discovered_from" "$probe_status" "http_error"
        continue
      fi
      if [ -n "$probe_content_type" ] && ! ingo_crawl_mime_is_document "$probe_content_type"; then
        skipped_count=$((skipped_count + 1))
        [ -n "$skipped_file" ] && ingo_crawl_append_skipped "$skipped_file" "$url" "$url" "$discovered_from" "mime_mismatch" "$ext" "$probe_content_type"
        continue
      fi
    fi

    host="$(ingo_crawl_url_host "$url")"
    out_name="$(ingo_crawl_download_file_name "$url")"
    out_path="$downloads_dir/$out_name"
    fetched_at="$(ingo_crawl_timestamp_utc)"

    if ! ingo_http_curl -fsSL "$url" -o "$out_path"; then
      failed_count=$((failed_count + 1))
      [ -n "$errors_file" ] && ingo_crawl_append_error "$errors_file" "$url" "$url" "$discovered_from" "0" "download_failed"
      rm -f "$out_path"
      continue
    fi

    content_sha="$(ingo_file_sha256 "$out_path")"
    bytes="$(ingo_file_size_bytes "$out_path")"
    mime_type="${probe_content_type:-application/octet-stream}"
    doc_id="sha256:$content_sha"
    canonical_doc_id="$(ingo_manifest_resolve_duplicate_doc_id "$manifest_file" "$content_sha" || true)"
    local_path="${out_path#"$ROOT_DIR"/}"

    if [ -n "$canonical_doc_id" ]; then
      duplicate_of="$canonical_doc_id"
      status="duplicate"
      duplicate_count=$((duplicate_count + 1))
      ingo_manifest_update_aliases "$manifest_file" "$canonical_doc_id" "$url" || true
      rm -f "$out_path"
    else
      duplicate_of=""
      status="downloaded"
      downloaded_count=$((downloaded_count + 1))
    fi

    ingo_manifest_append_record "$manifest_file" "$(jq -cn \
      --arg doc_id "$doc_id" \
      --arg status "$status" \
      --arg source_url "$url" \
      --arg discovered_from_url "$discovered_from" \
      --arg host "$host" \
      --arg mime_type "$mime_type" \
      --arg file_ext "$ext" \
      --arg local_path "$local_path" \
      --arg content_sha256 "$content_sha" \
      --arg bytes "$bytes" \
      --arg fetched_at "$fetched_at" \
      --arg last_seen_at "$fetched_at" \
      --arg duplicate_of "$duplicate_of" \
      '{
        doc_id: $doc_id,
        status: $status,
        source_url: $source_url,
        discovered_from_url: $discovered_from_url,
        host: $host,
        mime_type: $mime_type,
        file_ext: $file_ext,
        local_path: $local_path,
        content_sha256: $content_sha256,
        bytes: ($bytes|tonumber),
        fetched_at: $fetched_at,
        last_seen_at: $last_seen_at
      } + (if $duplicate_of != "" then {duplicate_of: $duplicate_of} else {} end)')"
  done < "$urls_file"

  printf "downloaded=%s duplicate=%s failed=%s skipped=%s\n" "$downloaded_count" "$duplicate_count" "$failed_count" "$skipped_count"
}
