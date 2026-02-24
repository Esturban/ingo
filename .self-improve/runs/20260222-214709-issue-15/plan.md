## Objective
- Plan a minimal fix for issue #15 so `bin/ingo query` validates `--top-k` early, fails clearly with exit code `2` on invalid input, and only sends a numeric `topK` to `/query-data`.

## Scope In
- Add `--top-k` validation logic in `cmd_query` in `bin/ingo`.
- Enforce positive integer format (no floats, signs, text, empty).
- Clamp accepted value to a documented upper bound (proposed: `1..50`).
- Ensure invalid `--top-k` errors are explicit and return exit code `2`.
- Update CLI usage/help text to document valid `--top-k` range.
- Update README usage note for `query --top-k`.

## Scope Out
- No changes to ingestion pipeline (`fetch/ocr/chunk/embed/cleanup`).
- No API contract changes in `lib/query.sh` beyond relying on validated numeric input from CLI.
- No refactor of global argument parsing or command dispatch.
- No network/service reliability changes outside input validation.

## Step Checklist
- Inspect `cmd_query` parsing in `bin/ingo` and define constants for bounds (`TOP_K_MIN=1`, `TOP_K_MAX=50`) local to query command.
- Add a small validator helper in `bin/ingo` (or inline guard) that:
  - Rejects non-digits (`foo`, `1.5`, `-1`, empty).
  - Rejects `< 1`.
  - Clamps values `> 50` down to `50` (if clamping path is chosen).
- Keep failure mode consistent:
  - Print clear message to `stderr` (example: `invalid --top-k: must be an integer between 1 and 50`).
  - Return `2`.
- Update `usage()` and `cmd_query --help` text to explicitly show accepted format/range.
- Update `README.md` query usage/help text to mirror CLI behavior.
- Run syntax and behavior checks (including exit codes).
- Verify a valid call sends numeric `topK` in JSON payload via a mocked `curl` capture.

## Expected File Touches
- `bin/ingo`
- `README.md`

## Validation Commands
- `bash -n bin/ingo`
- `bin/ingo query "x" --top-k foo >/tmp/ingo.out 2>/tmp/ingo.err; echo $?`
- `bin/ingo query "x" --top-k 0 >/tmp/ingo.out 2>/tmp/ingo.err; echo $?`
- `bin/ingo query --help`
- `bin/ingo --help`
- `tmpdir="$(mktemp -d)"; cat >"$tmpdir/curl" <<'SH'\n#!/usr/bin/env bash\nprintf '%s' \"$*\" >\"$tmpdir/curl.args\"\nwhile [ \"$#\" -gt 0 ]; do\n  if [ \"$1\" = \"-d\" ]; then\n    shift\n    printf '%s' \"$1\" >\"$tmpdir/payload.json\"\n    break\n  fi\n  shift\ndone\nprintf '{\"result\":[]}'\nprintf '\\n200'\nSH\nchmod +x \"$tmpdir/curl\"; PATH=\"$tmpdir:$PATH\" UPSTASH_VECTOR_REST_URL=\"https://example.test\" UPSTASH_VECTOR_REST_TOKEN=\"token\" INGO_NAMESPACE=\"ns\" bin/ingo query \"x\" --top-k 8 >/tmp/ingo.query.out; jq '.topK|type,.topK' \"$tmpdir/payload.json\"; rm -rf \"$tmpdir\"`
- `tmpdir="$(mktemp -d)"; cat >"$tmpdir/curl" <<'SH'\n#!/usr/bin/env bash\nwhile [ \"$#\" -gt 0 ]; do\n  if [ \"$1\" = \"-d\" ]; then\n    shift\n    printf '%s' \"$1\" >\"$tmpdir/payload.json\"\n    break\n  fi\n  shift\ndone\nprintf '{\"result\":[]}'\nprintf '\\n200'\nSH\nchmod +x \"$tmpdir/curl\"; PATH=\"$tmpdir:$PATH\" UPSTASH_VECTOR_REST_URL=\"https://example.test\" UPSTASH_VECTOR_REST_TOKEN=\"token\" INGO_NAMESPACE=\"ns\" bin/ingo query \"x\" --top-k 999 >/tmp/ingo.query.out; jq '.topK' \"$tmpdir/payload.json\"; rm -rf \"$tmpdir\"`

## Acceptance Criteria
- `bin/ingo query "x" --top-k foo` exits with code `2` and prints a clear validation error.
- `bin/ingo query "x" --top-k 0` exits with code `2` and prints a clear validation error.
- `bin/ingo query "x" --top-k 8` proceeds and payload contains numeric JSON `topK` (type `number`, value `8`).
- If clamping is implemented, oversized input (for example `999`) sends `topK: 50` and is documented.
- Help/usage output documents `--top-k` format/range consistently in `bin/ingo` and `README.md`.