Implemented issue #13 per the plan with scoped edits to exactly two files.

Changed files and rationale:

- `bin/ingo`
  - Updated only `# shellcheck source=...` annotations from `../lib/...` to `lib/...`.
  - Reason: fixes `SC1091` resolution under `shellcheck -x` from repo root without affecting runtime sourcing (`source "$ROOT_DIR/lib/..."` is unchanged).

- `lib/embed.sh`
  - In `ingo_embed_jsonl`, changed the read loop from `done < "$jsonl"` to an explicit FD pattern:
    - `exec 3< "$jsonl"`
    - `while ... read ... <&3; do ... done`
    - `exec 3<&-`
  - Added `local line`.
  - Reason: removes `SC2094` false-positive risk around read/write ambiguity while preserving embed behavior and output.

Validation results:

- `shellcheck -x bin/ingo lib/*.sh` -> exit `0`, no findings.
- `bin/ingo doctor` -> prints `ok`, exit `0`.
- `bin/ingo --help` before/after diff -> identical (`diff` exit `0`, same byte count).
- `git diff -- bin/ingo lib/embed.sh` shows only the intended minimal changes.

No staging/commits performed, and no `.self-improve/runs` artifacts were modified.