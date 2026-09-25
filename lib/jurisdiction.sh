#!/usr/bin/env bash
# REUSE_CHECKED: none -- searched this repo for '*jurisdiction*' and grepped
# for "jurisdiction" (DEV-6550); nothing already does per-legal-system
# pattern/vocabulary selection here.

set -euo pipefail

# DEV-6550: jurisdiction profiles let one seat's legal system (patterns for
# what counts as an "articulo"/"paragrafo"/"numeral" heading, plus relevance
# vocabulary) live as a small data file under profiles/, instead of that
# seat forking its own copy of ingo. See docs/jurisdiction-profiles.md.
ingo_apply_jurisdiction_profile() {
  local jurisdiction="$1"
  local profile_file="$ROOT_DIR/profiles/$jurisdiction.sh"

  if [ "$jurisdiction" = "generic" ]; then
    return 0
  fi
  if [ ! -f "$profile_file" ]; then
    echo "warning: unknown INGO_JURISDICTION='$jurisdiction' (no $profile_file); using generic defaults" >&2
    return 0
  fi

  # shellcheck disable=SC1090
  source "$profile_file"
}
