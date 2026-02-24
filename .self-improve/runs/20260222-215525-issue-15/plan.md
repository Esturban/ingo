## Objective
- Plan a minimal, repo-specific fix for issue `#15` so `bin/ingo query` validates `--top-k` early, fails fast on invalid input with exit code `2`, and only sends numeric `topK` values to `/query-data`.

## Scope In
- Add strict `--top-k` validation in `cmd_query` inside `bin/ingo`.
- Enforce positive integer input for `--top-k`.
- Clamp valid numeric input to a bounded max (proposed `50`) with documented behavior.
- Update CLI usage/help text to state valid `--top-k` format/range.
- Verify behavior with concrete command checks (invalid string, zero, valid integer).

## Scope Out
- No changes to ingestion flow (`fetch/ocr/chunk/embed/cleanup`).
- No API contract changes in `lib/query.sh` request schema beyond ensuring `topK` receives a validated numeric value.
- No new external dependencies or major refactors.
- No broad UX redesign of CLI help beyond `query --top-k` wording.

## Step Checklist
- [ ] Confirm current `cmd_query` option parsing path in `bin/ingo` and identify insertion point right after `--top-k` assignment.
- [ ] Implement a small validator in `bin/ingo` (inline or helper) that:
  - [ ] accepts only `^[0-9]+$`
  - [ ] rejects `0`
  - [ ] rejects negatives/decimals/non-numeric values
  - [ ] returns exit code `2` with a clear message.
- [ ] Add clamp logic to cap `top_k` to `50` (or chosen upper bound), keeping default `8`.
- [ ] Update usage/help strings in `usage()` and `cmd_query --help` to document valid format/range (e.g. `1-50`).
- [ ] Run static/smoke checks and record outputs for the issue acceptance cases.

## Expected File Touches
- `bin/ingo`
  - Add `--top-k` validation and clamp in `cmd_query`.
  - Update query usage/help text to include valid range/format.
- `README.md`
  - Update query usage note to reflect `--top-k` valid range (if maintained as user-facing CLI contract documentation).

## Validation Commands
- `shellcheck -S warning -x bin/ingo lib/*.sh`
- `bin/ingo query "x" --top-k foo; echo "exit=$?"`
- `bin/ingo query "x" --top-k 0; echo "exit=$?"`
- `bin/ingo query --help`
- `bin/ingo query "x" --top-k 8`  
  (with valid env set; confirm request path succeeds and no jq `--argjson` error)
- Optional clamp check:
  - `bin/ingo query "x" --top-k 999`  
  (confirm behavior matches documented clamp policy, e.g. uses `50`)

## Acceptance Criteria
- `bin/ingo query "x" --top-k foo` exits `2` with a clear validation error mentioning expected positive integer/range.
- `bin/ingo query "x" --top-k 0` exits `2` with the same class of validation error.
- `bin/ingo query "x" --top-k 8` proceeds normally and sends numeric `topK` in JSON payload.
- `bin/ingo query --help` and top-level `usage` text clearly document valid `--top-k` input (format and range, including clamp behavior if enabled).