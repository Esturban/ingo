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

ingo_file_ext_from_url() {
  local url="$1"
  local path ext
  path="${url%%\?*}"
  path="${path%%#*}"
  path="${path##*/}"
  ext="${path##*.}"
  if [ "$ext" = "$path" ]; then
    printf "\n"
    return 0
  fi
  printf "%s\n" "$(printf "%s" "$ext" | tr '[:upper:]' '[:lower:]')"
}

ingo_csv_contains() {
  local csv="$1"
  local needle="$2"
  local item
  needle="$(printf "%s" "$needle" | tr '[:upper:]' '[:lower:]')"
  IFS=',' read -r -a _items <<< "$csv"
  for item in "${_items[@]}"; do
    item="$(printf "%s" "$item" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [ -n "$item" ] || continue
    if [ "$item" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

ingo_is_document_extension() {
  local ext="$1"
  ext="$(printf "%s" "$ext" | tr '[:upper:]' '[:lower:]')"
  ingo_csv_contains "${INGO_INCLUDE_EXTENSIONS:-pdf,docx,xlsx,xlsm}" "$ext"
}

ingo_is_excluded_extension() {
  local ext="$1"
  ext="$(printf "%s" "$ext" | tr '[:upper:]' '[:lower:]')"
  ingo_csv_contains "${INGO_EXCLUDE_EXTENSIONS:-zip,png,jpg,jpeg,gif,webp,svg,ico,js,css,map,woff,woff2,ttf,eot,mp3,mp4,mov,avi}" "$ext"
}

ingo_url_matches_deny_pattern() {
  local url
  url="$(printf "%s" "$1" | tr '[:upper:]' '[:lower:]')"
  case "$url" in
    *linkedin.com*|*whatsapp.com*|*api.whatsapp.com*|*returnurl=*|*/security/*|*login*|\
    *mailto:*|*tel:*|*javascript:*|*data:*|\
    */ciudadania/*|*/participacion*|*/comunicate*|*/pqrs*|*/noticias/*|*/tramites-y-servicios*|\
    */images/*|*/media/*|*/templates/*|*/modules/*)
      return 0
      ;;
  esac
  return 1
}

ingo_url_is_allowed_page_candidate() {
  local url lc
  url="$1"
  lc="$(printf "%s" "$url" | tr '[:upper:]' '[:lower:]')"

  if ingo_url_matches_deny_pattern "$lc"; then
    return 1
  fi

  case "$lc" in
    *informacion_geografica*|\
    *sistema-de-informacion-geografica*|\
    *modelo-de-almacenamiento-geografico*|\
    *metadatos*|\
    *geodesia*|\
    *normograma*|\
    *datos-abiertos*|\
    *resolucion*)
      return 0
      ;;
  esac

  return 1
}

ingo_url_is_document_candidate() {
  local ext url="$1"
  if ingo_url_matches_deny_pattern "$url"; then
    return 1
  fi
  ext="$(ingo_file_ext_from_url "$1")"
  [ -n "$ext" ] || return 1
  if ingo_is_excluded_extension "$ext"; then
    return 1
  fi
  ingo_is_document_extension "$ext"
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
