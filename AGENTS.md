# ingo Agent Harness

Read this file before editing code in this repo.

## Mission

`ingo` is a shell-first ingest and retrieval harness. Treat the vector layer as a narrow backend boundary, not as an Upstash-specific app.

## Repository Shape

- CLI entrypoint: `bin/ingo`
- Shared runtime defaults: `lib/env.sh`
- Vector backend dispatch: `lib/vector.sh`
- Backend adapters: `lib/vector/upstash.sh`, `lib/vector/pinecone.sh`, `lib/vector/qdrant.sh`
- Contract tests: `tests/vector_backend_contract_test.sh` plus adapter-specific tests

## Rules

- Keep the public CLI stable unless the task explicitly requires a surface change.
- New vector provider work must go through `lib/vector.sh`; do not leak backend branches back into `bin/ingo`.
- Preserve the normalized query contract:
  - top-level `match_count`
  - `matches[]` with `id`, `score`, `text`, `source`, `section`, `article`
- Prefer generic env names first:
  - `INGO_VECTOR_BACKEND`
  - `INGO_VECTOR_URL`
  - `INGO_VECTOR_TOKEN`
- Preserve legacy Upstash aliases unless the task explicitly removes backward compatibility.
- Keep the runtime shell-native: `curl`, `jq`, and small focused helpers over larger framework rewrites.

## Harness Context

- `CLAUDE.md` should remain a thin pointer, not a second source of truth.
- `.wolf/OPENWOLF.md` and `.claude/rules/openwolf.md` are local tool overlays. Keep repo instructions here in `AGENTS.md`; keep tool-specific behavior there.

## Verification

For vector-layer changes, run at least:

- `bash tests/vector_backend_contract_test.sh`
- `bash tests/pinecone_adapter_test.sh`
- `bash tests/qdrant_adapter_test.sh`

## Done-gate (no "done" on intent — only on evidence)
- Not done until acceptance criteria met AND shown. Saying done without proof = not done.
- Acceptance source: `.acceptance` (one check per line) if present, else the task / PRD / spec criteria.
- Survives context loss: re-read the acceptance source after `/clear` or a crash. Never trust remembered progress — verify against the file.
- Each check must pass: command exits 0, or criterion demonstrably true. One unmet => not done; report which + why, then halt.
- Don't move the goalposts to pass. Unmeetable / wrong criterion => surface to the user; never silently drop it.


## Model routing
Route by task type (policy: rules/_meta.yaml). Pick the cheapest tier that fits.
- default -> sonnet
- security -> opus
- review -> sonnet
- test -> sonnet
- deploy -> sonnet
- architecture -> opus
- refactor -> haiku
- hooks -> haiku
- laravel -> sonnet
- nextjs -> sonnet
- python -> sonnet
- web -> sonnet
- performance -> sonnet

## Anti-patterns
- Pre-merge / anti-pattern audit => `anti-patterns-auditor`

## Commit hygiene (nothing goes in that doesn't need to be there)
- Never commit secrets/credentials: API keys, `.env` (non-example), private keys, tokens. Scan before staging.
- Never commit PII or scraped personal-data dumps: contact-list exports, raw email/CSV exports, address/phone data. Redact an incidental PII string inside real code (e.g. a test fixture) rather than deleting the whole file; untrack + gitignore dedicated data-dump files instead.
- Never commit AI-IDE scaffolding as if it were project work: `.cursor/`, `.cursorrules`, `.cursorignore`, `.clinerules`, `.windsurfrules`, `.roo*`, `memory-bank/`, `.github/copilot-instructions.md`, `*.code-workspace`. Untrack + gitignore if found; leave the files on disk.
- `.wolf/` (OpenWolf) state is legitimate operational memory, not scaffolding -- never touch it under this rule.
- Public repos: never commit `AGENTS.md` itself -- gitignore it instead. Private repos: commit it normally.


## CI/CD (dev -> trunk auto-PR)
- Every repo with real remote work gets `.github/workflows/dev-to-trunk.yml` (source: `templates/ci-cd/dev-to-trunk-auto-pr.yml`): push to `dev` auto-opens/refreshes a PR into the repo's default branch (`main`/`master`, auto-detected), owner requested as reviewer.
- PRs are opened ONLY by this Action -- never `gh pr create` run by a human or an agent.
- New repos: wire this Action in during harness mint. Existing repos: retrofit it alongside the AGENTS.md organ injector.
