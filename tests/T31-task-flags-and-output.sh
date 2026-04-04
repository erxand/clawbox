#!/usr/bin/env bash
# T31 — task flag completeness + output format validation
#
# What: Verify that `clawbox task` accepts ALL flags documented in help and that
#       the task startup output contains the expected fields. This is the first test
#       to exhaustively verify flag parity between `run` and `task`.
#
# Phases:
#   Phase 1: Source audit — confirm --retry, --timeout, --session, --context, --thinking flags
#            are all parsed in cmd_task
#   Phase 2: Flag acceptance — each flag is accepted without error
#   Phase 3: Output format — startup messages contain expected fields per flag
#   Phase 4: Error paths — invalid --retry, --timeout values rejected with usage hints
#   Phase 5: Flag parity with `run` — task accepts the same flags as run (minus --quiet/--json)
#   Phase 6: Help text coverage — all task flags appear in help output
#   Phase 7: --retry 0 (default) works, non-numeric values rejected
#   Phase 8: Combined flags — multiple flags together, correct ordering
#
# Why: cmd_task had --retry documented and tested in T22 Phase 6 as "accepted" but the
#      implementation was missing — the flag fell through to the `*)` catch-all and was
#      treated as the task description. This test exposes the gap and validates the fix.
#
# Date: 2026-04-04
# Run time: ~90s (tasks start immediately; we don't wait for completion)

set -euo pipefail

CLAWBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAWBOX="$CLAWBOX_DIR/clawbox"
RESULT_DIR="$CLAWBOX_DIR/tests/results"
mkdir -p "$RESULT_DIR"

TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T31-task-flags-and-output.md"

PASS=0
WARN=0
FAIL=0

log()  { echo "[$(date '+%H:%M:%S')] $*"; }
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
warn() { echo "  ⚠ $*"; WARN=$((WARN+1)); }
fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }

assert_pass() { if [ "$1" ]; then pass "$2"; else fail "$2"; fi; }
assert_fail() { if [ "$1" ]; then fail "$2"; else pass "$2"; fi; }

# Source common lib for rate-limit detection
source "$CLAWBOX_DIR/tests/lib/common.sh" 2>/dev/null || true

log "Starting T31 — task flag completeness + output format validation"

{
cat << HEADER
# T31 — task flag completeness + output format validation

**Run:** $(date '+%Y-%m-%d %H:%M')
**Host:** $(hostname)
**Clawbox:** $CLAWBOX_DIR

## Phases

- Phase 1: Source audit (--retry, --timeout, --session, --context, --thinking in cmd_task)
- Phase 2: Flag acceptance (each flag accepted without error, non-blocking return)
- Phase 3: Output format (startup messages contain correct fields per flag)
- Phase 4: Error paths (invalid values rejected with usage hints and exit 1)
- Phase 5: Flag parity (task flags match run flags, minus --quiet/--json)
- Phase 6: Help text coverage (all task flags in help output)
- Phase 7: --retry 0 and invalid --retry handling
- Phase 8: Combined flags (multi-flag combos work, non-blocking)

## Results

HEADER

# ── Phase 1: Source audit ─────────────────────────────────────────
log "Phase 1: Source audit — confirm all flags parsed in cmd_task"

# Get cmd_task function body (lines 509 onward until the next cmd_ function)
CMD_TASK_SRC=$(awk '/^cmd_task\(\)/{found=1} found{print} found && /^cmd_[a-z].*\(\)/ && !/^cmd_task/{found=0}' "$CLAWBOX")

if echo "$CMD_TASK_SRC" | grep -q "\-\-retry"; then
  pass "Phase 1a: --retry flag present in cmd_task source"
else
  fail "Phase 1a: --retry flag MISSING from cmd_task source"
fi

if echo "$CMD_TASK_SRC" | grep -q "\-\-timeout"; then
  pass "Phase 1b: --timeout flag present in cmd_task source"
else
  fail "Phase 1b: --timeout flag MISSING from cmd_task source"
fi

if echo "$CMD_TASK_SRC" | grep -q "\-\-session"; then
  pass "Phase 1c: --session flag present in cmd_task source"
else
  fail "Phase 1c: --session flag MISSING from cmd_task source"
fi

if echo "$CMD_TASK_SRC" | grep -q "\-\-context"; then
  pass "Phase 1d: --context flag present in cmd_task source"
else
  fail "Phase 1d: --context flag MISSING from cmd_task source"
fi

if echo "$CMD_TASK_SRC" | grep -q "\-\-thinking"; then
  pass "Phase 1e: --thinking flag present in cmd_task source"
else
  fail "Phase 1e: --thinking flag MISSING from cmd_task source"
fi

# Verify retry_max is actually used (not just declared)
if echo "$CMD_TASK_SRC" | grep -q "retry_max.*-gt\|retry_max.*le\|retry_max.*[0-9]"; then
  pass "Phase 1f: retry_max variable is actually used in logic (not just declared)"
else
  fail "Phase 1f: retry_max may be declared but not used in cmd_task logic"
fi

# ── Phase 2: Flag acceptance + non-blocking return ────────────────
log "Phase 2: Flag acceptance — each flag accepted (non-blocking, fast return)"

TMP_LOG=""
START_OUT=""
EXIT_CODE=0

# 2a: --retry 1
log "Phase 2a: clawbox task --retry 1 ..."
START_OUT=$("$CLAWBOX" task --retry 1 "Say exactly: TASK_RETRY_T31_OK" 2>&1) || EXIT_CODE=$?
if echo "$START_OUT" | grep -q "Task started"; then
  pass "Phase 2a: --retry 1 accepted; task started"
  # Extract log path from output
  TMP_LOG=$(echo "$START_OUT" | grep "Log:" | awk '{print $2}')
else
  fail "Phase 2a: --retry 1 NOT accepted or task didn't start (output: ${START_OUT:0:100})"
fi
# Wait briefly for lock to release (fast task)
sleep 3
wait 2>/dev/null || true

# 2b: --retry printed in startup output
if echo "$START_OUT" | grep -qi "retry"; then
  pass "Phase 2b: 'retry' mentioned in startup output when --retry N > 0"
else
  warn "Phase 2b: 'retry' not mentioned in startup output (may be cosmetic)"
fi

# 2c: --session flag accepted
log "Phase 2c: clawbox task --session ..."
START_OUT=$("$CLAWBOX" task --session t31-session-test "Say: SESSION_T31_OK" 2>&1) || true
if echo "$START_OUT" | grep -q "Task started"; then
  pass "Phase 2c: --session accepted; task started"
  # Check session appears in output
  if echo "$START_OUT" | grep -q "t31-session-test"; then
    pass "Phase 2d: session name 't31-session-test' in startup output"
  else
    warn "Phase 2d: session name not shown in startup output"
  fi
else
  fail "Phase 2c: --session NOT accepted"
fi
sleep 3
wait 2>/dev/null || true

# 2e: --thinking flag accepted
log "Phase 2e: clawbox task --thinking minimal ..."
START_OUT=$("$CLAWBOX" task --thinking minimal "Say: THINKING_T31_OK" 2>&1) || true
if echo "$START_OUT" | grep -q "Task started"; then
  pass "Phase 2e: --thinking minimal accepted; task started"
else
  fail "Phase 2e: --thinking minimal NOT accepted"
fi
sleep 3
wait 2>/dev/null || true

# ── Phase 3: Output format correctness ───────────────────────────
log "Phase 3: Output format — startup fields"

# 3a: Log path shown in output
log "Phase 3a: task startup output contains Log: line"
START_OUT=$("$CLAWBOX" task "Say: FORMAT_T31_OK" 2>&1) || true
LOG_PATH=$(echo "$START_OUT" | grep "Log:" | awk '{print $2}')
if [ -n "$LOG_PATH" ]; then
  pass "Phase 3a: Log path shown in startup output ($LOG_PATH)"
else
  fail "Phase 3a: Log path NOT shown in startup output"
fi
sleep 3
wait 2>/dev/null || true

# 3b: Log symlink exists and points to a file
if [ -L "$HOME/.clawbox-task.log" ]; then
  RESOLVED=$(readlink "$HOME/.clawbox-task.log" 2>/dev/null || echo "")
  if [ -n "$RESOLVED" ]; then
    pass "Phase 3b: ~/.clawbox-task.log symlink exists → $RESOLVED"
  else
    warn "Phase 3b: symlink exists but target is empty"
  fi
else
  warn "Phase 3b: ~/.clawbox-task.log symlink not found (task may not have run yet)"
fi

# 3c: Output always contains the three UX lines
if echo "$START_OUT" | grep -q "task-logs"; then
  pass "Phase 3c: 'task-logs' hint in startup output"
else
  fail "Phase 3c: 'task-logs' hint NOT in startup output"
fi

if echo "$START_OUT" | grep -q "task-status"; then
  pass "Phase 3d: 'task-status' hint in startup output"
else
  fail "Phase 3d: 'task-status' hint NOT in startup output"
fi

# ── Phase 4: Error paths ──────────────────────────────────────────
log "Phase 4: Error paths — invalid flag values rejected"

# 4a: --retry with no value → usage hint + exit 1
log "Phase 4a: --retry with no value"
ERROUT=$("$CLAWBOX" task --retry 2>&1) || EXIT4A=$?
if [ "${EXIT4A:-0}" -ne 0 ]; then
  pass "Phase 4a: --retry with no value exits non-zero"
else
  fail "Phase 4a: --retry with no value should exit non-zero but exited 0"
fi
if echo "$ERROUT" | grep -qi "usage\|retry"; then
  pass "Phase 4b: usage hint shown for --retry with no value"
else
  warn "Phase 4b: no usage hint for --retry with no value"
fi

# 4c: --timeout with non-numeric value → usage hint + exit 1
log "Phase 4c: --timeout with non-numeric value"
EXIT4C=0
ERROUT=$("$CLAWBOX" task --timeout abc "desc" 2>&1) || EXIT4C=$?
if [ "$EXIT4C" -ne 0 ]; then
  pass "Phase 4c: --timeout with non-numeric value exits non-zero"
else
  fail "Phase 4c: --timeout with non-numeric value should exit non-zero"
fi
if echo "$ERROUT" | grep -qi "usage\|timeout"; then
  pass "Phase 4d: usage hint shown for --timeout with non-numeric value"
else
  warn "Phase 4d: no usage hint for --timeout with non-numeric value"
fi

# 4e: --retry with non-numeric value → exit 1
log "Phase 4e: --retry with non-numeric value"
EXIT4E=0
ERROUT=$("$CLAWBOX" task --retry xyz "desc" 2>&1) || EXIT4E=$?
if [ "$EXIT4E" -ne 0 ]; then
  pass "Phase 4e: --retry with non-numeric value exits non-zero"
else
  fail "Phase 4e: --retry with non-numeric value should exit non-zero"
fi

# ── Phase 5: Flag parity with run ────────────────────────────────
log "Phase 5: Flag parity between run and task"

CMD_RUN_SRC=$(awk '/^cmd_run\(\)/{found=1} found{print} found && /^cmd_[a-z].*\(\)/ && !/^cmd_run/{found=0}' "$CLAWBOX")

RUN_HAS_RETRY=$(echo "$CMD_RUN_SRC" | grep -c "\-\-retry" || echo "0")
TASK_HAS_RETRY=$(echo "$CMD_TASK_SRC" | grep -c "\-\-retry" || echo "0")

if [ "$RUN_HAS_RETRY" -gt 0 ] && [ "$TASK_HAS_RETRY" -gt 0 ]; then
  pass "Phase 5a: --retry implemented in BOTH cmd_run and cmd_task"
else
  fail "Phase 5a: --retry parity broken — run has $RUN_HAS_RETRY refs, task has $TASK_HAS_RETRY refs"
fi

RUN_HAS_TIMEOUT=0
echo "$CMD_RUN_SRC" | grep -q "\-\-timeout" && RUN_HAS_TIMEOUT=1 || true
TASK_HAS_TIMEOUT=0
echo "$CMD_TASK_SRC" | grep -q "\-\-timeout" && TASK_HAS_TIMEOUT=1 || true
# Note: --timeout is task-only, so run should NOT have it
if [ "$RUN_HAS_TIMEOUT" -eq 0 ] && [ "$TASK_HAS_TIMEOUT" -gt 0 ]; then
  pass "Phase 5b: --timeout is task-only (correct — run doesn't have it)"
else
  warn "Phase 5b: --timeout parity check: run has it=$RUN_HAS_TIMEOUT, task has it=$TASK_HAS_TIMEOUT"
fi

# --quiet/--json should be run-only (task writes to log file)
TASK_HAS_JSON=0
echo "$CMD_TASK_SRC" | grep -q "\-\-json" && TASK_HAS_JSON=1 || true
TASK_HAS_QUIET=0
echo "$CMD_TASK_SRC" | grep -q "\-\-quiet" && TASK_HAS_QUIET=1 || true
if [ "$TASK_HAS_JSON" -eq 0 ] && [ "$TASK_HAS_QUIET" -eq 0 ]; then
  pass "Phase 5c: --quiet/--json correctly absent from cmd_task (task writes to log, not stdout)"
else
  warn "Phase 5c: --quiet/--json present in cmd_task — unexpected (task should write to log)"
fi

# ── Phase 6: Help text coverage ──────────────────────────────────
log "Phase 6: Help text coverage"

HELP_OUT=$("$CLAWBOX" help 2>&1)

if echo "$HELP_OUT" | grep -q "task.*retry\|--retry.*task\|retry.*task"; then
  pass "Phase 6a: --retry documented in help for task"
else
  fail "Phase 6a: task --retry NOT found in help text"
fi

if echo "$HELP_OUT" | grep -q "task.*timeout\|--timeout"; then
  pass "Phase 6b: --timeout documented in help for task"
else
  fail "Phase 6b: task --timeout NOT found in help text"
fi

if echo "$HELP_OUT" | grep -q "task.*session\|--session"; then
  pass "Phase 6c: --session documented in help for task"
else
  fail "Phase 6c: task --session NOT found in help text"
fi

if echo "$HELP_OUT" | grep -q "task.*context\|--context"; then
  pass "Phase 6d: --context documented in help for task"
else
  fail "Phase 6d: task --context NOT found in help text"
fi

# ── Phase 7: --retry 0 and edge cases ────────────────────────────
log "Phase 7: --retry 0 and edge cases"

# 7a: --retry 0 is valid (no-retry, same as default)
log "Phase 7a: --retry 0 accepted"
START_OUT=$("$CLAWBOX" task --retry 0 "Say: RETRY_ZERO_T31_OK" 2>&1) || true
if echo "$START_OUT" | grep -q "Task started"; then
  pass "Phase 7a: --retry 0 accepted; task started"
else
  fail "Phase 7a: --retry 0 NOT accepted"
fi
sleep 3
wait 2>/dev/null || true

# 7b: --retry 0 does NOT show retry line in output (it's the default/no-op)
if echo "$START_OUT" | grep -qi "Retry:"; then
  warn "Phase 7b: 'Retry:' shown even for --retry 0 (harmless but unexpected)"
else
  pass "Phase 7b: 'Retry:' correctly omitted for --retry 0"
fi

# ── Phase 8: Combined flags ───────────────────────────────────────
log "Phase 8: Combined flags — multiple flags together"

# 8a: --session + --retry together
log "Phase 8a: --session + --retry combined"
START_OUT=$("$CLAWBOX" task --session t31-combo --retry 2 "Say: COMBO_T31_OK" 2>&1) || true
if echo "$START_OUT" | grep -q "Task started"; then
  pass "Phase 8a: --session + --retry combined accepted"
else
  fail "Phase 8a: --session + --retry combined NOT accepted"
fi
if echo "$START_OUT" | grep -q "t31-combo"; then
  pass "Phase 8b: session name shown in combined-flags output"
else
  warn "Phase 8b: session name NOT shown in combined-flags output"
fi
if echo "$START_OUT" | grep -qi "retry"; then
  pass "Phase 8c: retry shown in combined-flags output"
else
  warn "Phase 8c: retry NOT shown in combined-flags output"
fi
sleep 3
wait 2>/dev/null || true

# 8d: --thinking + --retry + message (3-flag combo)
log "Phase 8d: --thinking + --retry + message (3-flag combo)"
START_OUT=$("$CLAWBOX" task --thinking minimal --retry 1 "Say: THREE_FLAGS_T31_OK" 2>&1) || true
if echo "$START_OUT" | grep -q "Task started"; then
  pass "Phase 8d: 3-flag combo (--thinking + --retry + message) accepted without crash"
else
  fail "Phase 8d: 3-flag combo NOT accepted"
fi
sleep 3
wait 2>/dev/null || true

# ── Summary ──────────────────────────────────────────────────────

TOTAL=$((PASS + WARN + FAIL))
echo ""
echo "## Summary"
echo ""
echo "| Result | Count |"
echo "|--------|-------|"
echo "| ✓ Pass | $PASS |"
echo "| ⚠ Warn | $WARN |"
echo "| ✗ Fail | $FAIL |"
echo "| Total  | $TOTAL |"
echo ""

if [ "$FAIL" -eq 0 ] && [ "$WARN" -eq 0 ]; then
  echo "**Verdict: PASS — $PASS/$TOTAL checks pass, 0 warn, 0 fail ✅**"
elif [ "$FAIL" -eq 0 ]; then
  echo "**Verdict: PASS with warnings — $PASS/$TOTAL pass, $WARN warn, 0 fail ⚠️**"
else
  echo "**Verdict: FAIL — $FAIL/$TOTAL checks failed ❌**"
fi

} | tee "$RESULT_FILE"

echo ""
echo "Result written to: $RESULT_FILE"
exit $FAIL
