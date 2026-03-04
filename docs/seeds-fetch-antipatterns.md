# Seed Fetch Anti-Patterns and Simplification

This note captures the runtime anti-patterns that reduced yield and caused confusing crawl behavior in `fetch --seeds`, and the simplified policy now used.

## Anti-Patterns Removed

1. Discovery-phase topic gating.
- Previous behavior filtered non-document links by narrow keyword patterns, dropping valid traversal paths.
- Current behavior keeps discovery generic and defers document acceptance to collect/probe.

2. Split policy decisions across phases.
- Previous behavior applied different inclusion logic in discovery vs collect, producing hard-to-debug drop-offs.
- Current behavior centralizes acceptance/rejection in collect (`extension + MIME + deny patterns + host policy`).

3. Expensive flat-file membership checks.
- Previous behavior repeatedly used `grep` over `visited/queued` files.
- Current behavior uses in-memory sets during the run and still writes debug files for traceability.

4. Hidden host defaults.
- Previous behavior had implicit host acceptance that could over/under-include.
- Current behavior derives runtime host policy from `seed hosts + --allow-hosts`.

## Runtime Observability

The crawl now reports per-phase progress:
- `crawl-progress`: discovery and queue growth.
- `collect-progress`: probing/downloading with downloaded/duplicate/failed/skipped counters.
- `extract-progress`: extraction counters.

End-of-run diagnostics now include:
- `crawl-skip-reasons` frequency table.
- `crawl-error-types` frequency table.

## Duplicate and Rerun Behavior

- Manifests are append-only by default.
- Already-seen URLs are skipped with reason `already_seen_url`.
- Extraction in `fetch --seeds` is scoped to documents downloaded in the current run.
- Use `--reset-manifests` only for an intentional clean-run ledger reset.
