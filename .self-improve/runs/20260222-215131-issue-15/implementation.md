Implemented issue `#15` per the plan, scoped to `bin/ingo` and `README.md`.

**Changed Files**
- `bin/ingo:22`  
  Updated CLI usage text to document `--top-k` semantics (`1-50`, clamp above max).
- `bin/ingo:39`  
  Added `INGO_QUERY_TOP_K_MAX=50` and new helper `ingo_validate_top_k()`:
  - accepts only digits
  - rejects `<= 0`
  - returns exit code `2` with clear error: `invalid --top-k: must be a positive integer (1-50)`
  - clamps values `>50` to `50`
- `bin/ingo:295`  
  Updated `query --help` output to include the same rules.
- `bin/ingo:319`  
  Wired validation into `cmd_query` before calling `ingo_query_text`.
- `README.md:68`  
  Documented `--top-k` validation/clamping behavior to match CLI.

**Validation Run**
- `bin/ingo query "x" --top-k foo` -> `code=2`, error message as expected.
- `bin/ingo query "x" --top-k 0` -> `code=2`, error message as expected.
- Mocked `curl` payload test with `--top-k 8` confirmed JSON has numeric `topK: 8`.
- Mocked `curl` payload test with `--top-k 999` confirmed clamped numeric `topK: 50`.

No staging/commits were performed, and no `.self-improve/runs` artifacts were edited.