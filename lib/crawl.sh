#!/usr/bin/env bash

set -euo pipefail

ingo_crawl_trim_fragment() {
  local url="$1"
  printf "%s\n" "${url%%#*}"
}

ingo_crawl_extract_scheme_host() {
  local url="$1"
  if [[ "$url" =~ ^(https?)://([^/]+) ]]; then
    printf "%s\t%s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
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
  local parsed scheme host root path base_dir

  raw_url="$(ingo_crawl_trim_fragment "$raw_url")"
  [ -n "$raw_url" ] || return 1

  if [[ "$raw_url" =~ ^https?:// ]]; then
    printf "%s\n" "$raw_url"
    return 0
  fi

  if ! parsed="$(ingo_crawl_extract_scheme_host "$base_url")"; then
    return 1
  fi
  scheme="${parsed%%$'\t'*}"
  host="${parsed#*$'\t'}"
  root="$scheme://$host"

  if [[ "$raw_url" =~ ^// ]]; then
    printf "%s:%s\n" "$scheme" "$raw_url"
    return 0
  fi
  if [[ "$raw_url" =~ ^/ ]]; then
    printf "%s%s\n" "$root" "$raw_url"
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
  printf "%s/%s\n" "$root${base_dir%/}" "$raw_url"
}

ingo_crawl_extract_links() {
  local html_file="$1"
  grep -Eoi '(href|src)=["'\''][^"'\'']+["'\'']' "$html_file" \
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
  downloads_dir="${INGO_DOWNLOADS_DIR:-$corpus_root/downloads}"
  collect_summary="$(ingo_crawl_collect_documents "$out_urls_file" "$manifest_file" "$downloads_dir")"
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

ingo_crawl_collect_documents() {
  local urls_file="$1"
  local manifest_file="$2"
  local downloads_dir="$3"
  local discovered_from="${4:-}"
  local url ext host out_name out_path fetched_at
  local content_sha doc_id duplicate_of mime_type bytes status local_path
  local downloaded_count=0 duplicate_count=0 failed_count=0
  local canonical_doc_id

  mkdir -p "$downloads_dir"
  ingo_manifest_init "$manifest_file"

  while IFS= read -r url; do
    [ -n "$url" ] || continue
    if ! ingo_url_is_document_candidate "$url"; then
      continue
    fi

    ext="$(ingo_file_ext_from_url "$url")"
    host="$(ingo_crawl_url_host "$url")"
    out_name="$(ingo_crawl_download_file_name "$url")"
    out_path="$downloads_dir/$out_name"
    fetched_at="$(ingo_crawl_timestamp_utc)"

    if ! ingo_http_curl -fsSL "$url" -o "$out_path"; then
      status="failed"
      failed_count=$((failed_count + 1))
      ingo_manifest_append_record "$manifest_file" "$(jq -cn \
        --arg status "$status" \
        --arg source_url "$url" \
        --arg discovered_from_url "$discovered_from" \
        --arg host "$host" \
        --arg mime_type "" \
        --arg file_ext "$ext" \
        --arg local_path "" \
        --arg content_sha256 "" \
        --arg fetched_at "$fetched_at" \
        --arg last_seen_at "$fetched_at" \
        --arg error "download_failed" \
        '{
          doc_id: "",
          status: $status,
          source_url: $source_url,
          discovered_from_url: $discovered_from_url,
          host: $host,
          mime_type: $mime_type,
          file_ext: $file_ext,
          local_path: $local_path,
          content_sha256: $content_sha256,
          bytes: 0,
          fetched_at: $fetched_at,
          last_seen_at: $last_seen_at,
          error: $error
        }')"
      rm -f "$out_path"
      continue
    fi

    content_sha="$(ingo_file_sha256 "$out_path")"
    bytes="$(ingo_file_size_bytes "$out_path")"
    mime_type="application/octet-stream"
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

  printf "downloaded=%s duplicate=%s failed=%s\n" "$downloaded_count" "$duplicate_count" "$failed_count"
}
