## Objective
- Propose a minimal, repo-specific hardening plan for the embed pipeline lint findings so `ingo` remains a lightweight, reliable shell RAG runtime without changing CLI behavior.

## Scope In
- Fix shell lint findings in `lib/embed.sh`.
- Fix related sourcing/lint behavior in `bin/ingo`.
- Keep ingest/query runtime behavior and command contract unchanged.
- Add only small defensive edits needed to satisfy lint and reliability expectations.

## Scope Out
- No feature additions or CLI UX redesign.
- No refactor of ingest/query flow beyond lint-driven hardening.
- No changes to external APIs, index schema, or environment variable contract.
- No broad formatting/style churn across unrelated files.

## Step Checklist
- Capture baseline help output for comparison: `bin/ingo --help > /tmp/ingo-help.before`.
- Run baseline lint to identify exact failures: `shellcheck -x bin/ingo lib/*.sh`.
- Patch `lib/embed.sh` to resolve reported issues with minimal behavioral impact (quoting, local vars, command substitutions, status handling as needed).
- Patch `bin/ingo` sourcing/lint points tied to `lib/embed.sh` and shellcheck’s cross-file analysis.
- Re-run lint until clean: `shellcheck -x bin/ingo lib/*.sh`.
- Verify runtime health check: `bin/ingo doctor`.
- Verify help output is unchanged via diff against baseline.
- Review diff to ensure only intended files and minimal edits are included.

## Expected File Touches
- `lib/embed.sh`
- `bin/ingo`

## Validation Commands
- `shellcheck -x bin/ingo lib/*.sh`
- `bin/ingo doctor`
- `bin/ingo --help > /tmp/ingo-help.after`
- `diff -u /tmp/ingo-help.before /tmp/ingo-help.after`
- `git diff -- lib/embed.sh bin/ingo`

## Acceptance Criteria
- `shellcheck -x bin/ingo lib/*.sh` exits successfully with no findings.
- `bin/ingo doctor` exits successfully and reports expected healthy status (`ok`).
- `bin/ingo --help` output is byte-for-byte unchanged from baseline.
- Only minimal, targeted edits exist in `lib/embed.sh` and `bin/ingo`.
