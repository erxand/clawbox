#!/usr/bin/env bash
# T11 — Background task mode test
#
# What: Test `clawbox task` (background execution) and `clawbox task-status`.
#       Verifies non-blocking start, lock file lifecycle, completion detection,
#       and ISSUE-43 timestamped log behavior (log path in output, symlink).
# Why:  clawbox task is the primary background-work command; task log and
#       symlink behavior changed in ISSUE-43 (2026-03-29).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T11-background-task.md"
CONTAINER="clawbox-work"
WORKSPACE="/home/node/.openclaw/workspace"
LOCK_FILE="$HOME/.clawbox-lock"
TASK_LOG_LINK="$HOME/.clawbox-task.log"

mkdir -p "$RESULT_DIR"

pass=0; fail=0; warn=0

check_pass() { echo "  ✓ $*"; pass=$((pass+1)); }
check_fail() { echo "  ✗ $*"; fail=$((fail+1)); }
check_warn() { echo "  ⚠ $*"; warn=$((warn+1)); }

check() {
  local name="$1" result="$2" expected="$3"
  if [ "$result" = "$expected" ]; then check_pass "$name"; else check_fail "$name (got: '$result', expected: '$expected')"; fi
}

check_contains() {
  local name="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then check_pass "$name";
  else check_fail "$name (expected to contain: '$needle')"; echo "    Got: $haystack"; fi
}

check_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then check_pass "$name";
  else check_fail "$name (should NOT contain: '$needle')"; fi
}

# ── Preflight ────────────────────────────────────────────────────────

echo ""
echo "=== T11 — Background task mode ==="
echo "Timestamp: $(date)"
echo ""

STATUS=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "missing")
if [ "$STATUS" != "healthy" ]; then
  echo "SKIP: Container is not healthy (status: $STATUS). Start with: clawbox start"
  exit 0
fi

# Clean up any stale lock from previous runs
if [ -f "$LOCK_FILE" ]; then
  LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && ! kill -0 "$LOCK_PID" 2>/dev/null; then
    rm -f "$LOCK_FILE"
    echo "  [preflight] Removed stale lock (PID $LOCK_PID no longer running)"
  fi
fi

# Clean up any leftover test artifacts from prior runs
docker exec "$CONTAINER" sh -c "rm -rf ${WORKSPACE}/t11-bg-task 2>/dev/null; true"

# ── Test 1: `clawbox task` returns immediately ───────────────────────

echo "--- Test 1: Non-blocking start ---"
TASK_DESC="Create a file called /home/node/.openclaw/workspace/t11-bg-task/result.txt containing the text 'T11 complete'"

# NOTE: We must NOT use $() here. Command substitution in bash waits for ALL
# processes in the process group (including backgrounded ones), so $() would
# block until the agent finishes — defeating the non-blocking test. Instead,
# redirect to a temp file and read it back.
TMP_OUT=$(mktemp)
START_TS=$(date +%s)
"$CLAWBOX" task "$TASK_DESC" > "$TMP_OUT" 2>&1 || true
END_TS=$(date +%s)
ELAPSED_START=$(( END_TS - START_TS ))
TASK_OUTPUT=$(cat "$TMP_OUT")
rm -f "$TMP_OUT"

echo "  Output: $TASK_OUTPUT"
echo "  Elapsed: ${ELAPSED_START}s"

check_contains "clawbox task returned 'Task started'" "$TASK_OUTPUT" "Task started"

if [ "$ELAPSED_START" -lt 10 ]; then
  check_pass "Non-blocking: returned in ${ELAPSED_START}s (< 10s)"
else
  check_fail "Blocking: took ${ELAPSED_START}s to return (expected < 10s) — likely cmd-subst issue, see NOTE above"
fi

# ── Test 2: ISSUE-43 — log path in output ────────────────────────────

echo ""
echo "--- Test 2: ISSUE-43 — timestamped log path in output ---"

# clawbox task should print "Log: /path/to/clawbox-task-YYYYMMDD-HHMMSS.log"
if echo "$TASK_OUTPUT" | grep -qE "Log:.*clawbox-task-[0-9]"; then
  TASK_LOG_PATH=$(echo "$TASK_OUTPUT" | grep -oE "/[^ ]+clawbox-task-[0-9][^ ]*" | head -1)
  check_pass "Log path printed in task output"
  echo "  Log path: $TASK_LOG_PATH"
else
  check_fail "Expected 'Log: /path/clawbox-task-YYYYMMDD-HHMMSS.log' in output"
  TASK_LOG_PATH=""
fi

# ── Test 3: ISSUE-43 — symlink points to timestamped file ────────────

echo ""
echo "--- Test 3: ISSUE-43 — ~/.clawbox-task.log symlink ---"
sleep 1

if [ -L "$TASK_LOG_LINK" ]; then
  RESOLVED=$(readlink "$TASK_LOG_LINK" 2>/dev/null || echo "")
  check_pass "~/.clawbox-task.log is a symlink"
  echo "  -> $RESOLVED"
  if echo "$RESOLVED" | grep -qE "clawbox-task-[0-9]"; then
    check_pass "Symlink points to timestamped log file"
  else
    check_fail "Symlink target doesn't look like a timestamped log: $RESOLVED"
  fi
  if [ -n "$TASK_LOG_PATH" ] && [ "$RESOLVED" = "$TASK_LOG_PATH" ]; then
    check_pass "Symlink target matches log path printed in task output"
  elif [ -n "$TASK_LOG_PATH" ]; then
    check_warn "Symlink target ($RESOLVED) differs from printed path ($TASK_LOG_PATH)"
    warn=$((warn+1))  # already counted above, but for clarity
  fi
else
  check_warn "~/.clawbox-task.log is a regular file (not a symlink) — ISSUE-43 may not be applied"
fi

# ── Test 4: Lock file created ─────────────────────────────────────────

echo ""
echo "--- Test 4: Lock file lifecycle ---"

if [ -f "$LOCK_FILE" ]; then
  LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    check_pass "Lock file exists with active PID ($LOCK_PID)"
  else
    echo "  ℹ Lock file exists but PID $LOCK_PID not running (task may have completed fast)"
  fi
else
  echo "  ℹ No lock file — task may have already completed (fast task)"
fi

# ── Test 5: task-status shows the task ───────────────────────────────

echo ""
echo "--- Test 5: task-status output ---"
STATUS_OUTPUT=$("$CLAWBOX" task-status 2>&1 || true)
echo "  Output (first 8 lines):"
echo "$STATUS_OUTPUT" | head -8 | sed 's/^/    /'

if echo "$STATUS_OUTPUT" | grep -qi "t11-bg-task\|result.txt\|Create a file\|T11"; then
  check_pass "task-status shows the submitted task description"
elif echo "$STATUS_OUTPUT" | grep -qi "Recorded tasks\|\.clawbox-task"; then
  check_pass "task-status shows task log reference"
else
  check_fail "task-status doesn't reference the submitted task"
fi

# ── Test 6: Wait for completion ───────────────────────────────────────

echo ""
echo "--- Test 6: Task completes and creates output ---"
echo "  Waiting up to 120s..."

MAX_WAIT=120
INTERVAL=5
ELAPSED_WAIT=0
COMPLETED=false

while [ "$ELAPSED_WAIT" -lt "$MAX_WAIT" ]; do
  if docker exec "$CONTAINER" test -f "${WORKSPACE}/t11-bg-task/result.txt" 2>/dev/null; then
    COMPLETED=true
    break
  fi
  sleep "$INTERVAL"
  ELAPSED_WAIT=$(( ELAPSED_WAIT + INTERVAL ))
  printf "."
done
echo ""

if [ "$COMPLETED" = "true" ]; then
  CONTENT=$(docker exec "$CONTAINER" cat "${WORKSPACE}/t11-bg-task/result.txt" 2>/dev/null || echo "(unreadable)")
  check_pass "Task completed in ~${ELAPSED_WAIT}s — result.txt created"
  echo "  Content: $CONTENT"
  if echo "$CONTENT" | grep -qi "T11\|complete"; then
    check_pass "File content matches expected"
  else
    check_fail "File content doesn't contain expected text. Got: $CONTENT"
  fi
else
  check_fail "Task did not complete within ${MAX_WAIT}s"
fi

# ── Test 7: Log file has content ──────────────────────────────────────

echo ""
echo "--- Test 7: Log file has content ---"
sleep 2

LOG_TO_CHECK="${TASK_LOG_PATH:-$TASK_LOG_LINK}"
if [ -f "$LOG_TO_CHECK" ] || [ -L "$LOG_TO_CHECK" ]; then
  LOG_LINES=$(wc -l < "$LOG_TO_CHECK" 2>/dev/null || echo 0)
  if [ "$LOG_LINES" -gt 2 ]; then
    check_pass "Log file has $LOG_LINES lines of content"
  else
    check_fail "Log file is too short ($LOG_LINES lines) — expected agent output"
  fi
else
  check_fail "Log file not found at $LOG_TO_CHECK"
fi

# ── Test 8: Lock file cleaned up after completion ─────────────────────

echo ""
echo "--- Test 8: Lock file cleaned up ---"

if [ ! -f "$LOCK_FILE" ]; then
  check_pass "Lock file cleaned up after task completion"
else
  LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    check_fail "Lock file still present with active PID $LOCK_PID"
  else
    check_warn "Lock file is stale (PID $LOCK_PID not running) — auto-cleaned on next run"
    rm -f "$LOCK_FILE"  # clean up for test 9
  fi
fi

# ── Test 9: Second task while first is in-flight ─────────────────────

echo ""
echo "--- Test 9: Concurrent task warning ---"
FAKE_PID=$$
echo "$FAKE_PID" > "$LOCK_FILE"

CONCURRENT_OUTPUT=$("$CLAWBOX" task "a second task" 2>&1 || true)
echo "  Output: $CONCURRENT_OUTPUT"

if echo "$CONCURRENT_OUTPUT" | grep -qiE "queued|already running|another.*running"; then
  check_pass "Second task shows 'already running' warning when lock is held"
else
  check_fail "Expected queued warning, got: $CONCURRENT_OUTPUT"
fi

# Clean up fake lock
rm -f "$LOCK_FILE"

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "==================================="
echo "RESULT: $pass pass, $warn warn, $fail fail"
echo "==================================="

# ── Write result file ─────────────────────────────────────────────────

cat > "$RESULT_FILE" << EOF
# T11 — Background task mode
**Date:** $(date '+%Y-%m-%d %H:%M')
**Container status:** $(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")

## What was tested
- \`clawbox task\` returns immediately (non-blocking start)
- ISSUE-43: timestamped log path printed in output
- ISSUE-43: \`~/.clawbox-task.log\` is a symlink to timestamped file
- Lock file created while task is running
- \`clawbox task-status\` shows the submitted task
- Task completes and creates output in container workspace
- Log file has content after completion
- Lock file cleaned up after completion
- Second \`clawbox task\` while one is in-flight shows queue warning

## Results
- **Pass:** $pass
- **Fail:** $fail
- **Warn:** $warn

## Key findings
$([ -n "${TASK_LOG_PATH:-}" ] && echo "- Timestamped log path: $TASK_LOG_PATH" || echo "- Timestamped log path: NOT printed in output")
$([ "$COMPLETED" = "true" ] && echo "- Task completed in ~${ELAPSED_WAIT}s" || echo "- Task DID NOT complete within ${MAX_WAIT}s")
$([ -L "$TASK_LOG_LINK" ] && echo "- ~/.clawbox-task.log is a symlink (ISSUE-43 ✓)" || echo "- ~/.clawbox-task.log is NOT a symlink (ISSUE-43 may not be applied)")

## Assessment
$([ $fail -eq 0 ] && echo "Background task mode is functional. ISSUE-43 timestamped log behavior confirmed." || echo "FAILURES detected — see results above.")
EOF

echo "Results written to: $RESULT_FILE"
[ $fail -eq 0 ]
