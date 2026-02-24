# Validation Report
- mode: strict
- full_pass: false
- allow_commit: false
- allow_pr: false
- allow_issue_close: false

## Verification Commands
- [PASS] bin/ingo doctor (rc=0)
- [PASS] shellcheck -S warning -x bin/ingo lib/*.sh (rc=0)

## Coverage
- changed_files: 143
- missing_expected_touches: 2
- uncovered_steps: 0

## Review Findings
- total_findings: 0
- p0: 0, p1: 0, p2: 0, p3: 0

## Failure Reasons
- missing expected file touches
