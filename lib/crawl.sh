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
  local processed_count=0 queued_count=0 start_ts now elapsed progress_every verbose

  queue_file="$work_dir/queue.tsv"
  visited_file="$work_dir/visited.txt"
  pages_dir="$work_dir/pages"
  mkdir -p "$work_dir" "$pages_dir"
  : > "$queue_file"
  : > "$visited_file"
  : > "$out_urls_file"

  start_ts="$(date +%s)"
  progress_every="${INGO_PROGRESS_EVERY:-25}"
  verbose="${INGO_CRAWL_VERBOSE:-0}"

  while IFS= read -r raw; do
    raw="${raw%%#*}"
    raw="$(printf "%s" "$raw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$raw" ] || continue
    printf "0\t%s\t\n" "$raw" >> "$queue_file"
    queued_count=$((queued_count + 1))
  done < "$seeds_file"

  while IFS=$'\t' read -r depth url parent; do
    [ -n "$url" ] || continue
    processed_count=$((processed_count + 1))
    if [ "$verbose" = "1" ]; then
      echo "crawl-url: depth=$depth url=$url"
    fi
    if [ $((processed_count % progress_every)) -eq 0 ]; then
      now="$(date +%s)"
      elapsed=$((now - start_ts))
      echo "crawl-progress: processed=$processed_count queued=$queued_count elapsed=${elapsed}s"
    fi
    parsed="$(ingo_crawl_extract_scheme_host "$url" || true)"
    [ -n "$parsed" ] || continue
    host="${parsed#*$'\t'}"
    if ! ingo_crawl_host_allowed "$host" "$allow_hosts_file"; then
      continue
    fi

    if grep -Fqx "$url" "$visited_file"; then
      continue
    fi
    printf "%s\n" "$url" >> "$visited_file"
    printf "%s\n" "$url" >> "$out_urls_file"

    if [ "$depth" -ge "$max_depth" ]; then
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
      parsed="$(ingo_crawl_extract_scheme_host "$candidate" || true)"
      [ -n "$parsed" ] || continue
      host="${parsed#*$'\t'}"
      if ! ingo_crawl_host_allowed "$host" "$allow_hosts_file"; then
        continue
      fi
      if ingo_url_matches_deny_pattern "$candidate"; then
        continue
      fi
      local candidate_ext
      candidate_ext="$(ingo_file_ext_from_url "$candidate")"
      if [ -n "$candidate_ext" ] && ingo_is_excluded_extension "$candidate_ext"; then
        continue
      fi
      if [ -z "$candidate_ext" ] || ! ingo_is_document_extension "$candidate_ext"; then
        if ! ingo_url_is_allowed_page_candidate "$candidate"; then
          continue
        fi
      fi
      if grep -Fqx "$candidate" "$visited_file"; then
        continue
      fi
      printf "%s\t%s\t%s\n" "$next_depth" "$candidate" "$url" >> "$queue_file"
      queued_count=$((queued_count + 1))
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

ingo_crawl_build_stable_doc_name() {
  local original_name="$1"
  local content_sha="$2"
  local base ext short
  base="$original_name"
  ext=""
  if [[ "$original_name" == *.* ]]; then
    ext=".${original_name##*.}"
    base="${original_name%.*}"
  fi
  short="$(printf "%s" "$content_sha" | cut -c1-10)"
  printf "%s-%s%s\n" "$base" "$short" "$ext"
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
  local url ext host out_name out_path tmp_out fetched_at stable_name
  local content_sha doc_id duplicate_of mime_type bytes status local_path final_url
  local probe_status probe_content_type probe_final_url probe
  local downloaded_count=0 duplicate_count=0 failed_count=0 skipped_count=0
  local canonical_doc_id

  mkdir -p "$downloads_dir"
  ingo_manifest_init "$manifest_file"
  [ -n "$skipped_file" ] && ingo_manifest_init "$skipped_file"
  [ -n "$errors_file" ] && ingo_manifest_init "$errors_file"

  while IFS= read -r url; do
    [ -n "$url" ] || continue
    ext=""
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
      probe_final_url="${probe##*$'\t'}"
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
      probe_final_url="${probe##*$'\t'}"
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
    tmp_out="$(mktemp "$downloads_dir/.tmp-download.XXXXXX")"
    fetched_at="$(ingo_crawl_timestamp_utc)"

    if ! ingo_http_curl -fsSL "$url" -o "$tmp_out"; then
      failed_count=$((failed_count + 1))
      [ -n "$errors_file" ] && ingo_crawl_append_error "$errors_file" "$url" "$url" "$discovered_from" "0" "download_failed"
      rm -f "$tmp_out"
      continue
    fi

    content_sha="$(ingo_file_sha256 "$tmp_out")"
    bytes="$(ingo_file_size_bytes "$tmp_out")"
    mime_type="${probe_content_type:-application/octet-stream}"
    final_url="${probe_final_url:-$url}"
    doc_id="sha256:$content_sha"
    canonical_doc_id="$(ingo_manifest_resolve_duplicate_doc_id "$manifest_file" "$content_sha" || true)"
    stable_name="$(ingo_crawl_build_stable_doc_name "$out_name" "$content_sha")"
    out_path="$downloads_dir/$stable_name"
    local_path="${out_path#"$ROOT_DIR"/}"

    if [ -n "$canonical_doc_id" ]; then
      duplicate_of="$canonical_doc_id"
      status="duplicate"
      duplicate_count=$((duplicate_count + 1))
      ingo_manifest_update_aliases "$manifest_file" "$canonical_doc_id" "$url" || true
      rm -f "$tmp_out"
    else
      duplicate_of=""
      status="downloaded"
      downloaded_count=$((downloaded_count + 1))
      mv -f "$tmp_out" "$out_path"
    fi

    ingo_manifest_append_doc_record \
      "$manifest_file" \
      "$doc_id" \
      "$status" \
      "$url" \
      "$final_url" \
      "$discovered_from" \
      "$host" \
      "$mime_type" \
      "$ext" \
      "$local_path" \
      "$content_sha" \
      "$bytes" \
      "$fetched_at" \
      "$fetched_at" \
      "$duplicate_of"
  done < "$urls_file"

  printf "downloaded=%s duplicate=%s failed=%s skipped=%s\n" "$downloaded_count" "$duplicate_count" "$failed_count" "$skipped_count"
}
