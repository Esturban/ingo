#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ingo_load_env() {
  if [ -f "$ROOT_DIR/.env" ]; then
    local name value
    local -a preserved_names=()
    local -a preserved_values=()

    # Let .env execute normally, then restore caller-provided runtime overrides.
    while IFS= read -r name; do
      preserved_names+=("$name")
      preserved_values+=("${!name}")
    done < <(compgen -A variable INGO_)
    for name in UPSTASH_VECTOR_REST_URL UPSTASH_VECTOR_REST_TOKEN; do
      if [ -n "${!name+x}" ]; then
        preserved_names+=("$name")
        preserved_values+=("${!name}")
      fi
    done

    set -a
    # shellcheck source=/dev/null
    . "$ROOT_DIR/.env"
    set +a

    for ((i = 0; i < ${#preserved_names[@]}; i++)); do
      name="${preserved_names[$i]}"
      value="${preserved_values[$i]}"
      printf -v "$name" '%s' "$value"
      export "${name?}"
    done
  fi

  : "${INGO_INBOX:=$HOME/ingest}"
  : "${INGO_RAW_DIR:=data/raw}"
  : "${INGO_CHUNK_DIR:=data/chunks}"
  : "${INGO_NAMESPACE:=legal-co}"
  : "${INGO_LANG:=spa}"
  : "${INGO_CHUNK_SIZE:=1400}"
  : "${INGO_CHUNK_OVERLAP:=180}"
  : "${INGO_CLEANUP_TEXT:=1}"
  : "${INGO_RELEVANCE_MODE:=strict}"
  : "${INGO_MIN_TERM_MATCHES:=2}"
  : "${INGO_REJECTED_DIR:=data/rejected}"
  : "${INGO_RELEVANCE_TERMS:=ambiental,licencia,vertimiento,emision,resolucion,decreto,articulo,autoridad,ministerio,agua,suelo,aire}"
  : "${INGO_CORPUS_DIR:=data/corpus}"
  : "${INGO_CRAWL_DEPTH:=2}"
  : "${INGO_ALLOWED_HOSTS_FILE:=data/corpus/config/allow_hosts.txt}"
  : "${INGO_INCLUDE_EXTENSIONS:=pdf,docx,xlsx,xlsm}"
  : "${INGO_EXCLUDE_EXTENSIONS:=zip,png,jpg,jpeg,gif,webp,svg,ico,js,css,map,woff,woff2,ttf,eot,mp3,mp4,mov,avi}"
  : "${INGO_PROGRESS_EVERY:=25}"
  : "${INGO_SNAPSHOT_PAGES_TO_PDF:=0}"
  : "${INGO_CRAWL_ALLOW_HTTP:=0}"
  : "${INGO_SKIP_PROBE_FOR_ALLOWED_EXTENSIONS:=1}"
  : "${INGO_ROLE:=all}"
  : "${INGO_VECTOR_BACKEND:=upstash}"
  : "${INGO_HTTP_CONNECT_TIMEOUT:=5}"
  : "${INGO_HTTP_READ_TIMEOUT:=30}"
  : "${INGO_HTTP_DOWNLOAD_TIMEOUT:=120}"

  if [ -n "${INGO_HTTP_RETRY_ATTEMPTS:-}" ]; then
    :
  elif [ -n "${INGO_HTTP_RETRY_MAX:-}" ]; then
    INGO_HTTP_RETRY_ATTEMPTS="$INGO_HTTP_RETRY_MAX"
  else
    INGO_HTTP_RETRY_ATTEMPTS="2"
  fi

  if [ -n "${INGO_HTTP_RETRY_BACKOFF_MIN:-}" ]; then
    :
  elif [ -n "${INGO_HTTP_RETRY_BACKOFF:-}" ]; then
    INGO_HTTP_RETRY_BACKOFF_MIN="$INGO_HTTP_RETRY_BACKOFF"
  else
    INGO_HTTP_RETRY_BACKOFF_MIN="1"
  fi

  : "${INGO_HTTP_RETRY_BACKOFF_MAX:=8}"
  : "${INGO_HTTP_RETRY_BACKOFF_FACTOR:=2}"
  : "${INGO_HTTP_RETRY_AFTER_MAX:=$INGO_HTTP_RETRY_BACKOFF_MAX}"

  if [ -n "${INGO_VECTOR_URL:-}" ]; then
    :
  elif [ -n "${UPSTASH_VECTOR_REST_URL:-}" ]; then
    INGO_VECTOR_URL="$UPSTASH_VECTOR_REST_URL"
  else
    INGO_VECTOR_URL=""
  fi

  if [ -n "${INGO_VECTOR_TOKEN:-}" ]; then
    :
  elif [ -n "${UPSTASH_VECTOR_REST_TOKEN:-}" ]; then
    INGO_VECTOR_TOKEN="$UPSTASH_VECTOR_REST_TOKEN"
  else
    INGO_VECTOR_TOKEN=""
  fi

  : "${INGO_VECTOR_MODEL:=}"
  : "${INGO_EMBEDDING_MODE:=provider}"
  : "${INGO_EMBEDDER_BACKEND:=ollama}"
  : "${INGO_EMBEDDER_URL:=}"
  : "${INGO_EMBEDDER_MODEL:=}"
  : "${INGO_EMBEDDER_TOKEN:=}"

  if [ -z "${UPSTASH_VECTOR_REST_URL:-}" ] && [ -n "$INGO_VECTOR_URL" ]; then
    UPSTASH_VECTOR_REST_URL="$INGO_VECTOR_URL"
  fi
  if [ -z "${UPSTASH_VECTOR_REST_TOKEN:-}" ] && [ -n "$INGO_VECTOR_TOKEN" ]; then
    UPSTASH_VECTOR_REST_TOKEN="$INGO_VECTOR_TOKEN"
  fi

  # Keep legacy names populated for compatibility with older scripts/tests.
  INGO_HTTP_RETRY_MAX="$INGO_HTTP_RETRY_ATTEMPTS"
  INGO_HTTP_RETRY_BACKOFF="$INGO_HTTP_RETRY_BACKOFF_MIN"
}

ingo_require_positive_integer_env() {
  local name="$1"
  local value="${!name:-}"
  ingo_require_positive_integer "$name" "$value"
}

ingo_require_bin() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing dependency: $cmd" >&2
    return 3
  fi
}

ingo_require_tesseract_lang() {
  local lang="$1"
  local list line
  if ! list="$(tesseract --list-langs 2>/dev/null)"; then
    echo "failed to list tesseract languages via 'tesseract --list-langs'" >&2
    return 5
  fi

  while IFS= read -r line; do
    if [ "$line" = "$lang" ]; then
      return 0
    fi
  done <<< "$list"

  echo "missing OCR language data for INGO_LANG=$lang (not found in 'tesseract --list-langs')" >&2
  return 5
}

ingo_require_env() {
  local missing=0
  if [ -z "${INGO_VECTOR_URL:-}" ]; then
    echo "missing env var: INGO_VECTOR_URL (legacy: UPSTASH_VECTOR_REST_URL)" >&2
    missing=1
  fi
  if [ -z "${INGO_VECTOR_TOKEN:-}" ]; then
    echo "missing env var: INGO_VECTOR_TOKEN (legacy: UPSTASH_VECTOR_REST_TOKEN)" >&2
    missing=1
  fi
  if [ "$missing" -ne 0 ]; then
    return 4
  fi
}

ingo_prepare_dirs() {
  mkdir -p "$INGO_INBOX" "$ROOT_DIR/$INGO_RAW_DIR" "$ROOT_DIR/$INGO_CHUNK_DIR" "$ROOT_DIR/$INGO_REJECTED_DIR"
}

ingo_require_ingest_enabled() {
  if [ "$INGO_ROLE" = "query" ]; then
    echo "ingest commands are disabled on this device (INGO_ROLE=query)" >&2
    return 6
  fi
}

ingo_require_positive_integer() {
  local name="$1"
  local value="$2"
  case "$value" in
    ''|*[!0-9]*|0)
      echo "invalid $name: must be a positive integer (got '$value')" >&2
      return 2
      ;;
  esac
}

ingo_require_nonnegative_integer() {
  local name="$1"
  local value="$2"
  case "$value" in
    ''|*[!0-9]*)
      echo "invalid $name: must be a non-negative integer (got '$value')" >&2
      return 2
      ;;
  esac
}
