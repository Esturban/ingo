You are planning a repo-specific fix for issue #13 in Esturban/ingo.

Objective:
Ship a lightweight, reliable shell RAG runtime for fast agent querying over indexed documents.

Issue URL: https://github.com/Esturban/ingo/issues/13
Issue title: Harden ingest shell scripts by fixing embed pipeline lint findings
Issue body:
## Problem
The ingest shell runtime has lint findings in the embed path that can hide reliability issues over time.

## Scope
- Fix shell lint findings in `lib/embed.sh` and related sourcing behavior in `bin/ingo`.
- Preserve existing ingest/query behavior and CLI command contract.

## Acceptance Criteria
- `bin/ingo doctor` succeeds.
- `shellcheck -x bin/ingo lib/*.sh` succeeds.
- `bin/ingo --help` output remains unchanged.

Prior run memory:
## Prior Run Memory
- unavailable for this run

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
