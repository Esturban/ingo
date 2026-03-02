#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/crawl.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

main() {
  local tmp seeds allow runtime
  tmp="$(mktemp -d)"
  seeds="$tmp/seeds.txt"
  allow="$tmp/allow.txt"
  runtime="$tmp/runtime.txt"

  cat > "$seeds" <<'SEEDS'
https://www.anla.gov.co/01_anla/sistema-de-informacion-geografica
https://datosabiertos-anla.hub.arcgis.com/
SEEDS
  cat > "$allow" <<'ALLOW'
geoportal.igac.gov.co
ALLOW

  ingo_crawl_build_allow_hosts_file "$seeds" "$allow" "$runtime"

  ingo_crawl_host_allowed "www.anla.gov.co" "$runtime" || fail "seed host should be allowed"
  ingo_crawl_host_allowed "datosabiertos-anla.hub.arcgis.com" "$runtime" || fail "seed host should be allowed"
  ingo_crawl_host_allowed "geoportal.igac.gov.co" "$runtime" || fail "allowlist host should be allowed"
  if ingo_crawl_host_allowed "api.whatsapp.com" "$runtime"; then
    fail "non-seed non-allowlist host should be blocked"
  fi
}

main
echo ok
