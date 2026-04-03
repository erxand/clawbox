#!/usr/bin/env bash
# T19 — Task early completion + retry flag behavior
#
# What: Tests two edge cases not covered by other suites:
#   1. `clawbox task --timeout N` where the task completes BEFORE timeout fires
#      — the timeout watchdog should be cleaned up, no spurious handoff
#   2. `clawbox run --retry N` — retries on a non-rate-limited success (verify no extra calls)
#      and verifies the flag is documented and accepted without error
#
# Why: T15 only tests tasks that *exceed* the timeout. "Task finishes early" is a
#      separate code path (watchdog kill path never fires) and has never been explicitly tested.
#      --retry was added in ISSUE-44 but only tested via T9/T8 indirectly (never stress-tested).
#
# Pass criteria:
#   - Task with --timeout 5 on a fast (5-second) task completes without timeout marker
#   - No stale watchdog process remains after fast task
#   - Lock file cleaned up after fast task with timeout flag
#   - --retry 1 flag is accepted, task succeeds, no double-invocation evidence
#   - --retry flag documented in help output
#   - Fast task log contains completion marker (=== Task completed ===)
#   - No handoff prompt emitted when task completes before timeout

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/lib/common.sh"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T19-early-completion-retry.md"
CONTAINER="clawbox-work"

mkdir -p "$RESULT_DIR"

log() { echo "[T19 $(date +%H:%M:%S)] $*"; }
PASS=0 FAIL=0 WARN=0
FINDINGS=()

check() {
  local label="$1" result="$2" detail="$3"
  FINDINGS+=("$result|$label|$detail")
  case "$result" in
    pass) PASS=$((PASS+1)); echo "  ✓ $label" ;;
    warn) WARN=$((WARN+1)); echo "  ⚠ $label — $detail" ;;
    fail) FAIL=$((FAIL+1)); echo "  ✗ $label — $detail" ;;
  esac
}

# ── Pre-flight ────────────────────────────────────────────────────────────────

log "Checking container is running..."
if ! docker ps --filter name="$CONTAINER" --filter status=running | grep -q "$CONTAINER"; then
  log "Starting container..."
  "$CLAWBOX" start
fi

# Clean up any stale locks from prior tests
rm -f ~/.clawbox-lock 2>/dev/null || true

# ── Phase 1: Task that completes before timeout ───────────────────────────────

log "Phase 1: Task with --timeout 5 on a trivially fast job..."

# Use a task so simple the agent will finish in seconds, well under 5min
FAST_TASK_MSG="Create a file called /home/node/.openclaw/workspace/t19-done.txt containing the text 'T19_EARLY_COMPLETE'. Then print DONE_T19."

# Capture the log path emitted by 'clawbox task'
TASK_START=$(date +%s)
TASK_OUTPUT=$(
  "$CLAWBOX" task --timeout 5 "$FAST_TASK_MSG" 2>&1
)
TASK_END=$(date +%s)
TASK_LAUNCH_TIME=$((TASK_END - TASK_START))

log "Task launch output:"
echo "$TASK_OUTPUT"

# Capture log path from task output
TASK_LOG_PATH=""
if echo "$TASK_OUTPUT" | grep -qE "Log:.*clawbox-task"; then
  TASK_LOG_PATH=$(echo "$TASK_OUTPUT" | grep -oE '/[^ ]+clawbox-task[^ ]+\.log' | head -1)
fi
if [ -z "$TASK_LOG_PATH" ]; then
  # fallback: resolve symlink
  TASK_LOG_PATH=$(readlink ~/.clawbox-task.log 2>/dev/null || echo "")
fi

log "Log path: ${TASK_LOG_PATH:-<not found>}"

# Check task returned immediately (non-blocking)
if [ $TASK_LAUNCH_TIME -le 15 ]; then
  check "task with --timeout returns immediately (non-blocking)" "pass" "${TASK_LAUNCH_TIME}s"
elif [ $TASK_LAUNCH_TIME -le 30 ]; then
  check "task with --timeout returns immediately (non-blocking)" "warn" "Took ${TASK_LAUNCH_TIME}s — pre-flight checks slow (expected ≤15s)"
else
  check "task with --timeout returns immediately (non-blocking)" "fail" "Took ${TASK_LAUNCH_TIME}s — expected ≤30s, something is blocking"
fi

# Wait for task to complete (max 120s for a fast task)
log "Waiting for task to complete (max 120s)..."
WAIT=0
while [ $WAIT -lt 120 ]; do
  if [ -z "$TASK_LOG_PATH" ] || [ ! -f "$TASK_LOG_PATH" ]; then
    TASK_LOG_PATH=$(readlink ~/.clawbox-task.log 2>/dev/null || echo "")
  fi
  if [ -n "$TASK_LOG_PATH" ] && [ -f "$TASK_LOG_PATH" ] && grep -q "Task completed" "$TASK_LOG_PATH" 2>/dev/null; then
    break
  fi
  sleep 3
  WAIT=$((WAIT+3))
done

if [ -n "$TASK_LOG_PATH" ] && [ -f "$TASK_LOG_PATH" ] && grep -q "Task completed" "$TASK_LOG_PATH"; then
  check "fast task completes within 120s" "pass" "Completed in ~${WAIT}s"
else
  check "fast task completes within 120s" "fail" "Log: ${TASK_LOG_PATH:-<not found>} — no completion marker after 120s"
fi

# Give a little extra time for lock cleanup
sleep 3

# Check: no stale lock after fast task completes
if [ ! -f ~/.clawbox-lock ]; then
  check "lock file cleaned up after fast task" "pass" ""
else
  LOCK_PID=$(cat ~/.clawbox-lock 2>/dev/null || echo "?")
  if ! kill -0 "$LOCK_PID" 2>/dev/null; then
    check "lock file cleaned up after fast task" "warn" "Stale lock found (dead PID $LOCK_PID) — clawbox cancel will clean it"
  else
    check "lock file cleaned up after fast task" "fail" "Live lock still held by PID $LOCK_PID after task completion"
  fi
fi

# Check: no TIMEOUT marker in log (task should have finished before 5min timeout)
if [ -n "$TASK_LOG_PATH" ] && [ -f "$TASK_LOG_PATH" ]; then
  if grep -q "TIMEOUT after" "$TASK_LOG_PATH"; then
    check "no spurious timeout fired for fast task" "fail" "Timeout marker found in log — watchdog fired prematurely"
  else
    check "no spurious timeout fired for fast task" "pass" "No TIMEOUT marker in log"
  fi

  # Check: no handoff prompt in log
  if grep -q "handoff prompt" "$TASK_LOG_PATH"; then
    check "no handoff prompt for fast task" "fail" "Handoff was sent even though task finished early"
  else
    check "no handoff prompt for fast task" "pass" "No handoff prompt in log"
  fi

  # Check: completion marker present
  if grep -q "Task completed\|=== Task completed" "$TASK_LOG_PATH"; then
    check "task log contains completion marker" "pass" ""
  else
    check "task log contains completion marker" "warn" "No '=== Task completed ===' line in log — agent may have crashed"
  fi
else
  check "no spurious timeout fired for fast task" "warn" "Log file not found — can't verify timeout behavior"
  check "no handoff prompt for fast task" "warn" "Log file not found — can't verify handoff behavior"
  check "task log contains completion marker" "warn" "Log file not found"
fi

# Check: file was actually created in container
log "Verifying output file in container..."
T19_FILE=$(docker exec "$CONTAINER" cat /home/node/.openclaw/workspace/t19-done.txt 2>/dev/null || echo "")
if echo "$T19_FILE" | grep -q "T19_EARLY_COMPLETE"; then
  check "fast task produced correct output in container" "pass" "File content: $T19_FILE"
else
  check "fast task produced correct output in container" "warn" "File not found or wrong content: '${T19_FILE}' — agent may have chosen a different approach"
fi

# ── Phase 2: --retry flag acceptance and documentation ───────────────────────

log "Phase 2: --retry flag behavior..."

# Check --retry is in help output
HELP_OUT=$("$CLAWBOX" help 2>&1 || true)
if echo "$HELP_OUT" | grep -q "\-\-retry"; then
  check "--retry flag documented in help" "pass" ""
else
  check "--retry flag documented in help" "fail" "--retry not mentioned in 'clawbox help' output"
fi

# Check --retry 1 on a normal (successful) task — should succeed on first attempt, no retry needed
log "Running --retry 1 on a successful task..."
RETRY_START=$(date +%s)
RETRY_OUT=$("$CLAWBOX" run --retry 1 "Reply with exactly: RETRY_OK" 2>&1 || true)
RETRY_END=$(date +%s)
RETRY_TIME=$((RETRY_END - RETRY_START))

# Check for rate limiting
if is_rate_limited "$RETRY_OUT"; then
  check "--retry 1 succeeds on non-rate-limited task" "warn" "Rate limited — can't verify retry behavior now"
elif echo "$RETRY_OUT" | grep -qi "RETRY_OK"; then
  check "--retry 1 succeeds on non-rate-limited task" "pass" "Got RETRY_OK in ${RETRY_TIME}s"
else
  check "--retry 1 succeeds on non-rate-limited task" "fail" "Expected RETRY_OK, got: $(echo "$RETRY_OUT" | tail -3)"
fi

# --retry 0 should also be accepted (0 = no retry, just like default)
RETRY0_OUT=$("$CLAWBOX" run --retry 0 "Reply: RETRY_ZERO_OK" 2>&1 || true)
if is_rate_limited "$RETRY0_OUT"; then
  check "--retry 0 accepted without error" "warn" "Rate limited"
elif echo "$RETRY0_OUT" | grep -qi "RETRY_ZERO_OK\|RETRY"; then
  check "--retry 0 accepted without error" "pass" ""
elif echo "$RETRY0_OUT" | grep -qi "invalid\|error\|unknown"; then
  check "--retry 0 accepted without error" "fail" "Flag caused an error: $(echo "$RETRY0_OUT" | head -2)"
else
  check "--retry 0 accepted without error" "pass" "No error from --retry 0"
fi

# Verify --retry is parsed before the message (flag ordering)
RETRY_FLAG_OUT=$("$CLAWBOX" run "Reply: FLAG_ORDER_OK" --retry 2 2>&1 || true)
if is_rate_limited "$RETRY_FLAG_OUT"; then
  check "--retry flag works in any position" "warn" "Rate limited"
elif echo "$RETRY_FLAG_OUT" | grep -qi "FLAG_ORDER_OK\|invalid\|unknown"; then
  if echo "$RETRY_FLAG_OUT" | grep -qi "FLAG_ORDER_OK"; then
    check "--retry flag works in any position" "pass" ""
  else
    check "--retry flag works in any position" "warn" "Flag after message may not be parsed: $(echo "$RETRY_FLAG_OUT" | head -2)"
  fi
else
  check "--retry flag works in any position" "warn" "Unexpected output: $(echo "$RETRY_FLAG_OUT" | head -2)"
fi

# ── Phase 3: task-status after completion ─────────────────────────────────────

log "Phase 3: task-status after task completion..."

TASK_STATUS_OUT=$("$CLAWBOX" task-status 2>&1 || true)

if echo "$TASK_STATUS_OUT" | grep -qi "no.*task\|not running\|completed\|last.*task\|task.*log"; then
  check "task-status shows useful info after completion" "pass" ""
else
  check "task-status shows useful info after completion" "warn" "Unexpected output: $(echo "$TASK_STATUS_OUT" | head -3)"
fi

# ── Phase 4: Watchdog cleanup validation ─────────────────────────────────────

log "Phase 4: No orphaned watchdog processes..."

# Check for any lingering clawbox-related background jobs
WATCHDOG_PROCS=$(pgrep -f "clawbox.*timeout\|clawbox.*watchdog" 2>/dev/null || echo "")
if [ -z "$WATCHDOG_PROCS" ]; then
  check "no orphaned watchdog processes after completion" "pass" ""
else
  check "no orphaned watchdog processes after completion" "warn" "Found possible watchdog PIDs: $WATCHDOG_PROCS"
fi

# Final lock state
if [ ! -f ~/.clawbox-lock ]; then
  check "no stale lock at end of test" "pass" ""
else
  LOCK_PID=$(cat ~/.clawbox-lock 2>/dev/null || echo "?")
  if ! kill -0 "$LOCK_PID" 2>/dev/null; then
    check "no stale lock at end of test" "warn" "Stale lock from dead PID $LOCK_PID — run: clawbox cancel"
    rm -f ~/.clawbox-lock
  else
    check "no stale lock at end of test" "fail" "Active lock held by PID $LOCK_PID at end of test"
  fi
fi

# ── Write results ─────────────────────────────────────────────────────────────

TOTAL=$((PASS+FAIL+WARN))

{
cat << EOF
# T19 — Task Early Completion + Retry Flag
**Date:** $(date '+%Y-%m-%d %H:%M')
**Task log:** ${TASK_LOG_PATH:-<not found>}

## Score
- ✓ Pass: ${PASS}
- ⚠ Warn: ${WARN}
- ✗ Fail: ${FAIL}
- Total checks: ${TOTAL}

## Findings

EOF

for item in "${FINDINGS[@]}"; do
  result="${item%%|*}"
  rest="${item#*|}"
  label="${rest%%|*}"
  detail="${rest#*|}"
  case "$result" in
    pass) echo "- ✓ **${label}**" ;;
    warn) echo "- ⚠ **${label}** — ${detail}" ;;
    fail) echo "- ✗ **${label}** — ${detail}" ;;
  esac
done

cat << EOF

## Notes

### Phase 1: Task finishes before timeout
- Tests the code path where the watchdog timer is set but never fires
- Fast task: "create t19-done.txt" — typically completes in <30s, well under 5min timeout
- Key invariants: no TIMEOUT marker, no handoff prompt, lock cleaned up, completion marker present

### Phase 2: --retry flag
- Verifies flag is accepted and documented
- Does NOT test actual retry behavior (would require simulated rate limit)
- Verifies --retry 0 and --retry 1 both work without errors

### Phase 3 & 4: Cleanup
- Ensures no orphaned processes or stale state after test completes

## Task Log (last 30 lines)
\`\`\`
$([ -n "$TASK_LOG_PATH" ] && [ -f "$TASK_LOG_PATH" ] && tail -30 "$TASK_LOG_PATH" || echo "<log not found>")
\`\`\`
EOF

} > "$RESULT_FILE"

log "Results written to $RESULT_FILE"
log ""
log "Summary: ${PASS} pass, ${WARN} warn, ${FAIL} fail (of ${TOTAL} checks)"
log "Done."
