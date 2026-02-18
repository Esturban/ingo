#!/usr/bin/env bash

set -euo pipefail

ingo_relevance_match_count() {
  local txt="$1"
  local terms_csv="$2"
  local content terms term count

  content="$(tr '[:upper:]' '[:lower:]' < "$txt" 2>/dev/null || true)"
  terms="$(printf "%s" "$terms_csv" | tr ',' '\n')"
  count=0

  while IFS= read -r term; do
    term="$(printf "%s" "$term" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$term" ] || continue
    if printf "%s" "$content" | grep -F -q "$term"; then
      count=$((count + 1))
    fi
  done <<< "$terms"

  printf "%s\n" "$count"
}

ingo_is_relevant() {
  local txt="$1"
  local min_matches="$2"
  local terms_csv="$3"
  local matches

  matches="$(ingo_relevance_match_count "$txt" "$terms_csv")"
  if [ "$matches" -ge "$min_matches" ]; then
    return 0
  fi
  return 1
}
