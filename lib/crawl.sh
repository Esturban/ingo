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

ingo_crawl_prefer_https() {
  local url="$1"
  if [[ "$url" =~ ^http:// ]] && [ "${INGO_CRAWL_ALLOW_HTTP:-0}" != "1" ]; then
    printf "%s\n" "https://${url#http://}"
    return 0
  fi
  printf "%s\n" "$url"
}

ingo_crawl_decode_entities() {
  local value="$1"
  value="${value//&amp;/&}"
  value="${value//&#38;/&}"
  printf "%s\n" "$value"
}

ingo_crawl_sanitize_url() {
  local url="$1"
  url="$(printf "%s" "$url" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
  url="$(ingo_crawl_decode_entities "$url")"
  printf "%s\n" "$url"
}

ingo_crawl_is_malformed_url() {
  local url="$1"
  url="$(ingo_crawl_sanitize_url "$url")"
  [[ "$url" =~ ^https?:// ]] || return 0
  [[ "$url" =~ [[:space:]] ]] && return 0
  [[ "$url" == *"|"* ]] && return 0
  if printf "%s" "$url" | grep -Eq '%($|[^0-9A-Fa-f]|.[^0-9A-Fa-f])'; then
    return 0
  fi
  [[ "$url" =~ ^https?://[^/?#]+ ]] || return 0
  return 1
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
  local line rule

  [ -f "$allow_file" ] || return 1
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(printf "%s" "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$line" ] || continue
    rule="$(printf "%s" "$line" | tr '[:upper:]' '[:lower:]')"
    case "$rule" in
      \**)
        rule="${rule#\*}"
        ;;
    esac
    if [ "$rule" = "$host" ] || [[ "$host" == *".${rule#.}" ]]; then
      return 0
    fi
  done < "$allow_file"
  return 1
}

ingo_crawl_build_allow_hosts_file() {
  local seeds_file="$1"
  local allow_hosts_file="$2"
  local out_file="$3"
  local raw parsed host line

  : > "$out_file"

  while IFS= read -r raw; do
    raw="${raw%%#*}"
    raw="$(ingo_crawl_sanitize_url "$raw")"
    [ -n "$raw" ] || continue
    raw="$(ingo_crawl_prefer_https "$raw")"
    parsed="$(ingo_crawl_extract_scheme_host "$raw" || true)"
    [ -n "$parsed" ] || continue
    host="${parsed#*$'\t'}"
    [ -n "$host" ] || continue
    printf "%s\n" "$host" >> "$out_file"
  done < "$seeds_file"

  if [ -f "$allow_hosts_file" ]; then
    while IFS= read -r line; do
      line="${line%%#*}"
      line="$(printf "%s" "$line" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
      [ -n "$line" ] || continue
      printf "%s\n" "$line" >> "$out_file"
    done < "$allow_hosts_file"
  fi

  sort -u "$out_file" -o "$out_file"
}

ingo_crawl_normalize_url() {
  local base_url="$1"
  local raw_url="$2"
  local parsed scheme host root path base_dir query path_only combined

  raw_url="$(ingo_crawl_trim_fragment "$raw_url")"
  raw_url="$(ingo_crawl_sanitize_url "$raw_url")"
  [ -n "$raw_url" ] || return 1

  if [[ "$raw_url" =~ ^https?:// ]]; then
    raw_url="$(ingo_crawl_prefer_https "$raw_url")"
    if ingo_crawl_is_malformed_url "$raw_url"; then
      return 1
    fi
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

ingo_crawl_snapshot_page_pdf() {
  local url="$1"
  local out_file="$2"
  if ! command -v wkhtmltopdf >/dev/null 2>&1; then
    return 127
  fi
  wkhtmltopdf -q "$url" "$out_file" >/dev/null 2>&1
}

ingo_crawl_discover_urls() {
  local seeds_file="$1"
  local max_depth="$2"
  local allow_hosts_file="$3"
  local out_urls_file="$4"
  local work_dir="$5"
  local queue_file visited_file queued_file pages_dir
  local -A visited_set=()
  local -A queued_set=()
  local line depth url parent parsed host page_file next_depth candidate raw
  local candidate_ext page_doc_candidates snapshot_tmp
  local processed_count=0 queued_count=0 start_ts now elapsed progress_every verbose

  queue_file="$work_dir/queue.tsv"
  visited_file="$work_dir/visited.txt"
  queued_file="$work_dir/queued.txt"
  pages_dir="$work_dir/pages"
  mkdir -p "$work_dir" "$pages_dir"
  : > "$queue_file"
  : > "$visited_file"
  : > "$queued_file"
  : > "$out_urls_file"

  start_ts="$(date +%s)"
  progress_every="${INGO_PROGRESS_EVERY:-25}"
  verbose="${INGO_CRAWL_VERBOSE:-0}"

  while IFS= read -r raw; do
    raw="${raw%%#*}"
    raw="$(ingo_crawl_sanitize_url "$raw")"
    [ -n "$raw" ] || continue
    raw="$(ingo_crawl_prefer_https "$raw")"
    if ingo_crawl_is_malformed_url "$raw"; then
      continue
    fi
    if [ "${queued_set["$raw"]+yes}" = "yes" ]; then
      continue
    fi
    queued_set["$raw"]=1
    printf "0\t%s\t\n" "$raw" >> "$queue_file"
    printf "%s\n" "$raw" >> "$queued_file"
    queued_count=$((queued_count + 1))
  done < "$seeds_file"
  echo "crawl-start: queued=$queued_count depth=$max_depth" >&2

  while IFS=$'\t' read -r depth url parent; do
    [ -n "$url" ] || continue
    url="$(ingo_crawl_sanitize_url "$url")"
    if ingo_crawl_is_malformed_url "$url"; then
      continue
    fi
    url="$(ingo_crawl_prefer_https "$url")"
    processed_count=$((processed_count + 1))
    if [ "$verbose" = "1" ]; then
      echo "crawl-url: depth=$depth url=$url"
    fi
    if [ "$processed_count" -eq 1 ] || [ $((processed_count % progress_every)) -eq 0 ]; then
      now="$(date +%s)"
      elapsed=$((now - start_ts))
      echo "crawl-progress: processed=$processed_count queued=$queued_count elapsed=${elapsed}s" >&2
    fi
    parsed="$(ingo_crawl_extract_scheme_host "$url" || true)"
    [ -n "$parsed" ] || continue
    host="${parsed#*$'\t'}"
    if ! ingo_crawl_host_allowed "$host" "$allow_hosts_file"; then
      continue
    fi

    if [ "${visited_set["$url"]+yes}" = "yes" ]; then
      continue
    fi
    visited_set["$url"]=1
    printf "%s\n" "$url" >> "$visited_file"
    printf "%s\n" "$url" >> "$out_urls_file"

    if [ "$depth" -ge "$max_depth" ]; then
      continue
    fi

    if ingo_url_is_document_candidate "$url"; then
      continue
    fi

    page_file="$pages_dir/page-$(printf "%s" "$url" | shasum -a 256 | awk '{print $1}').html"
    if ! ingo_crawl_fetch_page "$url" "$page_file" >/dev/null 2>&1; then
      continue
    fi

    next_depth=$((depth + 1))
    page_doc_candidates=0
    while IFS= read -r raw; do
      candidate="$(ingo_crawl_normalize_url "$url" "$raw" || true)"
      [ -n "$candidate" ] || continue
      candidate="$(ingo_crawl_sanitize_url "$candidate")"
      if ingo_crawl_is_malformed_url "$candidate"; then
        continue
      fi
      parsed="$(ingo_crawl_extract_scheme_host "$candidate" || true)"
      [ -n "$parsed" ] || continue
      host="${parsed#*$'\t'}"
      if ! ingo_crawl_host_allowed "$host" "$allow_hosts_file"; then
        continue
      fi
      if ingo_url_matches_deny_pattern "$candidate"; then
        continue
      fi
      candidate_ext="$(ingo_file_ext_from_url "$candidate")"
      if [ -n "$candidate_ext" ] && ingo_is_excluded_extension "$candidate_ext"; then
        continue
      fi
      if [ -n "$candidate_ext" ] && ingo_is_document_extension "$candidate_ext"; then
        page_doc_candidates=$((page_doc_candidates + 1))
      fi
      if [ "${visited_set["$candidate"]+yes}" = "yes" ]; then
        continue
      fi
      if [ "${queued_set["$candidate"]+yes}" = "yes" ]; then
        continue
      fi
      queued_set["$candidate"]=1
      printf "%s\t%s\t%s\n" "$next_depth" "$candidate" "$url" >> "$queue_file"
      printf "%s\n" "$candidate" >> "$queued_file"
      queued_count=$((queued_count + 1))
    done < <(ingo_crawl_extract_links "$page_file")

    if [ "${INGO_SNAPSHOT_PAGES_TO_PDF:-0}" = "1" ] && [ "$page_doc_candidates" -eq 0 ]; then
      snapshot_tmp="$(mktemp "${INGO_DOWNLOADS_DIR:-$work_dir}/.tmp-snapshot.XXXXXX.pdf")"
      if ingo_crawl_snapshot_page_pdf "$url" "$snapshot_tmp"; then
        printf "%s\n" "$snapshot_tmp|$url" >> "$work_dir/snapshots.list"
      else
        rm -f "$snapshot_tmp"
      fi
    fi
  done < "$queue_file"

  local corpus_root manifest_file downloads_dir collect_summary
  corpus_root="$(cd "$work_dir/.." && pwd)"
  manifest_file="${INGO_MANIFEST_FILE:-$corpus_root/manifests/documents.ndjson}"
  local skipped_file errors_file
  skipped_file="${INGO_SKIPPED_FILE:-$corpus_root/manifests/gdb_skipped.ndjson}"
  errors_file="${INGO_ERRORS_FILE:-$corpus_root/manifests/gdb_errors.ndjson}"
  downloads_dir="${INGO_DOWNLOADS_DIR:-$corpus_root/downloads}"
  collect_summary="$(ingo_crawl_collect_documents "$out_urls_file" "$manifest_file" "$downloads_dir" "" "$skipped_file" "$errors_file")"
  if [ -s "$work_dir/snapshots.list" ]; then
    while IFS='|' read -r snapshot_path source_url; do
      [ -n "$snapshot_path" ] || continue
      [ -f "$snapshot_path" ] || continue
      content_sha="$(ingo_file_sha256 "$snapshot_path")"
      bytes="$(ingo_file_size_bytes "$snapshot_path")"
      doc_id="sha256:$content_sha"
      canonical_doc_id="$(ingo_manifest_resolve_duplicate_doc_id "$manifest_file" "$content_sha" || true)"
      out_name="$(basename "$source_url" | sed 's/[^[:alnum:]_.-]/_/g')"
      [ -n "$out_name" ] || out_name="page"
      stable_name="$(ingo_crawl_build_stable_doc_name "$out_name.pdf" "$content_sha")"
      out_path="$downloads_dir/$stable_name"
      if [ -n "$canonical_doc_id" ]; then
        rm -f "$snapshot_path"
        ingo_manifest_append_doc_record \
          "$manifest_file" \
          "$doc_id" \
          "duplicate" \
          "$source_url" \
          "$source_url" \
          "$source_url" \
          "$(ingo_crawl_url_host "$source_url")" \
          "application/pdf" \
          "pdf" \
          "" \
          "$content_sha" \
          "$bytes" \
          "$(ingo_crawl_timestamp_utc)" \
          "$(ingo_crawl_timestamp_utc)" \
          "$canonical_doc_id"
      else
        mv -f "$snapshot_path" "$out_path"
        ingo_manifest_append_doc_record \
          "$manifest_file" \
          "$doc_id" \
          "downloaded" \
          "$source_url" \
          "$source_url" \
          "$source_url" \
          "$(ingo_crawl_url_host "$source_url")" \
          "application/pdf" \
          "pdf" \
          "${out_path#"$ROOT_DIR"/}" \
          "$content_sha" \
          "$bytes" \
          "$(ingo_crawl_timestamp_utc)" \
          "$(ingo_crawl_timestamp_utc)" \
          ""
      fi
    done < "$work_dir/snapshots.list"
  fi
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
    curl --http1.1 -sSIL -o /dev/null \
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
    application/octet-stream*|\
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
  local content_sha doc_id duplicate_of mime_type bytes status local_path final_url doc_id_suffix
  local probe_status probe_content_type probe_final_url probe
  local downloaded_count=0 duplicate_count=0 failed_count=0 skipped_count=0
  local processed_count=0 total_count=0 progress_every verbose
  local canonical_doc_id
  local run_doc_ids_file="${INGO_NEW_DOC_IDS_FILE:-}"
  local existing_path existing_abs_path download_timeout
  local canonical_path canonical_abs_path

  mkdir -p "$downloads_dir"
  ingo_manifest_init "$manifest_file"
  [ -n "$skipped_file" ] && ingo_manifest_init "$skipped_file"
  [ -n "$errors_file" ] && ingo_manifest_init "$errors_file"
  if [ -n "$run_doc_ids_file" ]; then
    mkdir -p "$(dirname "$run_doc_ids_file")"
    : > "$run_doc_ids_file"
  fi
  progress_every="${INGO_PROGRESS_EVERY:-25}"
  verbose="${INGO_CRAWL_VERBOSE:-0}"
  total_count="$(wc -l < "$urls_file" | tr -d ' ')"
  download_timeout="${INGO_HTTP_DOWNLOAD_TIMEOUT:-${INGO_HTTP_READ_TIMEOUT:-30}}"
  echo "collect-start: total_urls=$total_count" >&2

  while IFS= read -r url; do
    [ -n "$url" ] || continue
    processed_count=$((processed_count + 1))
    if [ "$verbose" = "1" ]; then
      echo "collect-url: $url"
    fi
    if [ "$processed_count" -eq 1 ] || [ $((processed_count % progress_every)) -eq 0 ]; then
      echo "collect-progress: processed=$processed_count/$total_count downloaded=$downloaded_count duplicate=$duplicate_count failed=$failed_count skipped=$skipped_count" >&2
    fi
    url="$(ingo_crawl_sanitize_url "$url")"
    if ingo_crawl_is_malformed_url "$url"; then
      skipped_count=$((skipped_count + 1))
      [ -n "$skipped_file" ] && ingo_crawl_append_skipped "$skipped_file" "$url" "$url" "$discovered_from" "malformed_url" "" ""
      continue
    fi
    if ingo_manifest_has_url "$manifest_file" "$url"; then
      existing_path="$(ingo_manifest_find_local_path_by_url "$manifest_file" "$url" || true)"
      if [ -n "$existing_path" ]; then
        if [[ "$existing_path" = /* ]]; then
          existing_abs_path="$existing_path"
        else
          existing_abs_path="$ROOT_DIR/$existing_path"
        fi
        if [ -f "$existing_abs_path" ]; then
          skipped_count=$((skipped_count + 1))
          [ -n "$skipped_file" ] && ingo_crawl_append_skipped "$skipped_file" "$url" "$url" "$discovered_from" "already_seen_url" "" ""
          continue
        fi
      fi
    fi
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

    if ! INGO_HTTP_READ_TIMEOUT="$download_timeout" ingo_http_curl -fsSL "$url" -o "$tmp_out"; then
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
      doc_id_suffix="$(printf "%s" "$url" | shasum -a 256 | awk '{print $1}' | cut -c1-10)"
      doc_id="${doc_id}:dup-${doc_id_suffix}"
      duplicate_of="$canonical_doc_id"
      status="duplicate"
      duplicate_count=$((duplicate_count + 1))
      ingo_manifest_update_aliases "$manifest_file" "$canonical_doc_id" "$url" || true
      canonical_path="$(ingo_manifest_find_local_path_by_doc_id "$manifest_file" "$canonical_doc_id" || true)"
      if [ -n "$canonical_path" ]; then
        if [[ "$canonical_path" = /* ]]; then
          canonical_abs_path="$canonical_path"
        else
          canonical_abs_path="$ROOT_DIR/$canonical_path"
        fi
      else
        canonical_abs_path=""
      fi
      if [ -n "$canonical_abs_path" ] && [ -f "$canonical_abs_path" ]; then
        rm -f "$tmp_out"
      else
        mv -f "$tmp_out" "$out_path"
      fi
    else
      duplicate_of=""
      status="downloaded"
      downloaded_count=$((downloaded_count + 1))
      mv -f "$tmp_out" "$out_path"
      if [ -n "$run_doc_ids_file" ]; then
        printf "%s\n" "$doc_id" >> "$run_doc_ids_file"
      fi
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
