# T21 — JSON output completeness + CLAWBOX_DIR env override
**Date:** 2026-04-03 12:56

## What was tested
- Phase 1: `clawbox run --json` produces valid, complete JSON with all documented keys
- Phase 2: `CLAWBOX_DIR` env var override behavior
- Phase 3: `clawbox task-status` and `clawbox task-logs` output format validation

## Results

| Status | Check |
|--------|-------|
| ✓ PASS | --json output is valid JSON |
| ✓ PASS | JSON has key: response (value: OK) |
| ✓ PASS | JSON has key: elapsed_ms (value: 6337) |
| ✓ PASS | JSON has key: timestamp (value: 2026-04-03T18:56:09Z) |
| ✓ PASS | JSON has key: context_files (value: 0) |
| ✓ PASS | elapsed_ms is a positive integer: 6337ms |
| ✓ PASS | timestamp is ISO-8601 format: 2026-04-03T18:56:09Z |
| ✓ PASS | context_files=0 when no --context flag |
| ✓ PASS | response field is non-empty (len=2) |
| ✓ PASS | --json + --context: context_files=1 (>0) |
| ✓ PASS | jq pipeline extraction works (response: PIPELINE_OK) |
| ✓ PASS | --json + --session: 'session' key present (value: t21-test-63700) |
| ✓ PASS | --quiet stdout has no banner (response-only): QUIET_OK |
| ✓ PASS | CLAWBOX_DIR documented in help output |
| ✓ PASS | CLAWBOX_DIR override: status command works |
| ✓ PASS | CLAWBOX_DIR=/nonexistent gives meaningful error |
| ✓ PASS | GATEWAY_PORT documented in help output |
| ✓ PASS | task-status with no task: produces output (no crash) |
| ✓ PASS | task-status output references task state or log |
| ✓ PASS | task-status output is human-readable text (not JSON) |
| ✓ PASS | task-logs with no log: graceful 'no log' message |

**21 pass, 0 warn, 0 fail** (of 21 checks)

## Key findings
- All critical checks passed
- No warnings
