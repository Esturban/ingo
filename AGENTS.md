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
