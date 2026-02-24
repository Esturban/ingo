## Objective
- Propose a minimal fix plan for issue #13 that resolves current ShellCheck findings in the embed/sourcing path while preserving the existing `ingo` ingest/query CLI behavior and command contract.

## Scope In
- Address `SC1091` sourcing-follow issues in `bin/ingo` so `shellcheck -x` can resolve sourced libs reliably.
- Address `SC2094` findings in `lib/embed.sh` around the JSONL read loop.
- Keep runtime behavior stable for `ingo embed`, `ingo doctor`, and `ingo --help`.
- Add only targeted, testable shell changes (no feature changes).

## Scope Out
- No changes to API/provider logic (Upstash request format, auth flow, endpoint behavior).
- No CLI UX redesign or help text rewording.
- No new commands, flags, dependencies, or broad refactors across unrelated `lib/*.sh` files.
- No changes driven by issue text execution; only repo-file edits and repo-local validation.

## Step Checklist
- Capture a baseline of help output to prove contract stability: run and save `bin/ingo --help`.
- Fix `bin/ingo` source directives so ShellCheck can statically follow local libs with `-x` (without changing runtime source targets).
- Refactor the `lib/embed.sh` JSONL ingestion loop to remove `SC2094` ambiguity while keeping line-by-line embed behavior intact.
- Run `shellcheck -x bin/ingo lib/*.sh` and iterate until clean.
- Run `bin/ingo doctor` and confirm success.
- Re-run `bin/ingo --help` and compare against baseline for exact match.
- Summarize changed lines and why each change is behavior-preserving.

## Expected File Touches
- `bin/ingo`
- `lib/embed.sh`

## Validation Commands
- `bin/ingo --help > /tmp/ingo-help.before`
- `shellcheck -x bin/ingo lib/*.sh`
- `bin/ingo doctor`
- `bin/ingo --help > /tmp/ingo-help.after`
- `diff -u /tmp/ingo-help.before /tmp/ingo-help.after`

## Acceptance Criteria
- `bin/ingo doctor` exits successfully and prints expected healthy status (`ok`).
- `shellcheck -x bin/ingo lib/*.sh` exits with zero findings.
- `bin/ingo --help` output is byte-for-byte unchanged from baseline comparison.
- Only minimal, issue-focused edits are present in the expected files.