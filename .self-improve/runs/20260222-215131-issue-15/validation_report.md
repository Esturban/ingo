# Validation Report
- mode: strict
- full_pass: true
- allow_commit: true
- allow_pr: true
- allow_issue_close: true

## Verification Commands
- [PASS] bin/ingo doctor (rc=0)
- [PASS] shellcheck -S warning -x bin/ingo lib/*.sh (rc=0)

## Coverage
- changed_files: 114
- missing_expected_touches: 0
- uncovered_steps: 0

## Review Findings
- total_findings: 0
- p0: 0, p1: 0, p2: 0, p3: 0

## Failure Reasons
- none
