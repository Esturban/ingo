## Objective
Propose a minimal, testable fix plan for issue `#13` that removes current shell lint risks in the embed/sourcing paths while preserving runtime behavior and CLI output.

## Scope In
- Resolve current `shellcheck` findings in `bin/ingo` (`SC1091`) and `lib/embed.sh` (`SC2094`).
- Keep ingest/query command behavior unchanged (`doctor`, `embed`, `run`, `query`, etc.).
- Keep `bin/ingo --help` text byte-for-byte stable.

## Scope Out
- No feature work, refactors, or CLI contract changes.
- No changes to vector API semantics, relevance logic, OCR/chunk pipeline rules, or env variable schema.
- No dependency/toolchain changes beyond existing shell tooling.

## Step Checklist
- Capture baseline outputs:
  - `bin/ingo --help` output snapshot.
  - Current lint output from `shellcheck -x bin/ingo lib/*.sh`.
- Fix `SC1091` in `bin/ingo` by adjusting `# shellcheck source=...` hints so `shellcheck -x` can resolve sourced files from repo root.
- Fix `SC2094` in `lib/embed.sh` by restructuring the read loop to avoid any read/write-same-file lint ambiguity (without changing embed semantics).
- Keep edits surgical and localized; avoid altering argument parsing, usage text, and command dispatch.
- Re-run validations and confirm no behavioral drift in `doctor` and `--help`.

## Expected File Touches
- `bin/ingo`
  - Update only shellcheck source-annotation lines above `source` statements.
- `lib/embed.sh`
  - Adjust loop/input-file handling in `ingo_embed_jsonl` to satisfy lint safely.
- Optional (only if needed for repeatable check artifact): a temporary local diff/check command output, not committed.

## Validation Commands
- `shellcheck -x bin/ingo lib/*.sh`
- `bin/ingo doctor`
- `bin/ingo --help`
- `diff -u <(bin/ingo --help) <(bin/ingo --help)`  
  (Run before/after snapshot variant in practice to assert unchanged help text.)
- `git diff -- bin/ingo lib/embed.sh`  
  (Confirm only intended minimal edits landed.)

## Acceptance Criteria
- `bin/ingo doctor` exits `0` and prints expected success output (`ok`).
- `shellcheck -x bin/ingo lib/*.sh` exits `0` with no findings.
- `bin/ingo --help` output remains unchanged from baseline.
- Only intended files (`bin/ingo`, `lib/embed.sh`) are modified for this issue.