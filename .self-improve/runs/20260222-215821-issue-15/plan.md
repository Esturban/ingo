## Objective
- Propose a minimal, repo-specific fix for issue `#15` that validates `--top-k` in `bin/ingo` before query execution, fails fast with exit code `2` on invalid input, and documents the valid range/format.

## Scope In
- Add strict `--top-k` parsing/validation in `cmd_query` in `bin/ingo`.
- Enforce positive integer input only.
- Clamp to a bounded range (`1..50`) or reject out-of-range with a clear message (recommended: reject for explicitness).
- Keep JSON payload numeric (`topK` as number) for valid inputs.
- Update CLI usage/help text in `bin/ingo` and user-facing docs in `README.md`.

## Scope Out
- No changes to Upstash API behavior, `lib/query.sh` payload schema, or response formatting.
- No ingestion pipeline changes (`fetch`, `ocr`, `chunk`, `embed`, `cleanup`, `run`).
- No new test framework introduction; rely on targeted shell validation commands.
- No objective/mission rewrite for the repo.

## Step Checklist
- Inspect `cmd_query` option parsing in `bin/ingo` and add a small validator function (or inline check) for `--top-k`.
- Validate `--top-k` immediately after parsing `--top-k` value:
  - Require regex `^[1-9][0-9]*$`.
  - Enforce range bounds (`1..50`).
  - Emit clear error to stderr and `return 2` on failure.
- Update query help text from `--top-k N` to explicit format/range (for example `--top-k N (integer 1-50)`).
- Update `README.md` usage/help section to match runtime behavior.
- Run static checks (`shellcheck`) and manual CLI validations for invalid/valid paths.
- Confirm valid path still reaches payload creation with numeric `topK`.

## Expected File Touches
- `bin/ingo`
- `README.md`

## Validation Commands
- `shellcheck -S warning -x bin/ingo lib/*.sh`
- `bin/ingo query "x" --top-k foo >/tmp/ingo.err 2>&1; code=$?; echo "exit=$code"; cat /tmp/ingo.err`
- `bin/ingo query "x" --top-k 0 >/tmp/ingo.err 2>&1; code=$?; echo "exit=$code"; cat /tmp/ingo.err`
- `bin/ingo query --help`
- `tmpbin="$(mktemp -d)"; cat >"$tmpbin/curl" <<'EOF'\n#!/usr/bin/env bash\nwhile [ \"$#\" -gt 0 ]; do\n  if [ \"$1\" = \"-d\" ]; then\n    payload=\"$2\"; shift 2; continue\n  fi\n  shift\ndone\nprintf '%s\\n200\\n' '{\"result\":[]}'\nprintf '%s' \"$payload\" > /tmp/ingo.payload.json\nEOF\nchmod +x \"$tmpbin/curl\"; PATH=\"$tmpbin:$PATH\" UPSTASH_VECTOR_REST_URL=\"https://example.com\" UPSTASH_VECTOR_REST_TOKEN=\"t\" bin/ingo query \"x\" --top-k 8 >/tmp/ingo.out 2>/tmp/ingo.err; code=$?; echo \"exit=$code\"; cat /tmp/ingo.err; jq '.topK|type,.topK' /tmp/ingo.payload.json`

## Acceptance Criteria
- `bin/ingo query "x" --top-k foo` exits with code `2` and a clear validation error.
- `bin/ingo query "x" --top-k 0` exits with code `2` and a clear validation error.
- `bin/ingo query "x" --top-k 8` succeeds on the happy path and sends numeric `topK` in JSON.
- Help/usage text explicitly documents `--top-k` format and range (matching implementation).