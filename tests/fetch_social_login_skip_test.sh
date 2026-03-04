#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
source "$ROOT_DIR/lib/fetch.sh"

fail() { echo "FAIL: $*" >&2; exit 1; }

main() {
  ingo_url_matches_deny_pattern "https://api.whatsapp.com/send?x=1" || fail "whatsapp should be denied"
  ingo_url_matches_deny_pattern "https://co.linkedin.com/company/anla" || fail "linkedin should be denied"
  ingo_url_matches_deny_pattern "https://vital.minambiente.gov.co/SILPA/Security/Login.aspx" || fail "login should be denied"
  ingo_url_matches_deny_pattern "https://www.anla.gov.co/01_anla/tel:018000" || fail "tel links should be denied"
  ingo_url_matches_deny_pattern "https://www.anla.gov.co/01_anla/mailto:test@example.com" || fail "mailto links should be denied"
  if ingo_url_matches_deny_pattern "https://www.anla.gov.co/01_anla/documentos/informacion_geografica/guia.pdf"; then
    fail "gdb doc should not be denied"
  fi
  echo ok
}

main "$@"
