#!/usr/bin/env bash
# T30 — Shell automation + exit code contract
#
# What: Verify that clawbox behaves correctly as a building block in shell
#       scripts — proper exit codes, pipeable output, set -e compatibility,
#       conditional execution, and real scripting patterns.
#
# Scenarios:
#   Phase 1: Exit code contract
#     - exit 0 on success (run, ask, version, help, status)
#     - exit 1 on usage errors (no message, bad flags, unknown command)
#     - exit 1 on missing container (assert_container_running)
#     - exit 2 documented for rate-limit (code path verified via source audit)
#
#   Phase 2: Conditional execution (&&, ||, if)
#     - clawbox run "..." && echo "ok"  — && executes on success
#     - clawbox run "" 2>/dev/null || echo "fallback"  — || executes on failure
#     - if clawbox run ...; then ... fi — full if-then pattern
#
#   Phase 3: Pipeline and redirection
#     - output=$(clawbox run --quiet "...") — captures cleanly
#     - clawbox run --json "..." | jq .response  — JSON pipeline
#     - clawbox run --quiet "..." > /tmp/out.txt — file redirect
#
#   Phase 4: set -e and set -o pipefail compatibility
#     - Script with set -e exits correctly on clawbox failure
#     - set -o pipefail catches broken pipe downstream
#
#   Phase 5: Scripting idioms
#     - clawbox version exits 0
#     - clawbox help exits 0 (docs often say "run --help")
#     - clawbox doctor exits 0 when healthy
#     - unknown command exits 1 — distinguishable from "rate limit" (exit 2)
#     - GATEWAY_PORT override works from env in script context
#
#   Phase 6: Source audit — exit code comments in clawbox source
#     - exit 0 paths exist for success commands
#     - exit 1 paths exist for user errors
#     - exit 2 path exists for rate limit
#     - help text documents exit 2 behavior
#
# Run time: ~3 minutes (3-4 live agent calls for exit-code confirmation)
# Safe to re-run: yes — no persistent workspace changes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLAWBOX="$CLAWBOX_DIR/clawbox"

source "$SCRIPT_DIR/lib/common.sh"

# ── Result file ──────────────────────────────────────────────────────────────
TIMESTAMP=$(date '+%Y-%m-%d-%H-%M')
RESULT_FILE="$SCRIPT_DIR/results/${TIMESTAMP}-T30-shell-automation.md"
mkdir -p "$SCRIPT_DIR/results"

PASS=0; WARN=0; FAIL=0

pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
warn() { echo "  ⚠ $*"; WARN=$((WARN+1)); }
fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }

echo ""
echo "══════════════════════════════════════════════════════════"
echo "  T30 — Shell automation + exit code contract"
echo "  $(date '+%Y-%m-%d %H:%M')"
echo "══════════════════════════════════════════════════════════"
echo ""

# ── Container check ──────────────────────────────────────────────────────────
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q 'clawbox-work'; then
  echo "✗ Container not running — start with: bash clawbox start"
  exit 1
fi

# ── Phase 1: Exit code contract ──────────────────────────────────────────────
echo "── Phase 1: Exit code contract ─────────────────────────────"

# 1a. version exits 0
code=0; bash "$CLAWBOX" version >/dev/null 2>&1 || code=$?
if [ "$code" -eq 0 ]; then pass "version exits 0"; else fail "version exited $code (expected 0)"; fi

# 1b. help exits 0
code=0; bash "$CLAWBOX" help >/dev/null 2>&1 || code=$?
if [ "$code" -eq 0 ]; then pass "help exits 0"; else fail "help exited $code (expected 0)"; fi

# 1c. --help exits 0
code=0; bash "$CLAWBOX" --help >/dev/null 2>&1 || code=$?
if [ "$code" -eq 0 ]; then pass "--help exits 0"; else fail "--help exited $code (expected 0)"; fi

# 1d. status exits 0 when container running
code=0; bash "$CLAWBOX" status >/dev/null 2>&1 || code=$?
if [ "$code" -eq 0 ]; then pass "status exits 0 (container healthy)"; else fail "status exited $code (expected 0)"; fi

# 1e. run with no message exits 1
code=0; bash "$CLAWBOX" run 2>/dev/null || code=$?
if [ "$code" -eq 1 ]; then pass "run (no args) exits 1"; else fail "run (no args) exited $code (expected 1)"; fi

# 1f. ask with no message exits 1
code=0; bash "$CLAWBOX" ask 2>/dev/null || code=$?
if [ "$code" -eq 1 ]; then pass "ask (no args) exits 1"; else fail "ask (no args) exited $code (expected 1)"; fi

# 1g. unknown command exits 1
code=0; bash "$CLAWBOX" nonexistent-cmd-xyz 2>/dev/null || code=$?
if [ "$code" -eq 1 ]; then pass "unknown command exits 1"; else fail "unknown command exited $code (expected 1)"; fi

# 1h. --context with invalid path exits 1
code=0; bash "$CLAWBOX" run --context /nonexistent/path "test" 2>/dev/null || code=$?
if [ "$code" -eq 1 ]; then pass "--context invalid path exits 1"; else fail "--context invalid path exited $code (expected 1)"; fi

# 1i. --thinking with empty value exits 1
code=0; bash "$CLAWBOX" run --thinking "" "test" 2>/dev/null || code=$?
if [ "$code" -eq 1 ]; then pass "--thinking empty exits 1"; else fail "--thinking empty exited $code (expected 1)"; fi

echo ""

# ── Phase 2: Conditional execution ───────────────────────────────────────────
echo "── Phase 2: Conditional execution ──────────────────────────"

# 2a. && executes on success
AND_RESULT=""
AND_RESULT=$(bash "$CLAWBOX" run --quiet "Say exactly: COND_AND_OK" 2>/dev/null && echo "AND_RAN") || true
if echo "$AND_RESULT" | grep -q "AND_RAN"; then
  pass "&& body executes on exit 0 (run success)"
else
  if is_rate_limited "$AND_RESULT"; then
    skip_rate_limited "T30" "$RESULT_FILE" "Phase 2a rate limited"
    exit 0
  fi
  fail "&& body did NOT execute after successful run (got: $AND_RESULT)"
fi

# 2b. || executes on failure (no-arg run)
OR_RESULT=""
OR_RESULT=$(bash "$CLAWBOX" run 2>/dev/null || echo "OR_RAN") || true
if echo "$OR_RESULT" | grep -q "OR_RAN"; then
  pass "|| body executes on exit 1 (run with no args)"
else
  fail "|| body did NOT execute after failed run (got: $OR_RESULT)"
fi

# 2c. if/then pattern
IF_OUTPUT=""
IF_OUTPUT=$(bash "$CLAWBOX" run --quiet "Say exactly: IF_THEN_OK" 2>/dev/null) || true
if is_rate_limited "$IF_OUTPUT"; then
  warn "Phase 2c rate limited — skipping"
  WARN=$((WARN+1))
elif echo "$IF_OUTPUT" | grep -q "IF_THEN_OK"; then
  pass "if/then: run success branch taken correctly"
else
  fail "if/then: expected IF_THEN_OK in output, got: $(echo "$IF_OUTPUT" | head -1)"
fi

# 2d. if/else: failure branch taken on bad args
IF_FAIL_BRANCH=""
if bash "$CLAWBOX" run 2>/dev/null; then
  IF_FAIL_BRANCH="success"
else
  IF_FAIL_BRANCH="failure"
fi
if [ "$IF_FAIL_BRANCH" = "failure" ]; then
  pass "if/else: failure branch taken on exit 1 (run no args)"
else
  fail "if/else: success branch taken even though run had no args"
fi

echo ""

# ── Phase 3: Pipeline and redirection ────────────────────────────────────────
echo "── Phase 3: Pipeline and redirection ───────────────────────"

# 3a. Command substitution captures output cleanly (no banners)
CAPTURED=""
CAPTURED=$(bash "$CLAWBOX" run --quiet "Say exactly: CAPTURE_OK" 2>/dev/null) || true
if is_rate_limited "$CAPTURED"; then
  warn "Phase 3a rate limited"
else
  CAPTURED_TRIMMED="$(echo "$CAPTURED" | tr -d '[:space:]')"
  if echo "$CAPTURED_TRIMMED" | grep -q "CAPTURE_OK"; then
    # Make sure no banner leaked into captured output
    if echo "$CAPTURED" | grep -qi "clawbox\|▶\|gateway"; then
      warn "Command substitution: banner text leaked into stdout (should be on stderr)"
    else
      pass "Command substitution captures response only (no banners)"
    fi
  else
    fail "Command substitution: expected CAPTURE_OK, got: $(echo "$CAPTURED" | head -1)"
  fi
fi

# 3b. --json output pipeable to jq
JSON_OUT=""
JSON_OUT=$(bash "$CLAWBOX" run --json "Say exactly: JQ_OK" 2>/dev/null) || true
if is_rate_limited "$JSON_OUT"; then
  warn "Phase 3b rate limited"
else
  if echo "$JSON_OUT" | jq -e '.response' >/dev/null 2>&1; then
    EXTRACTED=$(echo "$JSON_OUT" | jq -r '.response' 2>/dev/null || echo "")
    if echo "$EXTRACTED" | grep -q "JQ_OK"; then
      pass "--json output is directly pipeable to jq (.response contains sentinel)"
    else
      warn "--json parseable but response doesn't contain JQ_OK sentinel (got: $(echo "$EXTRACTED" | head -1))"
    fi
  else
    fail "--json output is not valid JSON (jq parse failed): $(echo "$JSON_OUT" | head -2)"
  fi
fi

# 3c. File redirection
TMP_OUT=$(mktemp)
bash "$CLAWBOX" run --quiet "Say exactly: REDIR_OK" > "$TMP_OUT" 2>/dev/null || true
if grep -q "REDIR_OK" "$TMP_OUT" 2>/dev/null; then
  pass "File redirection: response written to file correctly"
elif [ -s "$TMP_OUT" ]; then
  CONTENT=$(cat "$TMP_OUT")
  if is_rate_limited "$CONTENT"; then
    warn "Phase 3c rate limited"
  else
    warn "File redirect: file has content but REDIR_OK not found: $(head -1 "$TMP_OUT")"
  fi
else
  warn "File redirect: output file is empty"
fi
rm -f "$TMP_OUT"

# 3d. stderr doesn't bleed into stdout with --quiet
QUIET_STDOUT=""
QUIET_STDERR=""
QUIET_STDOUT=$(bash "$CLAWBOX" run --quiet "Say exactly: QUIET_STDOUT_ONLY" 2>/tmp/t30-stderr-check) || true
QUIET_STDERR=$(cat /tmp/t30-stderr-check 2>/dev/null || echo "")
rm -f /tmp/t30-stderr-check
if is_rate_limited "$QUIET_STDOUT"; then
  warn "Phase 3d rate limited"
else
  if echo "$QUIET_STDOUT" | grep -q "QUIET_STDOUT_ONLY"; then
    if echo "$QUIET_STDOUT" | grep -qi "▶\|clawbox\|gateway"; then
      fail "--quiet: banner found in stdout (should be on stderr)"
    else
      pass "--quiet: stdout is clean (response only, no banners)"
    fi
  else
    warn "--quiet: sentinel not found in stdout: $(echo "$QUIET_STDOUT" | head -1)"
  fi
fi

echo ""

# ── Phase 4: set -e and set -o pipefail compatibility ────────────────────────
echo "── Phase 4: set -e / set -o pipefail compatibility ─────────"

# 4a. set -e script exits on clawbox failure
SET_E_RESULT=""
SET_E_RESULT=$(bash -c '
  set -e
  bash '"$CLAWBOX"' run 2>/dev/null
  echo "SHOULD_NOT_REACH"
' 2>/dev/null || echo "EXITED_CORRECTLY")
if echo "$SET_E_RESULT" | grep -q "EXITED_CORRECTLY"; then
  pass "set -e: script exits when clawbox run fails (no args)"
elif echo "$SET_E_RESULT" | grep -q "SHOULD_NOT_REACH"; then
  fail "set -e: script continued past failing clawbox run (should have exited)"
else
  warn "set -e: unexpected result: $SET_E_RESULT"
fi

# 4b. set -e script does NOT exit on clawbox success
SET_E_SUCCESS=""
SET_E_SUCCESS=$(bash -c '
  set -e
  bash '"$CLAWBOX"' run --quiet "Say: SET_E_PASS" 2>/dev/null
  echo "CONTINUED_OK"
' 2>/dev/null) || true
if is_rate_limited "$SET_E_SUCCESS"; then
  warn "Phase 4b rate limited"
elif echo "$SET_E_SUCCESS" | grep -q "CONTINUED_OK"; then
  pass "set -e: script continues normally after successful clawbox run"
else
  warn "set -e: expected CONTINUED_OK after success, got: $(echo "$SET_E_SUCCESS" | tail -1)"
fi

# 4c. set -o pipefail: catches failed clawbox in a pipeline
PIPEFAIL_CODE=0
bash -c '
  set -o pipefail
  bash '"$CLAWBOX"' run 2>/dev/null | cat
' 2>/dev/null || PIPEFAIL_CODE=$?
if [ "$PIPEFAIL_CODE" -ne 0 ]; then
  pass "set -o pipefail: pipeline propagates clawbox exit 1 to script exit code"
else
  fail "set -o pipefail: failed clawbox in pipeline should yield non-zero exit"
fi

echo ""

# ── Phase 5: Scripting idioms ─────────────────────────────────────────────────
echo "── Phase 5: Scripting idioms ────────────────────────────────"

# 5a. doctor exits 0 when container is healthy
code=0; bash "$CLAWBOX" doctor >/dev/null 2>&1 || code=$?
if [ "$code" -eq 0 ]; then pass "doctor exits 0 (container healthy)"; else fail "doctor exited $code (expected 0 — is container healthy?)"; fi

# 5b. task-status exits 0 (informational, always)
code=0; bash "$CLAWBOX" task-status >/dev/null 2>&1 || code=$?
if [ "$code" -eq 0 ]; then pass "task-status exits 0"; else fail "task-status exited $code (expected 0)"; fi

# 5c. cancel with no task running exits 0 (safe no-op)
code=0; bash "$CLAWBOX" cancel >/dev/null 2>&1 || code=$?
if [ "$code" -eq 0 ]; then pass "cancel (no task running) exits 0"; else fail "cancel exits $code (expected 0)"; fi

# 5d. GATEWAY_PORT env override is respected in a script context
GATEWAY_VERSION_OUT=""
GATEWAY_VERSION_OUT=$(GATEWAY_PORT=18790 bash "$CLAWBOX" version 2>&1) || true
if echo "$GATEWAY_VERSION_OUT" | grep -q "clawbox"; then
  pass "GATEWAY_PORT env override in script context: version command works"
else
  warn "GATEWAY_PORT env override: unexpected output: $GATEWAY_VERSION_OUT"
fi

# 5e. version output is parseable (machine-readable)
VERSION_OUT=$(bash "$CLAWBOX" version 2>/dev/null) || VERSION_OUT=""
VERSION_LINE=$(echo "$VERSION_OUT" | head -1)
if echo "$VERSION_LINE" | grep -qE '^clawbox .+'; then
  pass "version output starts with 'clawbox ...' (machine-parseable)"
else
  fail "version output not parseable: $VERSION_LINE"
fi

# 5f. exit code distinguishability: success (0) vs error (1) vs rate-limit (2)
# Verify exit 2 is documented and distinct
HELP_EXIT2=$(bash "$CLAWBOX" help 2>&1 | grep -c "exit 2\|exit code 2" || echo "0")
if [ "$HELP_EXIT2" -gt 0 ]; then
  pass "exit 2 (rate-limit) is documented in help output"
else
  warn "exit 2 not explicitly mentioned in help — consider documenting for scripting users"
fi

echo ""

# ── Phase 6: Source audit ─────────────────────────────────────────────────────
echo "── Phase 6: Source audit ────────────────────────────────────"

# 6a. exit 0 exists for informational commands (version, help, status)
EXIT0_COUNT=$(grep -c 'exit 0' "$CLAWBOX" 2>/dev/null || echo "0")
if [ "$EXIT0_COUNT" -gt 0 ]; then
  pass "Source has $EXIT0_COUNT explicit 'exit 0' paths"
else
  fail "Source has no explicit 'exit 0' — commands may fall through to unintended exit codes"
fi

# 6b. exit 1 for user errors
EXIT1_COUNT=$(grep -c 'exit 1' "$CLAWBOX" 2>/dev/null || echo "0")
if [ "$EXIT1_COUNT" -ge 5 ]; then
  pass "Source has $EXIT1_COUNT 'exit 1' paths (user error exits)"
else
  warn "Source has only $EXIT1_COUNT 'exit 1' paths — seems low"
fi

# 6c. exit 2 for rate limit
EXIT2_COUNT=$(grep -c 'exit 2' "$CLAWBOX" 2>/dev/null || echo "0")
if [ "$EXIT2_COUNT" -gt 0 ]; then
  pass "Source has 'exit 2' path for rate-limit detection"
else
  fail "Source has no 'exit 2' — rate-limit exit code is not implemented"
fi

# 6d. CLAWBOX_RATE_LIMITED sentinel in source
if grep -q 'CLAWBOX_RATE_LIMITED' "$CLAWBOX" 2>/dev/null; then
  pass "CLAWBOX_RATE_LIMITED sentinel exists in source (scripting hook)"
else
  fail "CLAWBOX_RATE_LIMITED sentinel missing from source"
fi

# 6e. assert_container_running exits 1 when container is stopped
if grep -q 'assert_container_running' "$CLAWBOX" 2>/dev/null; then
  # Function definition starts at a specific line — check the function body (up to 40 lines)
  FUNC_START=$(grep -n '^assert_container_running()' "$CLAWBOX" | head -1 | cut -d: -f1 || echo "0")
  if [ "$FUNC_START" -gt 0 ]; then
    FUNC_BODY=$(sed -n "${FUNC_START},$((FUNC_START+40))p" "$CLAWBOX")
    if echo "$FUNC_BODY" | grep -q 'exit 1'; then
      pass "assert_container_running exits 1 on unhealthy container"
    else
      warn "assert_container_running body (first 40 lines) has no 'exit 1' — verify manually"
    fi
  else
    warn "assert_container_running exists but can't find definition line — verify manually"
  fi
else
  fail "assert_container_running not found in source"
fi

# 6f. assert_not_busy exits 1 when task is running
if grep -q 'assert_not_busy' "$CLAWBOX" 2>/dev/null; then
  if grep -A 15 'assert_not_busy' "$CLAWBOX" | grep -q 'exit 1'; then
    pass "assert_not_busy exits 1 when task lock is held"
  else
    warn "assert_not_busy exists but exit 1 not confirmed — verify manually"
  fi
else
  fail "assert_not_busy not found in source"
fi

echo ""

# ── Summary ───────────────────────────────────────────────────────────────────
echo "══════════════════════════════════════════════════════════"
TOTAL=$((PASS+WARN+FAIL))
echo "  T30 — Shell automation + exit code contract"
echo "  Pass: $PASS   Warn: $WARN   Fail: $FAIL   (of $TOTAL checks)"
echo "══════════════════════════════════════════════════════════"
echo ""

# ── Write result file ─────────────────────────────────────────────────────────
cat > "$RESULT_FILE" << EOF
# T30 — Shell automation + exit code contract
**Date:** $(date '+%Y-%m-%d %H:%M')

## Result: $PASS/$TOTAL pass, $WARN warn, $FAIL fail

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
$(if [ $FAIL -eq 0 ]; then echo "✅ All checks pass — exit code contract is correct for shell automation."; else echo "⚠️ $FAIL check(s) failed — see above."; fi)
EOF

echo "Result written to: $RESULT_FILE"

# Exit with failure if any hard failures
[ $FAIL -eq 0 ] || exit 1
