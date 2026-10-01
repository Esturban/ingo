#!/usr/bin/env bash
# REUSE_CHECKED: /Users/EVA/Desktop/eva/03_development/_dev/repos/3_utilities/sh/ingo/tests/query_top_k_validation_test.sh
# matched its fail/assert_eq/test_*/main() style; no existing test already
# covers the DEV-6550 jurisdiction-profile loader (lib/jurisdiction.sh,
# profiles/co.sh).

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib/jurisdiction.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/jurisdiction.sh"
# shellcheck source=../lib/env.sh
# shellcheck disable=SC1091
source "$ROOT_DIR/lib/env.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

assert_eq() {
  local got="$1"
  local want="$2"
  local msg="$3"
  if [ "$got" != "$want" ]; then
    fail "$msg (got='$got' want='$want')"
  fi
}

# Run ingo_load_env in a clean subshell each time so one test's env vars
# never leak into the next (they are exported by `: "${VAR:=...}"` inside
# ingo_load_env, which happens in-process, not in a child).

test_generic_jurisdiction_has_no_paragraph_or_numeral_pattern() {
  local paragraph_pattern numeral_pattern
  paragraph_pattern="$(bash -c '
    ROOT_DIR="'"$ROOT_DIR"'"
    source "$ROOT_DIR/lib/jurisdiction.sh"
    source "$ROOT_DIR/lib/env.sh"
    INGO_JURISDICTION=generic
    ingo_load_env
    printf "%s" "$INGO_PARAGRAPH_PATTERN"
  ')"
  numeral_pattern="$(bash -c '
    ROOT_DIR="'"$ROOT_DIR"'"
    source "$ROOT_DIR/lib/jurisdiction.sh"
    source "$ROOT_DIR/lib/env.sh"
    INGO_JURISDICTION=generic
    ingo_load_env
    printf "%s" "$INGO_NUMERAL_PATTERN"
  ')"
  assert_eq "$paragraph_pattern" "" "generic jurisdiction leaves INGO_PARAGRAPH_PATTERN empty"
  assert_eq "$numeral_pattern" "" "generic jurisdiction leaves INGO_NUMERAL_PATTERN empty"
}

test_co_jurisdiction_fills_in_paragraph_numeral_and_relevance_terms() {
  local paragraph_pattern numeral_pattern relevance_terms issuer_hints
  paragraph_pattern="$(bash -c '
    ROOT_DIR="'"$ROOT_DIR"'"
    source "$ROOT_DIR/lib/jurisdiction.sh"
    source "$ROOT_DIR/lib/env.sh"
    INGO_JURISDICTION=co
    ingo_load_env
    printf "%s" "$INGO_PARAGRAPH_PATTERN"
  ')"
  numeral_pattern="$(bash -c '
    ROOT_DIR="'"$ROOT_DIR"'"
    source "$ROOT_DIR/lib/jurisdiction.sh"
    source "$ROOT_DIR/lib/env.sh"
    INGO_JURISDICTION=co
    ingo_load_env
    printf "%s" "$INGO_NUMERAL_PATTERN"
  ')"
  # This machine's own ingo/.env (gitignored, real local config) already
  # pins INGO_RELEVANCE_TERMS to the generic value, which is a legitimate
  # higher-precedence override in production but would make this test only
  # prove ".env wins", not "the co profile fills these in". Clear it first
  # (empty counts as unset for ":=" purposes) so this test exercises the
  # profile's own default in isolation from whatever .env this repo has.
  relevance_terms="$(bash -c '
    ROOT_DIR="'"$ROOT_DIR"'"
    source "$ROOT_DIR/lib/jurisdiction.sh"
    source "$ROOT_DIR/lib/env.sh"
    INGO_JURISDICTION=co
    INGO_RELEVANCE_TERMS=""
    ingo_load_env
    printf "%s" "$INGO_RELEVANCE_TERMS"
  ')"
  issuer_hints="$(bash -c '
    ROOT_DIR="'"$ROOT_DIR"'"
    source "$ROOT_DIR/lib/jurisdiction.sh"
    source "$ROOT_DIR/lib/env.sh"
    INGO_JURISDICTION=co
    INGO_ISSUER_HINTS=""
    ingo_load_env
    printf "%s" "$INGO_ISSUER_HINTS"
  ')"

  [ -n "$paragraph_pattern" ] || fail "co jurisdiction should set a non-empty INGO_PARAGRAPH_PATTERN"
  # Regression check for a real bug found while wiring this profile: a
  # literal {n,m} interval inside a bash "${VAR:=word}" default silently
  # truncates the value right after the interval's closing brace. Assert
  # the FULL numeral pattern survives end to end, not just "non-empty".
  assert_eq "$numeral_pattern" '^[[:space:]]*([0-9]{1,3}|[a-z])[.)][[:space:]]+' \
    "co jurisdiction's INGO_NUMERAL_PATTERN must not be truncated at the {n,m} interval"
  case "$relevance_terms" in
    *anla*) : ;;
    *) fail "co jurisdiction's INGO_RELEVANCE_TERMS should mention anla (got '$relevance_terms')" ;;
  esac
  case "$issuer_hints" in
    *"ANLA:AUTORIDAD NACIONAL DE LICENCIAS AMBIENTALES"*) : ;;
    *) fail "co jurisdiction's INGO_ISSUER_HINTS should include the ANLA hint (got '$issuer_hints')" ;;
  esac
}

test_explicit_runtime_override_wins_over_the_profile() {
  local article_pattern
  article_pattern="$(bash -c '
    ROOT_DIR="'"$ROOT_DIR"'"
    source "$ROOT_DIR/lib/jurisdiction.sh"
    source "$ROOT_DIR/lib/env.sh"
    INGO_JURISDICTION=co
    INGO_ARTICLE_PATTERN="custom-pattern-from-caller"
    ingo_load_env
    printf "%s" "$INGO_ARTICLE_PATTERN"
  ')"
  assert_eq "$article_pattern" "custom-pattern-from-caller" \
    "a caller-supplied INGO_ARTICLE_PATTERN must survive loading the co profile"
}

test_unknown_jurisdiction_warns_and_falls_back_to_generic() {
  local out status
  set +e
  out="$(bash -c '
    ROOT_DIR="'"$ROOT_DIR"'"
    source "$ROOT_DIR/lib/jurisdiction.sh"
    source "$ROOT_DIR/lib/env.sh"
    INGO_JURISDICTION=does-not-exist
    ingo_load_env
    printf "%s" "$INGO_NUMERAL_PATTERN"
  ' 2>&1)"
  status=$?
  set -e
  assert_eq "$status" "0" "an unknown jurisdiction must not fail ingo_load_env"
  case "$out" in
    *"warning: unknown INGO_JURISDICTION"*) : ;;
    *) fail "expected a warning for an unknown jurisdiction (got '$out')" ;;
  esac
}

main() {
  test_generic_jurisdiction_has_no_paragraph_or_numeral_pattern
  test_co_jurisdiction_fills_in_paragraph_numeral_and_relevance_terms
  test_explicit_runtime_override_wins_over_the_profile
  test_unknown_jurisdiction_warns_and_falls_back_to_generic
  echo "ok"
}

main "$@"
