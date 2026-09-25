# REUSE_CHECKED: none -- no prior jurisdiction/profile doc existed under
# docs/ before DEV-6550.

# Jurisdiction profiles (DEV-6550)

`ingo` is one tool shared across seats/domains. A seat working a different
legal system should not fork the tool -- it should add a profile.

## How it works

- `INGO_JURISDICTION` selects a profile (default: `generic`).
- `lib/jurisdiction.sh` sources `profiles/$INGO_JURISDICTION.sh` (if it
  exists) from inside `ingo_load_env`, before the hardcoded generic
  defaults in `lib/env.sh` are applied.
- A profile file only uses `: "${VAR:=...}"` assignments, so anything
  already set by the caller's real environment or `.env` (higher
  precedence) is never overridden. Precedence, highest first: runtime env /
  `.env` > jurisdiction profile > generic hardcoded default.
- Unknown `INGO_JURISDICTION` values print a warning and fall back to the
  generic defaults; they never hard-fail `ingo`.

## What a profile can set

| Variable | Purpose |
| --- | --- |
| `INGO_SECTION_PATTERN` | Regex (matched against a lowercase, accent-folded line -- see `lc_es()` in `lib/chunk.sh`) for title/chapter/section headings. |
| `INGO_ARTICLE_PATTERN` | Regex for "article" headings -- the primary legal citation unit. |
| `INGO_PARAGRAPH_PATTERN` | Regex for a "paragrafo"-equivalent sub-heading, if the jurisdiction has one. Empty disables it. |
| `INGO_NUMERAL_PATTERN` | Regex for enumerated numeral items (`1.`, `a)`, ...). Empty disables it. |
| `INGO_RELEVANCE_TERMS` | Comma-separated vocabulary for the relevance gate (`lib/relevance.sh`) -- rejects OCR noise that never mentions a term from this jurisdiction's domain. |
| `INGO_ISSUER_HINTS` | Comma-separated `ISSUER:PHRASE` pairs a consumer (e.g. `sig norma`) can use to label a source by scanning its own text, when no manifest metadata exists for it. |

## `profiles/co.sh` -- Colombia (ANLA, IGAC, MADS, CAR)

Ships as the reference profile for this ticket's own use case: Yuliana's
environmental-compliance corpus. Load it with:

```bash
INGO_JURISDICTION=co bin/ingo chunk
```

or set `INGO_JURISDICTION=co` in `.env`.

## Adding a new jurisdiction

1. Copy `profiles/co.sh` to `profiles/<name>.sh`.
2. Replace the patterns/vocabulary with the new jurisdiction's own legal
   drafting conventions (what an "article" heading looks like there, what
   the domain vocabulary is).
3. Set `INGO_JURISDICTION=<name>` for that seat. Nothing else in `ingo`
   changes -- the ingest/query pipeline, vector backends, and CLI surface
   are all shared.
