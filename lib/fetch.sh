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
  local ts candidate

  ts="$(date +%Y%m%d-%H%M%S)"
  while :; do
    candidate="$inbox/${ts}-${BASHPID}-${RANDOM}.pdf"
    if (set -o noclobber; : > "$candidate") 2>/dev/null; then
      printf "%s\n" "$candidate"
      return 0
    fi
  done
}
