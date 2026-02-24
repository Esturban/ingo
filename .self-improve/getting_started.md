# Getting Started for ingo

This file is required by the self-improvement runtime.

## Repository Context
- repo_id: `ingo`
- github_repo: `Esturban/ingo`
- default_branch: `master`
- integration_branch: `dev`

## Objective
Ship a lightweight, reliable shell RAG runtime for fast agent querying over indexed documents.

## First-Time Setup
```bash
# No bootstrap required/configured for this repo.
```

## Validation Commands
- `bin/ingo doctor`
- `shellcheck -x bin/ingo lib/*.sh`

## One-Shot Run Template
```bash
./scripts/ralph_oneshot.sh run \
  --repo-id ingo \
  --issue <N> \
  --plan-effort medium \
  --review-effort medium \
  --validation-mode strict \
  --max-plan-attempts 2 \
  --max-repair-iterations 1
```

## Notes
- Keep issue scope repo-specific.
- One issue per run to reduce risk.
- Branch flow: feature -> `dev` -> `master`.
