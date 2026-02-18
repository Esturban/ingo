#!/usr/bin/env bash

set -euo pipefail

ingo_fetch_url() {
  local url="$1"
  local inbox="$2"
  local ts out

  ts="$(date +%Y%m%d-%H%M%S)"
  out="$inbox/$ts.pdf"
  curl -fsSL "$url" -o "$out"
  printf "%s\n" "$out"
}

ingo_list_pdfs() {
  local inbox="$1"
  find "$inbox" -maxdepth 1 -type f -name '*.pdf' | sort
}
