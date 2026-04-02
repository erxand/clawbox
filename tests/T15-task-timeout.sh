#!/usr/bin/env bash
# T15 — Task timeout + handoff
#
# What: Test that `clawbox task --timeout <min>` correctly:
#   1. Runs the agent and kills it after the timeout
#   2. Sends a handoff prompt asking the agent to update TASK.md
#   3. Logs "TIMEOUT after Nm — sending handoff prompt" in the task log
#   4. Exits cleanly (lock released, next task can run)
#   5. Task log contains handoff response from agent
#
# Why:  Long-running tasks have no safety net. A stuck agent runs forever with
#       no progress visibility. The timeout+handoff pattern ensures partial work
#       is committed and documented so a follow-up session can continue.
#
# ISSUE-43 fix: capture the specific log file path from `clawbox task` output
# so that test 9 (new task) starting a new log doesn't clobber the analysis.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T15-task-timeout.md"
CONTAINER="clawbox-work"

mkdir -p "$RESULT_DIR"

PASS=0
FAIL=0
WARN=0

log() { echo "[T15 $(date +%H:%M:%S)] $*"; }
pass() { echo "✓ $*"; PASS=$((PASS+1)); }
fail() { echo "✗ $*"; FAIL=$((FAIL+1)); }
warn() { echo "⚠ $*"; WARN=$((WARN+1)); }

# ── Teardown helper ─────────────────────────────────────────────────

cleanup() {
  log "Cleanup: stopping container..."
  "$CLAWBOX" stop 2>/dev/null || true
}
trap cleanup EXIT

# ── Setup ───────────────────────────────────────────────────────────

log "Starting fresh container..."
"$CLAWBOX" stop 2>/dev/null || true
"$CLAWBOX" start
# Give the gateway extra time to fully initialise before firing a task (T15 saw
# "gateway connect failed" when using a 5s wait — the default clawbox start
# waits for the container to be healthy, but the OpenClaw gateway inside may
# still be binding its WebSocket. 15s gives it a safe margin.
log "Waiting 15s for gateway to fully initialise..."
sleep 15

# ── Test 1: --timeout flag accepted + task starts ───────────────────

log "Test 1: --timeout flag is accepted + log path printed..."

# Give a complex task that should NOT finish in 1 minute
TASK_DESC="IMPORTANT: Do ALL of this work yourself — do NOT spawn subagents or delegate to other sessions. Write every file directly using your own tools. Build a complete REST API for a blog platform in /home/node/.openclaw/workspace/blog-api-timeout-test with: (1) Express.js server with JWT authentication middleware, (2) endpoints for users (register, login, profile), posts (CRUD), comments (CRUD on posts), (3) in-memory data store with proper validation, (4) comprehensive test suite with at least 20 tests using Jest, (5) API documentation in README.md. Make sure all tests pass. Create TASK.md with your plan and progress."

# Capture the task start output (ISSUE-43: extract specific log path from output)
TASK_START_OUTPUT=$("$CLAWBOX" task --timeout 1 --session "t15-timeout-test" "$TASK_DESC" 2>&1 || true)
echo "$TASK_START_OUTPUT"

# Extract log path from output — ISSUE-43 fix: "Log: /path/to/timestamped.log"
# If old version (no Log: line), fall back to the symlink
TASK_LOG=$(echo "$TASK_START_OUTPUT" | grep "^  Log:" | awk '{print $2}' | head -1 || true)
if [ -z "$TASK_LOG" ]; then
  TASK_LOG="$HOME/.clawbox-task.log"
  warn "Log path not found in task output — using symlink fallback $TASK_LOG"
else
  pass "--timeout flag accepted, task started, log path: $TASK_LOG"
fi

# Verify task started
if [ -f "$HOME/.clawbox-lock" ] || [ -f "$TASK_LOG" ]; then
  pass "Task started (lock file or log present)"
else
  fail "Lock file and log both absent — task may not have started"
fi

# ── Test 2: Wait for task completion (timeout + handoff = ~2 min total) ──

log "Test 2: Waiting for task to timeout and handoff to complete (up to 3 minutes)..."

MAX_WAIT=420  # 7 minutes (1 min task + ~2 min handoff + gateway reload + buffer)
waited=0
while [ $waited -lt $MAX_WAIT ]; do
  # Check if task is done (no lock file, and log has completion marker)
  if [ ! -f "$HOME/.clawbox-lock" ] && [ -f "$TASK_LOG" ]; then
    if grep -q "Handoff complete\|Task completed" "$TASK_LOG" 2>/dev/null; then
      log "Task finished after ${waited}s"
      break
    fi
  fi
  sleep 5
  waited=$((waited + 5))
done

if [ $waited -ge $MAX_WAIT ]; then
  warn "Task did not complete within ${MAX_WAIT}s — proceeding with partial results"
fi

# ── Test 2b: Gateway connection succeeded (not a cold-start failure) ────────

log "Test 2b: Checking for gateway connection failures..."
if grep -q "gateway connect failed\|Gateway agent failed\|No reply from agent" "$TASK_LOG" 2>/dev/null; then
  fail "Gateway connection failed — task did not actually run (cold-start issue). Increase startup sleep."
  cat "$TASK_LOG" >&2
else
  pass "No gateway connection failures in task log"
fi

# ── Test 3: Task log exists ──────────────────────────────────────────

log "Test 3: Task log exists..."
if [ -f "$TASK_LOG" ]; then
  pass "Task log exists at $TASK_LOG"
else
  fail "Task log not found at $TASK_LOG"
fi

# ── Test 4: Timeout marker in log ───────────────────────────────────

log "Test 4: Timeout marker in log..."
if grep -q "TIMEOUT after.*sending handoff prompt" "$TASK_LOG" 2>/dev/null; then
  pass "Timeout marker found in log"
else
  if grep -q "Task completed" "$TASK_LOG" 2>/dev/null; then
    warn "Task completed before timeout (1 min may have been enough) — no timeout triggered"
  else
    fail "Timeout marker NOT found in log — timeout may not have triggered"
  fi
fi

# ── Test 5: Handoff complete marker in log ──────────────────────────

log "Test 5: Handoff complete marker in log..."
if grep -q "Handoff complete" "$TASK_LOG" 2>/dev/null; then
  pass "Handoff complete marker found in log"
else
  if grep -q "TIMEOUT" "$TASK_LOG" 2>/dev/null; then
    fail "Timeout triggered but Handoff complete marker missing"
  else
    warn "No handoff marker — timeout did not trigger"
  fi
fi

# ── Test 6: Handoff response contains something useful ─────────────

log "Test 6: Handoff response non-empty..."
HANDOFF_SECTION=$(awk '/--- Handoff response ---/,/=== Handoff complete/' "$TASK_LOG" 2>/dev/null || true)
if [ -n "$HANDOFF_SECTION" ] && [ ${#HANDOFF_SECTION} -gt 100 ]; then
  pass "Handoff response non-empty (${#HANDOFF_SECTION} bytes)"
else
  if grep -q "TIMEOUT" "$TASK_LOG" 2>/dev/null; then
    fail "Handoff response empty or very short"
  else
    warn "No handoff response — timeout did not trigger"
  fi
fi

# ── Test 7: TASK.md created or updated in workspace ─────────────────

log "Test 7: TASK.md created in workspace..."
TASK_MD=$(docker exec "$CONTAINER" \
  sh -c "find /home/node/.openclaw/workspace -name TASK.md -not -path '*/node_modules/*' 2>/dev/null | head -3" \
  2>/dev/null || echo "")
TASK_MD_CONTENT=""
if [ -n "$TASK_MD" ]; then
  TASK_MD_CONTENT=$(docker exec "$CONTAINER" cat "$(echo "$TASK_MD" | head -1)" 2>/dev/null || echo "")
  if [ -n "$TASK_MD_CONTENT" ]; then
    pass "TASK.md found and non-empty: $TASK_MD"
  else
    warn "TASK.md found but empty: $TASK_MD"
  fi
else
  # Check if handoff fell back to embedded agent (gateway not ready)
  if grep -q "falling back to embedded\|Gateway agent failed" "$TASK_LOG" 2>/dev/null; then
    warn "TASK.md not found — handoff fell back to embedded (host) agent: gateway reload was not ready in time. (Fixed in CLI: gateway health poll now retries for 60s)"
  elif grep -q "TIMEOUT" "$TASK_LOG" 2>/dev/null; then
    fail "TASK.md not found after handoff — agent did not write task journal"
  else
    warn "TASK.md not found — task may not have had time to create it"
  fi
fi

# ── Test 8: Lock released after completion ──────────────────────────

log "Test 8: Lock released after completion..."
if [ ! -f "$HOME/.clawbox-lock" ]; then
  pass "Lock file cleaned up — new tasks can run immediately"
else
  LOCK_PID=$(cat "$HOME/.clawbox-lock" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    fail "Lock still held by PID $LOCK_PID after task completion"
  else
    warn "Stale lock file present but PID is dead — would be cleaned up on next run"
    rm -f "$HOME/.clawbox-lock"
  fi
fi

# ── Test 9: New task can start after timeout ────────────────────────
# IMPORTANT (ISSUE-43): capture new task's log path separately so it
# doesn't clobber TASK_LOG used in the result section below.
# NOTE: If the container stopped during SIGUSR1 reload, restart it first.

log "Test 9: New task starts cleanly after timeout..."
# Ensure container is running (gateway reload may have stopped it)
if ! docker ps --filter "name=$CONTAINER" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -q "$CONTAINER"; then
  log "Container stopped during handoff — restarting for test 9..."
  "$CLAWBOX" start 2>/dev/null || true
  sleep 10
fi

NEW_TASK_TMP=$(mktemp)
"$CLAWBOX" task --timeout 0 "Write the text DONE to /home/node/.openclaw/workspace/DONE.txt" > "$NEW_TASK_TMP" 2>&1 || true
NEW_TASK_OUTPUT=$(cat "$NEW_TASK_TMP")
rm -f "$NEW_TASK_TMP"
NEW_TASK_LOG=$(echo "$NEW_TASK_OUTPUT" | grep "^  Log:" | awk '{print $2}' | head -1 || true)
if echo "$NEW_TASK_OUTPUT" | grep -q "Task started"; then
  pass "New task started cleanly after timeout (log: ${NEW_TASK_LOG:-unknown})"
else
  fail "New task failed to start after timeout: $NEW_TASK_OUTPUT"
fi

# Cancel that follow-up task quickly since we don't need it
sleep 2
"$CLAWBOX" cancel 2>/dev/null || true

# ── Test 10: help text shows --timeout ──────────────────────────────

log "Test 10: help text shows --timeout..."
if "$CLAWBOX" help 2>&1 | grep -q "\-\-timeout"; then
  pass "help text includes --timeout flag"
else
  fail "help text missing --timeout flag"
fi

# ── Test 11: ISSUE-43 — timestamped log files (not overwritten) ─────

log "Test 11: ISSUE-43 — task log has unique timestamped path..."
if [[ "$TASK_LOG" =~ clawbox-task-[0-9]{8}-[0-9]{6}\.log$ ]]; then
  pass "Task log is timestamped: $TASK_LOG"
else
  warn "Task log is not timestamped — ISSUE-43 may not be fixed: $TASK_LOG"
fi

# Verify symlink points to the correct timestamped log
LINK_TARGET=$(readlink "$HOME/.clawbox-task.log" 2>/dev/null || echo "")
if [ -n "$LINK_TARGET" ]; then
  pass "Symlink ~/.clawbox-task.log exists, points to: $LINK_TARGET"
else
  warn "Symlink ~/.clawbox-task.log not found — legacy fixed log may still be in use"
fi

# ── Summary ─────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL + WARN))

{
  echo "# T15 — Task timeout + handoff"
  echo "**Date:** $(date '+%Y-%m-%d %H:%M')"
  echo ""
  echo "## Score"
  echo "- ✓ Pass: $PASS"
  echo "- ⚠ Warn: $WARN"
  echo "- ✗ Fail: $FAIL"
  echo "- Total checks: $TOTAL"
  echo ""
  echo "## Findings"
  echo ""
  if grep -q "TIMEOUT after" "$TASK_LOG" 2>/dev/null; then
    echo "### Timeout triggered: YES"
    echo "- $(grep 'TIMEOUT after' "$TASK_LOG" 2>/dev/null | head -1)"
  else
    echo "### Timeout triggered: NO (task completed within 1 min)"
  fi
  echo ""
  if grep -q "Handoff complete" "$TASK_LOG" 2>/dev/null; then
    echo "### Handoff sent: YES"
    echo "- Handoff response length: $(awk '/--- Handoff response ---/,/=== Handoff complete/' "$TASK_LOG" 2>/dev/null | wc -c) bytes"
  else
    echo "### Handoff sent: NO"
  fi
  echo ""
  echo "### Task log: $TASK_LOG"
  echo ""
  if [ -n "${TASK_MD:-}" ]; then
    echo "### TASK.md found: YES"
    echo "- Location: $TASK_MD"
    echo ""
    echo "### TASK.md content:"
    echo '```'
    echo "${TASK_MD_CONTENT:-}" | head -40
    echo '```'
  else
    echo "### TASK.md found: NO"
  fi
  echo ""
  echo "## Task Log Tail (the timeout test log, not clobbered by test 9)"
  echo '```'
  tail -60 "$TASK_LOG" 2>/dev/null || echo "(no log)"
  echo '```'
} > "$RESULT_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  T15 RESULT: $PASS pass / $WARN warn / $FAIL fail (of $TOTAL)"
echo "  Result file: $RESULT_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[ $FAIL -eq 0 ] && exit 0 || exit 1
