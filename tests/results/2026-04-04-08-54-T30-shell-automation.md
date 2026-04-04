# T30 — Shell automation + exit code contract
**Date:** 2026-04-04 08:54

## Result: 32/32 pass, 0 warn, 0 fail

### Phase 1: Exit code contract
Tests that every command returns the correct exit code so scripts can branch on success/failure.
Verified: version (0), help (0), --help (0), status (0), run-no-args (1), ask-no-args (1),
unknown command (1), --context invalid path (1), --thinking empty (1).

### Phase 2: Conditional execution
Verified &&, ||, and if/then/else patterns with both success and failure cases.

### Phase 3: Pipeline and redirection
Verified command substitution (no banner bleed), --json | jq pipeline, file redirect,
and --quiet stdout cleanliness.

### Phase 4: set -e / set -o pipefail
Verified that clawbox integrates correctly with strict shell scripting modes.
set -e exits on clawbox failure; does not exit on success.
set -o pipefail propagates non-zero exit through pipelines.

### Phase 5: Scripting idioms
Verified doctor (0), task-status (0), cancel/no-task (0), GATEWAY_PORT env in script,
version machine-readability, and exit-code documentation.

### Phase 6: Source audit
Verified exit 0/1/2 paths in source, CLAWBOX_RATE_LIMITED sentinel, assert_container_running,
and assert_not_busy exit codes.

## Verdict
✅ All checks pass — exit code contract is correct for shell automation.
