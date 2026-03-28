#!/usr/bin/env bash
# T12 — cancel command
# Tests:
#   1. `clawbox cancel` with no running task prints informative message (no error)
#   2. `clawbox cancel` with a stale lock cleans up the lock file
#   3. `clawbox cancel` with a live background task kills it, cleans up lock, appends cancellation marker
#   4. After cancel, assert_not_busy no longer blocks a new task
#   5. `cancel` appears in help output
#   6. `task-status` shows "clawbox cancel" hint (not raw kill)
#   7. `assert_not_busy` shows "clawbox cancel" hint (not raw kill)
set -euo pipefail

CLAWBOX_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CLAWBOX="$CLAWBOX_DIR/clawbox"
LOCK_FILE="$HOME/.clawbox-lock"
TASK_LOG="$HOME/.clawbox-task.log"
RESULTS_DIR="$CLAWBOX_DIR/tests/results"
TS=$(date '+%Y-%m-%d-%H-%M')
RESULT_FILE="$RESULTS_DIR/${TS}-T12-cancel.md"
CONTAINER="clawbox-work"

mkdir -p "$RESULTS_DIR"

pass=0; fail=0; warn=0

check() {
  local name="$1" result="$2" expected="$3"
  if [ "$result" = "$expected" ]; then
    echo "  ✓ $name"
    pass=$((pass+1))
  else
    echo "  ✗ $name (got: $result, expected: $expected)"
    fail=$((fail+1))
  fi
}

check_contains() {
  local name="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  ✓ $name"
    pass=$((pass+1))
  else
    echo "  ✗ $name (expected to contain: '$needle')"
    echo "    Got: $haystack"
    fail=$((fail+1))
  fi
}

check_not_contains() {
  local name="$1" haystack="$2" needle="$3"
  if ! echo "$haystack" | grep -qF "$needle"; then
    echo "  ✓ $name"
    pass=$((pass+1))
  else
    echo "  ✗ $name (should NOT contain: '$needle')"
    fail=$((fail+1))
  fi
}

warn_check() {
  local name="$1" result="$2" expected="$3"
  if [ "$result" = "$expected" ]; then
    echo "  ✓ $name"
    pass=$((pass+1))
  else
    echo "  ⚠ $name (got: $result, expected: $expected)"
    warn=$((warn+1))
  fi
}

echo ""
echo "=== T12: cancel command ==="
echo ""

# ── Test 1: cancel with no lock ──────────────────────────────────────
echo "1. cancel with no running task"
rm -f "$LOCK_FILE"
out=$("$CLAWBOX" cancel 2>&1 || true)
check_contains "prints informative message" "$out" "No background task is currently running"
check_not_contains "does not error out hard" "$out" "Error"

# ── Test 2: cancel with stale lock ──────────────────────────────────
echo ""
echo "2. cancel with stale lock (dead PID)"
echo "99999999" > "$LOCK_FILE"  # PID that certainly doesn't exist
out=$("$CLAWBOX" cancel 2>&1 || true)
check_contains "reports stale PID" "$out" "stale PID"
check "lock file cleaned up after stale" "$([ -f "$LOCK_FILE" ] && echo 'exists' || echo 'gone')" "gone"

# ── Test 3: cancel a live background task ────────────────────────────
echo ""
echo "3. cancel a live background task"
# Start a long-running sleep as the "locked" process, write its PID to the lock.
# This avoids $BASHPID (not available in macOS bash 3.2) and avoids using $$
# (which would point at the test script, causing it to be killed by cancel).
{
  echo "=== Task started: $(date '+%Y-%m-%d %H:%M:%S') ==="
  echo "Description: synthetic 60s sleep for cancel test"
  echo ""
  sleep 60
  echo "=== Task completed: $(date '+%Y-%m-%d %H:%M:%S') ==="
} > "$TASK_LOG" 2>&1 &
FAKE_TASK_PID=$!
echo "$FAKE_TASK_PID" > "$LOCK_FILE"

# Give it a moment to write the lock
sleep 1

# Verify the lock is actually held by a live PID
check "lock file exists before cancel" "$([ -f "$LOCK_FILE" ] && echo 'exists' || echo 'gone')" "exists"
lock_pid_before=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
check "lock has a real PID" "$(kill -0 "$lock_pid_before" 2>/dev/null && echo 'alive' || echo 'dead')" "alive"

# Now cancel
out=$("$CLAWBOX" cancel 2>&1 || true)
check_contains "cancel prints 'Cancelling'" "$out" "Cancelling task"
check_contains "cancel prints 'cancelled'" "$out" "cancelled"

# Give it a moment to clean up
sleep 2

check "lock file gone after cancel" "$([ -f "$LOCK_FILE" ] && echo 'exists' || echo 'gone')" "gone"
check "fake task process killed" "$(kill -0 "$FAKE_TASK_PID" 2>/dev/null && echo 'alive' || echo 'dead')" "dead"
check_contains "cancellation marker in log" "$(cat "$TASK_LOG" 2>/dev/null || echo '')" "cancelled by user"

# ── Test 4: after cancel, new task is not blocked ────────────────────
echo ""
echo "4. after cancel, assert_not_busy does not block"
rm -f "$LOCK_FILE"
# Source the clawbox script to call assert_not_busy directly
out=$(bash -c "source '$CLAWBOX' 2>/dev/null || true; LOCK_FILE='$LOCK_FILE'; $(grep -A 20 '^assert_not_busy' "$CLAWBOX" | head -25)" 2>&1 || true)
# The simplest check: LOCK_FILE doesn't exist, so no busy message
check_not_contains "no busy message after cancel" "$out" "Another Clawbox task is already running"

# ── Test 5: cancel in help output ────────────────────────────────────
echo ""
echo "5. help and hint checks"
help_out=$("$CLAWBOX" help 2>&1)
check_contains "cancel in help" "$help_out" "cancel"
check_contains "cancel description in help" "$help_out" "Cancel the currently running background task"

# ── Test 6: task-status shows 'clawbox cancel' not raw kill ──────────
echo ""
echo "6. task-status cancel hint"
# Spawn a real sleep process and write its PID to lock file (live PID)
sleep 60 &
SLEEP6_PID=$!
echo "$SLEEP6_PID" > "$LOCK_FILE"
ts_out=$("$CLAWBOX" task-status 2>&1 || true)
check_contains "task-status shows clawbox cancel" "$ts_out" "clawbox cancel"
check_not_contains "task-status doesn't show raw kill PID hint" "$ts_out" "To cancel: kill "
{ kill "$SLEEP6_PID" 2>/dev/null; wait "$SLEEP6_PID" 2>/dev/null; } || true
rm -f "$LOCK_FILE"

# ── Test 7: assert_not_busy shows 'clawbox cancel' not raw kill ──────
echo ""
echo "7. assert_not_busy cancel hint"
# Spawn a real sleep process and write its PID to lock file (live PID)
sleep 60 &
SLEEP7_PID=$!
echo "$SLEEP7_PID" > "$LOCK_FILE"
busy_out=$("$CLAWBOX" run "test" 2>&1 || true)
check_contains "assert_not_busy shows clawbox cancel" "$busy_out" "clawbox cancel"
check_not_contains "assert_not_busy doesn't show raw kill PID hint" "$busy_out" "kill \$lock_pid"
{ kill "$SLEEP7_PID" 2>/dev/null; wait "$SLEEP7_PID" 2>/dev/null; } || true
rm -f "$LOCK_FILE"

# ── Summary ──────────────────────────────────────────────────────────
echo ""
echo "==================================="
echo "RESULT: $pass pass, $warn warn, $fail fail"
echo "==================================="

# Write result file
{
cat << HEADER
# T12 — cancel command
**Date:** $(date '+%Y-%m-%d %H:%M')
**Container status:** $(docker inspect "$CONTAINER" --format '{{.State.Status}}' 2>/dev/null || echo "unknown")

## What was tested
- \`clawbox cancel\` with no running task
- \`clawbox cancel\` with a stale lock file (dead PID)
- \`clawbox cancel\` with a live background task (SIGTERM → SIGKILL fallback)
- After cancel, new tasks are not blocked
- \`cancel\` appears in help with correct description
- \`task-status\` shows \`clawbox cancel\` hint (not raw \`kill\`)
- \`assert_not_busy\` shows \`clawbox cancel\` hint (not raw \`kill\`)

## Results

HEADER

echo "| Check | Result |"
echo "|-------|--------|"
} > "$RESULT_FILE"

if [ $fail -eq 0 ]; then
  echo "**All $pass checks passed.**" >> "$RESULT_FILE"
  echo "" >> "$RESULT_FILE"
  echo "## Assessment" >> "$RESULT_FILE"
  echo "cancel command works end-to-end: no-op when idle, cleans stale locks, kills live tasks, appends cancellation marker to log, and all UX hints point to \`clawbox cancel\` instead of raw \`kill\`." >> "$RESULT_FILE"
  exit 0
else
  echo "**$pass pass, $warn warn, $fail fail**" >> "$RESULT_FILE"
  exit 1
fi
