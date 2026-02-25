#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

ingo_load_env() {
  if [ -f "$ROOT_DIR/.env" ]; then
    set -a
    # shellcheck source=/dev/null
    . "$ROOT_DIR/.env"
    set +a
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
  : "${INGO_ROLE:=all}"
  : "${INGO_HTTP_CONNECT_TIMEOUT:=5}"
  : "${INGO_HTTP_READ_TIMEOUT:=30}"
  : "${INGO_HTTP_RETRY_MAX:=2}"
  : "${INGO_HTTP_RETRY_BACKOFF:=1}"
  : "${INGO_HTTP_RETRY_BACKOFF_MIN:=$INGO_HTTP_RETRY_BACKOFF}"
  : "${INGO_HTTP_RETRY_BACKOFF_MAX:=30}"
  : "${INGO_HTTP_RETRY_BACKOFF_FACTOR:=2}"
  : "${INGO_HTTP_RETRY_AFTER_MAX:=$INGO_HTTP_RETRY_BACKOFF_MAX}"
}

ingo_require_bin() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "missing dependency: $cmd" >&2
    return 3
  fi
}

ingo_require_env() {
  local missing=0
  for key in UPSTASH_VECTOR_REST_URL UPSTASH_VECTOR_REST_TOKEN; do
    if [ -z "${!key:-}" ]; then
      echo "missing env var: $key" >&2
      missing=1
    fi
  done
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
