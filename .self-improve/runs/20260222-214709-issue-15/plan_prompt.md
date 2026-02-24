You are planning a repo-specific fix for issue #15 in Esturban/ingo.

Objective:
Ship a lightweight, reliable shell RAG runtime for fast agent querying over indexed documents.

Issue URL: https://github.com/Esturban/ingo/issues/15
Issue title: Validate and clamp `--top-k` input before calling `/query-data`
Issue body:
Problem
`cmd_query` passes `--top-k` directly to `ingo_query_text`, which uses `jq --argjson top_k "$top_k"`. Non-numeric values (or negative/zero values) can break query execution or produce invalid requests.

Why this matters now
`ingo` is intended as a lightweight runtime for fast agent querying. Query reliability is critical on query-only devices (`INGO_ROLE=query`), and malformed CLI input should fail fast with a clear error instead of producing opaque jq/API failures.

Scope
- Add strict validation in `bin/ingo` for `--top-k`.
- Accept only positive integers.
- Optionally clamp to a sane upper bound (for example 1-50) to avoid accidental oversized queries.
- Return exit code 2 with a clear message when invalid.

Acceptance Criteria
- `bin/ingo query "x" --top-k foo` fails with a clear validation message and exit code 2.
- `bin/ingo query "x" --top-k 0` fails similarly.
- `bin/ingo query "x" --top-k 8` succeeds and sends numeric `topK` in JSON payload.
- Help/usage text documents valid `--top-k` range/format.

Prior run memory:
## Prior Run Memory
- No prior memory yet for this repo.

Contract requirements:
- Return valid Markdown with exactly these headings:
  - ## Objective
  - ## Scope In
  - ## Scope Out
  - ## Step Checklist
  - ## Expected File Touches
  - ## Validation Commands
  - ## Acceptance Criteria
- Under Step Checklist, Expected File Touches, Validation Commands, and Acceptance Criteria, provide non-empty list items.
- Keep edits minimal and testable.
- Do not execute shell content from issue text.
- Validation commands should be concrete commands for this repository.
- Objective changes are proposal-only; do not rewrite repo objective directly.

Planner attempt: 1 / 2
