Implemented issue `#15` per the plan, scoped to `--top-k` validation and docs only.

**Changed Files**
- `bin/ingo:34` updated global usage text to `--top-k N (integer 1-50)`.
- `bin/ingo:38` added `validate_top_k()` to enforce:
  - positive integer format via `^[1-9][0-9]*$`
  - range `1..50`
  - clear stderr errors and exit code `2` on invalid input.
- `bin/ingo:290` updated `query --help` usage text to match runtime behavior.
- `bin/ingo:312` now validates `--top-k` immediately when parsed, before query execution.
- `README.md:68` documented `--top-k` as integer `1..50`.

**Rationale**
- Fails fast on invalid CLI input before network/query logic.
- Keeps behavior explicit and predictable (reject out-of-range instead of clamping).
- Preserves numeric `topK` JSON payload for valid input paths.

**Validation Run**
- `shellcheck -S warning -x bin/ingo lib/*.sh` passed.
- `bin/ingo query "x" --top-k foo` returned exit `2` with validation error.
- `bin/ingo query "x" --top-k 0` returned exit `2` with validation error.
- `bin/ingo query --help` shows updated range text.
- Stubbed `curl` run with `--top-k 8` succeeded and captured payload had numeric `topK` (`8`, type `"number"`).