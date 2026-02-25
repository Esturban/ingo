#!/usr/bin/env bash

set -euo pipefail

# Retriable HTTP status matrix:
#   408 Request Timeout       – transient server-side timeout
#   429 Too Many Requests     – rate limited; honor Retry-After when present
#   500 Internal Server Error – transient upstream fault
#   502 Bad Gateway           – transient upstream fault
#   503 Service Unavailable   – transient upstream fault; honor Retry-After
#   504 Gateway Timeout       – transient upstream timeout
ingo_http_is_retriable_status() {
  case "$1" in
    408|429|500|502|503|504) return 0 ;;
    *) return 1 ;;
  esac
}

# Retriable curl exit code matrix:
#    7 CURLE_COULDNT_CONNECT    – connection refused / host unreachable
#   18 CURLE_PARTIAL_FILE       – transfer interrupted mid-stream
#   28 CURLE_OPERATION_TIMEDOUT – request exceeded --max-time
#   52 CURLE_GOT_NOTHING        – server closed connection without response
#   56 CURLE_RECV_ERROR         – network receive error
ingo_http_is_retriable_exit_code() {
  case "$1" in
    7|18|28|52|56) return 0 ;;
    *) return 1 ;;
  esac
}

ingo_http_extract_status_code() {
  local headers_file="$1"
  grep -E '^HTTP/[0-9.]+ [0-9]{3}' "$headers_file" | tail -n 1 | awk '{print $2}'
}

ingo_http_extract_retry_after_raw() {
  local headers_file="$1"
  awk -F': *' '
    /^HTTP\// {retry_after=""}
    /^[Rr]etry-[Aa]fter:/ {
      value=$2
      sub(/\r$/, "", value)
      retry_after=value
    }
    END {print retry_after}
  ' "$headers_file"
}

ingo_http_to_epoch() {
  local value="$1"
  if date -u -d "$value" +%s >/dev/null 2>&1; then
    date -u -d "$value" +%s
    return 0
  fi
  if date -u -j -f "%a, %d %b %Y %H:%M:%S GMT" "$value" +%s >/dev/null 2>&1; then
    date -u -j -f "%a, %d %b %Y %H:%M:%S GMT" "$value" +%s
    return 0
  fi
  return 1
}

ingo_http_retry_after_seconds() {
  local headers_file="$1"
  local raw now epoch

  raw="$(ingo_http_extract_retry_after_raw "$headers_file")"
  if [ -z "$raw" ]; then
    return 1
  fi

  if [[ "$raw" =~ ^[0-9]+$ ]]; then
    printf "%s\n" "$raw"
    return 0
  fi

  if ! epoch="$(ingo_http_to_epoch "$raw")"; then
    return 1
  fi
  now="$(date -u +%s)"
  if [ "$epoch" -le "$now" ]; then
    printf "0\n"
  else
    printf "%s\n" $((epoch - now))
  fi
}

ingo_http_computed_backoff() {
  local retry_index="$1"
  local delay="$INGO_HTTP_RETRY_BACKOFF_MIN"
  local i=0

  while [ "$i" -lt "$retry_index" ]; do
    delay=$((delay * INGO_HTTP_RETRY_BACKOFF_FACTOR))
    i=$((i + 1))
  done

  if [ "$delay" -gt "$INGO_HTTP_RETRY_BACKOFF_MAX" ]; then
    delay="$INGO_HTTP_RETRY_BACKOFF_MAX"
  fi
  printf "%s\n" "$delay"
}

ingo_http_retry_delay_seconds() {
  local retry_index="$1"
  local headers_file="$2"
  local delay

  if delay="$(ingo_http_retry_after_seconds "$headers_file")"; then
    if [ "$delay" -gt "$INGO_HTTP_RETRY_AFTER_MAX" ]; then
      delay="$INGO_HTTP_RETRY_AFTER_MAX"
    fi
    if [ "$delay" -gt "$INGO_HTTP_RETRY_BACKOFF_MAX" ]; then
      delay="$INGO_HTTP_RETRY_BACKOFF_MAX"
    fi
    printf "%s\n" "$delay"
    return 0
  fi

  ingo_http_computed_backoff "$retry_index"
}

ingo_http_curl() {
  local attempt=0
  local status curl_rc should_retry delay headers_file body_file err_file

  while :; do
    headers_file="$(mktemp)"
    body_file="$(mktemp)"
    err_file="$(mktemp)"
    set +e
    curl \
      --connect-timeout "$INGO_HTTP_CONNECT_TIMEOUT" \
      --max-time "$INGO_HTTP_READ_TIMEOUT" \
      -D "$headers_file" \
      "$@" >"$body_file" 2>"$err_file"
    curl_rc=$?
    set -e

    status="$(ingo_http_extract_status_code "$headers_file" || true)"
    should_retry=1
    if [ -n "$status" ] && ingo_http_is_retriable_status "$status"; then
      should_retry=0
    elif [ "$curl_rc" -ne 0 ] && ingo_http_is_retriable_exit_code "$curl_rc"; then
      should_retry=0
    fi

    if [ "$should_retry" -eq 0 ] && [ "$attempt" -lt "$INGO_HTTP_RETRY_MAX" ]; then
      delay="$(ingo_http_retry_delay_seconds "$attempt" "$headers_file")"
      rm -f "$headers_file" "$body_file" "$err_file"
      sleep "$delay"
      attempt=$((attempt + 1))
      continue
    fi

    cat "$body_file"
    cat "$err_file" >&2
    rm -f "$headers_file" "$body_file" "$err_file"
    return "$curl_rc"
  done
}
