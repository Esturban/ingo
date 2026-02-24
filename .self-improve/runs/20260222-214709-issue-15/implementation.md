Implemented issue `#15` per the plan, scoped to `query --top-k` validation and docs.

Changed files and rationale:

- `bin/ingo:34`
  - Updated top-level usage text to document `--top-k` range and clamping behavior.
- `bin/ingo:38`
  - Added `ingo_validate_top_k()` to enforce:
    - digits-only integer input
    - minimum bound (`1`)
    - clear stderr error on invalid input
    - exit code `2` on validation failure
    - clamp values above max to `50`
- `bin/ingo:296`
  - In `cmd_query`, defined local bounds (`TOP_K_MIN=1`, `TOP_K_MAX=50`), expanded `query --help` text, and applied validation before calling `ingo_query_text`.
  - This ensures only numeric `topK` reaches `/query-data`.
- `README.md:68`
  - Added query note documenting `--top-k` must be `1..50` and that values over `50` are clamped.

Validation run:

- `bash -n bin/ingo` passed.
- `bin/ingo query "x" --top-k foo` returned exit code `2` with:
  - `invalid --top-k: must be an integer between 1 and 50`
- `bin/ingo query "x" --top-k 0` returned exit code `2` with same message.
- Mocked `curl` payload checks:
  - `--top-k 8` produced JSON numeric `topK` (`type: "number"`, value `8`).
  - `--top-k 999` produced `topK: 50` (clamped).

No staging or commits were performed.