#!/usr/bin/env bash

set -euo pipefail

ingo_fetch_url() {
  local url="$1"
  local inbox="$2"
  local out

  out="$(ingo_reserve_fetch_output "$inbox")"
  if ! ingo_http_curl -fsSL "$url" -o "$out"; then
    rm -f "$out"
    return 1
  fi
  printf "%s\n" "$out"
}

ingo_list_pdfs() {
  local inbox="$1"
  find "$inbox" -maxdepth 1 -type f -iname '*.pdf' | sort
}

ingo_reserve_fetch_output() {
  local inbox="$1"
  local ts candidate pid
  local max_attempts="${INGO_FETCH_RESERVE_MAX_ATTEMPTS:-128}"
  local attempt=1

  if [ ! -d "$inbox" ]; then
    echo "fetch output directory does not exist: $inbox" >&2
    return 2
  fi
  if [ ! -w "$inbox" ]; then
    echo "fetch output directory is not writable: $inbox" >&2
    return 2
  fi
  case "$max_attempts" in
    ''|*[!0-9]*|0)
      max_attempts=128
      ;;
  esac

  ts="$(date +%Y%m%d-%H%M%S)"
  pid="${BASHPID:-$$}"
  while [ "$attempt" -le "$max_attempts" ]; do
    candidate="$inbox/${ts}-${pid}-${RANDOM}.pdf"
    if (set -o noclobber; : > "$candidate") 2>/dev/null; then
      printf "%s\n" "$candidate"
      return 0
    fi
    attempt=$((attempt + 1))
  done

  echo "failed to reserve unique fetch output in $inbox after $max_attempts attempts" >&2
  return 2
}
