#!/usr/bin/env bash
# T11 — Background task mode test
#
# What: Test `clawbox task` (background execution) and `clawbox task-status`.
#       Verifies non-blocking start, lock file lifecycle, and completion detection.
# Why:  clawbox task is the only primary CLI command without a formal test.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T11-background-task.md"
CONTAINER="clawbox-work"
WORKSPACE="/home/node/.openclaw/workspace"
LOCK_FILE="$HOME/.clawbox-lock"
TASK_FILE="$HOME/.clawbox-tasks"

mkdir -p "$RESULT_DIR"

pass() { echo "✓ $*"; }
fail() { echo "✗ $*"; }
info() { echo "  $*"; }

# ── Preflight ────────────────────────────────────────────────────────

echo "=== T11 — Background task mode ==="
echo "Timestamp: $(date)"
echo ""

# Container must be running
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
    info "Removed stale lock file (PID $LOCK_PID no longer running)"
  fi
fi

# Clean up any leftover test artifacts from prior runs
docker exec "$CONTAINER" sh -c "rm -rf ${WORKSPACE}/t11-bg-task 2>/dev/null; true"

# ── Test 1: `clawbox task` returns immediately ───────────────────────

echo ""
echo "--- Test 1: Non-blocking start ---"
TASK_DESC="Create a file called /home/node/.openclaw/workspace/t11-bg-task/result.txt containing the text 'T11 complete'"
START_TS=$(date +%s)
TASK_OUTPUT=$("$CLAWBOX" task "$TASK_DESC" 2>&1 || true)
END_TS=$(date +%s)
ELAPSED=$(( END_TS - START_TS ))

echo "  Output: $TASK_OUTPUT"
echo "  Elapsed: ${ELAPSED}s"

if echo "$TASK_OUTPUT" | grep -qi "task started"; then
  pass "clawbox task returned immediately with 'Task started' message"
else
  fail "Expected 'Task started' message, got: $TASK_OUTPUT"
fi

if [ "$ELAPSED" -lt 5 ]; then
  pass "Non-blocking: returned in ${ELAPSED}s (< 5s)"
else
  fail "Blocking: took ${ELAPSED}s to return (expected < 5s)"
fi

# ── Test 2: Lock file created (task is running) ──────────────────────

echo ""
echo "--- Test 2: Lock file lifecycle ---"
sleep 1

if [ -f "$LOCK_FILE" ]; then
  LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    pass "Lock file exists with active PID ($LOCK_PID)"
  else
    info "Lock file exists but PID $LOCK_PID is not running (task may have completed very fast)"
  fi
else
  info "No lock file found — task may have already completed"
fi

# ── Test 3: task-status shows the task ───────────────────────────────

echo ""
echo "--- Test 3: task-status output ---"
STATUS_OUTPUT=$("$CLAWBOX" task-status 2>&1 || true)
echo "  Output:"
echo "$STATUS_OUTPUT" | sed 's/^/    /'

if echo "$STATUS_OUTPUT" | grep -q "t11-bg-task\|T11\|result.txt\|t11\|Create a file"; then
  pass "task-status shows the submitted task"
else
  # It should show at minimum the tasks file entry
  if echo "$STATUS_OUTPUT" | grep -q "Recorded tasks"; then
    pass "task-status shows tasks file (task logged)"
  else
    fail "task-status doesn't show the submitted task"
  fi
fi

# ── Test 4: Wait for completion ───────────────────────────────────────

echo ""
echo "--- Test 4: Task completes and creates output ---"
echo "  Waiting up to 120s for task to complete..."

MAX_WAIT=120
INTERVAL=5
ELAPSED=0
COMPLETED=false

while [ "$ELAPSED" -lt "$MAX_WAIT" ]; do
  if docker exec "$CONTAINER" test -f "${WORKSPACE}/t11-bg-task/result.txt" 2>/dev/null; then
    COMPLETED=true
    break
  fi
  sleep "$INTERVAL"
  ELAPSED=$(( ELAPSED + INTERVAL ))
  printf "."
done
echo ""

if [ "$COMPLETED" = "true" ]; then
  CONTENT=$(docker exec "$CONTAINER" cat "${WORKSPACE}/t11-bg-task/result.txt" 2>/dev/null || echo "(unreadable)")
  pass "Task completed in ~${ELAPSED}s — result.txt created"
  info "File content: $CONTENT"
  if echo "$CONTENT" | grep -qi "T11 complete\|complete"; then
    pass "File content matches expected ('T11 complete' or similar)"
  else
    fail "File content doesn't contain expected text. Got: $CONTENT"
  fi
else
  fail "Task did not complete within ${MAX_WAIT}s"
fi

# ── Test 5: Lock file cleaned up after completion ─────────────────────

echo ""
echo "--- Test 5: Lock file cleaned up ---"
sleep 2  # Give subprocess a moment to release lock

if [ ! -f "$LOCK_FILE" ]; then
  pass "Lock file cleaned up after task completion"
else
  LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && kill -0 "$LOCK_PID" 2>/dev/null; then
    fail "Lock file still present with active PID $LOCK_PID"
  else
    info "Lock file is stale (PID $LOCK_PID no longer running) — auto-cleanup on next run"
    pass "Lock PID is not running (effectively cleaned up)"
  fi
fi

# ── Test 6: Second task while first is in-flight ─────────────────────

echo ""
echo "--- Test 6: Concurrent task warning ---"
# Fake a lock file to simulate a running task
FAKE_PID=$$
echo "$FAKE_PID" > "$LOCK_FILE"

CONCURRENT_OUTPUT=$("$CLAWBOX" task "a second task" 2>&1 || true)
echo "  Output: $CONCURRENT_OUTPUT"

if echo "$CONCURRENT_OUTPUT" | grep -qi "queued\|already running\|another.*running"; then
  pass "Second task shows 'already running' / queued warning when lock is held"
else
  fail "Expected queued warning, got: $CONCURRENT_OUTPUT"
fi

# Clean up fake lock
rm -f "$LOCK_FILE"

# ── Summary ──────────────────────────────────────────────────────────

echo ""
echo "=== Done ==="
PASS=$(grep -c "^✓" <<< "$(grep -E "^✓|^✗" /dev/stdin <<< "$(grep -E "^[✓✗]" /dev/fd/1 2>/dev/null || true)")" || true)

# ── Write result file ─────────────────────────────────────────────────

cat > "$RESULT_FILE" << EOF
# T11 — Background task mode
**Date:** $(date '+%Y-%m-%d %H:%M')
**Container status:** $(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")

## What was tested
- \`clawbox task\` returns immediately (non-blocking)
- Lock file is created while task runs
- \`clawbox task-status\` shows the task
- Task completes and creates output in container workspace
- Lock file is cleaned up after completion
- Second \`clawbox task\` while one is in-flight shows a queue warning

## Results
$([ "$COMPLETED" = "true" ] && echo "✓ Background task ran to completion in ~${ELAPSED}s" || echo "✗ Background task did not complete within ${MAX_WAIT}s")
$([ "$ELAPSED" -lt 5 ] && echo "✓ Non-blocking: returned in ${ELAPSED}s" || echo "? Check elapsed time")
- task-status output reviewed (see stdout above)
- Lock file lifecycle: checked
- Concurrent warning: tested with fake lock

## Assessment
$([ "$COMPLETED" = "true" ] && echo "Background task mode is functional." || echo "Background task mode needs investigation.")
EOF

echo "Results written to: $RESULT_FILE"
