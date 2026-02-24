Implemented issue `#15` per the plan, scoped to `query --top-k` validation and docs only.

**Changed Files**
1. `bin/ingo:34`
- Updated top-level usage to document `--top-k` contract: positive integer `1-50`, clamp above `50`.

2. `bin/ingo:276`
- Added strict `--top-k` handling in `cmd_query`:
  - Accepts only `^[0-9]+$`.
  - Rejects `0` with exit code `2`.
  - Rejects non-numeric/decimal/negative inputs with exit code `2`.
  - Clamps values `>50` to `50` with a clear stderr message.
- Validation now runs before env/bin checks so invalid input fails fast.

3. `bin/ingo:279`
- Updated `ingo query --help` text to explicitly document valid range and clamp behavior.

4. `README.md:68`
- Added user-facing note matching runtime behavior: `--top-k` must be positive integer, valid range `1-50`, clamp above `50`.

**Why**
- Prevents invalid values from reaching `jq --argjson` and `/query-data`.
- Ensures deterministic CLI contract and fast, clear failures (`exit 2`) for bad input.
- Keeps API payload numeric for `topK` without changing request schema.

**Validation Run**
1. `shellcheck -S warning -x bin/ingo lib/*.sh` passed.
2. `bin/ingo query "x" --top-k foo` → `invalid --top-k...` and `exit=2`.
3. `bin/ingo query "x" --top-k 0` → `invalid --top-k...` and `exit=2`.
4. `bin/ingo query --help` shows `1-50` and clamp behavior.
5. `bin/ingo query "x" --top-k 8` succeeded (`exit=0`, `match_count=8`).
6. Optional clamp check: `bin/ingo query "x" --top-k 999` prints clamp message and succeeds with clamped result size (`50`).