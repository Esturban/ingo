Implemented issue `#13` per the plan, with scoped changes only in the expected files.

Changed files and rationale:

- `bin/ingo:7`  
  Updated all `shellcheck source=...` hints from `../lib/...` to `lib/...` so `shellcheck -x` resolves sourced files correctly when run from repo root.  
  Runtime `source "$ROOT_DIR/lib/...` lines are unchanged, so CLI behavior is preserved.

- `lib/embed.sh:84`  
  Precomputed `meta_file` once before the loop and switched the JSONL read loop to explicit FD redirection (`read ... <&3` with `done 3< "$jsonl"`).  
  This removes `SC2094` ambiguity while keeping the same line-by-line upsert/count behavior.

Validation run results:

- `shellcheck -x bin/ingo lib/*.sh` → clean (exit 0)
- `bin/ingo doctor` → `ok`
- `bin/ingo --help` before/after diff (`/tmp/ingo-help.before` vs `/tmp/ingo-help.after`) → no differences

No `.self-improve/runs` artifacts were edited, and nothing was staged or committed.