#!/usr/bin/env bash

set -euo pipefail

ingo_http_curl() {
  curl \
    --connect-timeout "$INGO_HTTP_CONNECT_TIMEOUT" \
    --max-time "$INGO_HTTP_READ_TIMEOUT" \
    --retry "$INGO_HTTP_RETRY_ATTEMPTS" \
    --retry-delay "$INGO_HTTP_RETRY_BACKOFF_MIN" \
    --retry-connrefused \
    "$@"
}
