## Objective
Propose a minimal, testable change for issue #15 so `bin/ingo query` validates `--top-k` early, accepts only positive integers, optionally clamps to a safe max, and returns clear exit-code-`2` errors instead of `jq`/API failures.

## Scope In
- Add strict `--top-k` parsing/validation in `bin/ingo` (`cmd_query` path).
- Enforce integer-only input and reject `<= 0`.
- Clamp valid integers above an upper bound to that bound (proposed: `50`).
- Update query help/usage text to document allowed format/range.
- Verify failure modes and JSON payload behavior with repository-local commands.

## Scope Out
- No changes to Upstash API contract or endpoint logic in `lib/query.sh`.
- No ingestion/OCR/chunk/embed behavior changes.
- No broad refactors of CLI argument parsing across unrelated commands.
- No external CI/workflow changes.

## Step Checklist
- Inspect `cmd_query` in `bin/ingo` and add a small validator helper (or inline guard) for `--top-k`.
- Parse `--top-k` before calling `ingo_query_text`, and fail with `return 2` on invalid values with a clear message (e.g., `invalid --top-k: must be a positive integer (1-50)`).
- Implement clamping rule for oversized values (e.g., `>50` becomes `50`) to prevent accidental oversized queries.
- Keep default `top_k=8` unchanged when flag is omitted.
- Update `usage()` and `query --help` text in `bin/ingo` to show required format/range.
- Update README query example/help text to match the new range semantics.
- Run targeted validation commands to confirm exit codes/messages and numeric `topK` payload serialization.

## Expected File Touches
- `bin/ingo`
- `README.md`

## Validation Commands
- `bin/ingo query "x" --top-k foo >/tmp/ingo_topk_foo.out 2>&1; code=$?; printf 'code=%s\n' "$code"; cat /tmp/ingo_topk_foo.out`
- `bin/ingo query "x" --top-k 0 >/tmp/ingo_topk_zero.out 2>&1; code=$?; printf 'code=%s\n' "$code"; cat /tmp/ingo_topk_zero.out`
- `tmp="$(mktemp -d)"; cat >"$tmp/curl" <<'EOF'\n#!/usr/bin/env bash\npayload=\"\"\nwhile [ \"$#\" -gt 0 ]; do\n  if [ \"$1\" = \"-d\" ]; then payload=\"$2\"; shift 2; continue; fi\n  shift\ndone\nprintf '%s' \"$payload\" > \"$TMP_CAPTURE/payload.json\"\nprintf '{\"result\":[]}'\nprintf '\\n200'\nEOF\nchmod +x \"$tmp/curl\"; TMP_CAPTURE=\"$tmp\" PATH=\"$tmp:$PATH\" UPSTASH_VECTOR_REST_URL=\"https://example.test\" UPSTASH_VECTOR_REST_TOKEN=\"test\" bin/ingo query \"x\" --top-k 8 >/tmp/ingo_topk_ok.out 2>&1; jq -e '.topK == 8 and (.topK|type==\"number\")' \"$tmp/payload.json\"; echo \"payload_ok=$?\"`
- `tmp="$(mktemp -d)"; cat >"$tmp/curl" <<'EOF'\n#!/usr/bin/env bash\npayload=\"\"\nwhile [ \"$#\" -gt 0 ]; do\n  if [ \"$1\" = \"-d\" ]; then payload=\"$2\"; shift 2; continue; fi\n  shift\ndone\nprintf '%s' \"$payload\" > \"$TMP_CAPTURE/payload.json\"\nprintf '{\"result\":[]}'\nprintf '\\n200'\nEOF\nchmod +x \"$tmp/curl\"; TMP_CAPTURE=\"$tmp\" PATH=\"$tmp:$PATH\" UPSTASH_VECTOR_REST_URL=\"https://example.test\" UPSTASH_VECTOR_REST_TOKEN=\"test\" bin/ingo query \"x\" --top-k 999 >/tmp/ingo_topk_clamp.out 2>&1; jq -e '.topK == 50 and (.topK|type==\"number\")' \"$tmp/payload.json\"; echo \"clamp_ok=$?\"`

## Acceptance Criteria
- `bin/ingo query "x" --top-k foo` exits with code `2` and a clear validation error.
- `bin/ingo query "x" --top-k 0` exits with code `2` and a clear validation error.
- `bin/ingo query "x" --top-k 8` proceeds and sends numeric `topK` in JSON payload.
- Oversized valid integer values are clamped to the documented max (proposed `50`) before request build.
- Help/usage text clearly documents valid `--top-k` format/range.