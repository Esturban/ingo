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
}
