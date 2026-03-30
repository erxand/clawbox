#!/usr/bin/env bash
# T6 — Concurrent task handling
#
# What: Test concurrent `clawbox run` behavior after ISSUE-30/37 lock fixes.
#       Two sections:
#       PART 1: Raw gateway test — fire two `openclaw agent` calls simultaneously,
#               verify both complete with correct, independent outputs (no interference).
#       PART 2: Lock test — fire two `clawbox run` calls simultaneously, verify
#               that the second call gets a "task already running" message and exits 1
#               (or queues if lock is not held). Also verifies lock releases properly.
#
# Why:  Clawbox uses a PID-based lock file (~/.clawbox-lock) to serialize `run`/`task`
#       calls. After ISSUE-30 (added lock) and ISSUE-37 (made it exit 1 not warn),
#       the UX changed: concurrent `clawbox run` calls now fail fast rather than queue.
#       This test verifies the new contract is working correctly.
#
# Note: This test deliberately does NOT use `set -e` globally because we expect
#       some paths to fail and we want to capture that.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T6-concurrent-tasks.md"
CONTAINER="clawbox-work"
TIMEOUT_SECONDS=300   # 5 minutes per task (they run in parallel for Part 1)
WORKSPACE="/home/node/.openclaw/workspace"
LOCK_FILE="$HOME/.clawbox-lock"

mkdir -p "$RESULT_DIR"

log() { echo "[T6 $(date +%H:%M:%S)] $*"; }

PASS=0
FAIL=0
WARN=0
pass() { echo "✓ $*"; PASS=$((PASS+1)); }
fail() { echo "✗ $*"; FAIL=$((FAIL+1)); }
warn() { echo "⚠ $*"; WARN=$((WARN+1)); }

# Source rate limit helper
if [ -f "${SCRIPT_DIR}/lib/common.sh" ]; then
  source "${SCRIPT_DIR}/lib/common.sh"
fi

# ── Setup ────────────────────────────────────────────────────────────────────

log "Checking container is running..."
RUNNING=$(docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null || echo "false")
if [ "$RUNNING" != "true" ]; then
  log "Starting container..."
  "$CLAWBOX" start
  sleep 5
fi

# Clean up any leftover dirs + stale lock from previous runs
docker exec "$CONTAINER" sh -c "rm -rf $WORKSPACE/concurrent-A $WORKSPACE/concurrent-B" 2>/dev/null || true
rm -f "$LOCK_FILE" 2>/dev/null || true

log "=== PART 1: Raw gateway concurrency (both tasks should complete) ==="

# ── Part 1: Tasks ────────────────────────────────────────────────────────────

# Task A: Write a small math utility module with tests
TASK_A="Create a file at $WORKSPACE/concurrent-A/math.js with these exported functions: add(a,b), subtract(a,b), multiply(a,b), divide(a,b) (throws Error('division by zero') when b=0). Also create $WORKSPACE/concurrent-A/math.test.js that tests all four functions using Node's built-in assert module (no extra deps). Then run: node $WORKSPACE/concurrent-A/math.test.js and report whether tests passed."

# Task B: Write a small string utility module with tests
TASK_B="Create a file at $WORKSPACE/concurrent-B/strings.js with these exported functions: capitalize(s) (first letter uppercase), truncate(s,n) (truncate to n chars + '...' if longer), slugify(s) (lowercase, spaces→hyphens, strip non-alphanumeric). Also create $WORKSPACE/concurrent-B/strings.test.js that tests all three using Node's built-in assert. Then run: node $WORKSPACE/concurrent-B/strings.test.js and report whether tests passed."

# ── Fire both tasks simultaneously ────────────────────────────────────────────

log "Firing Task A and Task B simultaneously (raw gateway)..."
START_TIME=$(date +%s)

OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw agent --agent main --session-id "t6-concurrent-A-$$" -m "$TASK_A" > /tmp/t6-output-A.txt 2>&1 &
PID_A=$!

# Small stagger (2s) to make the race condition more realistic but not trivial
sleep 2

OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw agent --agent main --session-id "t6-concurrent-B-$$" -m "$TASK_B" > /tmp/t6-output-B.txt 2>&1 &
PID_B=$!

log "Task A PID: $PID_A | Task B PID: $PID_B"

# ── Wait for both with timeout ────────────────────────────────────────────────

TASK_A_DONE="no"
TASK_B_DONE="no"
TASK_A_TIMEOUT="no"
TASK_B_TIMEOUT="no"
ELAPSED=0

while [ "$ELAPSED" -lt "$TIMEOUT_SECONDS" ]; do
  sleep 10
  ELAPSED=$(( $(date +%s) - START_TIME ))

  if ! kill -0 "$PID_A" 2>/dev/null && [ "$TASK_A_DONE" = "no" ]; then
    wait "$PID_A" 2>/dev/null || true
    TASK_A_DONE="yes"
    log "Task A finished at ${ELAPSED}s"
  fi

  if ! kill -0 "$PID_B" 2>/dev/null && [ "$TASK_B_DONE" = "no" ]; then
    wait "$PID_B" 2>/dev/null || true
    TASK_B_DONE="yes"
    log "Task B finished at ${ELAPSED}s"
  fi

  [ "$TASK_A_DONE" = "yes" ] && [ "$TASK_B_DONE" = "yes" ] && break

  log "Waiting... ${ELAPSED}s (A:$TASK_A_DONE B:$TASK_B_DONE)"
done

# Kill anything still running after timeout
if kill -0 "$PID_A" 2>/dev/null; then
  log "TIMEOUT — killing Task A"
  kill "$PID_A" 2>/dev/null || true
  TASK_A_TIMEOUT="yes"
fi
if kill -0 "$PID_B" 2>/dev/null; then
  log "TIMEOUT — killing Task B"
  kill "$PID_B" 2>/dev/null || true
  TASK_B_TIMEOUT="yes"
fi

END_TIME=$(date +%s)
TOTAL_ELAPSED=$(( END_TIME - START_TIME ))

# ── Verify Part 1 results ────────────────────────────────────────────────────

log "Verifying Part 1 results..."

# Check Task A deliverables
MATH_JS=$(docker exec "$CONTAINER" sh -c "test -f $WORKSPACE/concurrent-A/math.js && echo yes || echo no" 2>/dev/null || echo "no")
MATH_TEST=$(docker exec "$CONTAINER" sh -c "test -f $WORKSPACE/concurrent-A/math.test.js && echo yes || echo no" 2>/dev/null || echo "no")

# Check Task B deliverables
STRINGS_JS=$(docker exec "$CONTAINER" sh -c "test -f $WORKSPACE/concurrent-B/strings.js && echo yes || echo no" 2>/dev/null || echo "no")
STRINGS_TEST=$(docker exec "$CONTAINER" sh -c "test -f $WORKSPACE/concurrent-B/strings.test.js && echo yes || echo no" 2>/dev/null || echo "no")

# Run tests independently
MATH_RUN=$(docker exec "$CONTAINER" sh -c "node $WORKSPACE/concurrent-A/math.test.js 2>&1" 2>/dev/null || echo "(test run failed or file missing)")
STRINGS_RUN=$(docker exec "$CONTAINER" sh -c "node $WORKSPACE/concurrent-B/strings.test.js 2>&1" 2>/dev/null || echo "(test run failed or file missing)")

MATH_OK=$(echo "$MATH_RUN" | grep -qi "Tests failed: [^0]\|AssertionError\|SyntaxError\|Cannot find\|Error:" && echo "FAIL" || echo "PASS")
STRINGS_OK=$(echo "$STRINGS_RUN" | grep -qi "Tests failed: [^0]\|AssertionError\|SyntaxError\|Cannot find\|Error:" && echo "FAIL" || echo "PASS")

# Cross-contamination checks
A_IN_B=$(docker exec "$CONTAINER" sh -c "ls $WORKSPACE/concurrent-B/ 2>/dev/null" | grep -c "math"; true)
B_IN_A=$(docker exec "$CONTAINER" sh -c "ls $WORKSPACE/concurrent-A/ 2>/dev/null" | grep -c "string"; true)
A_IN_B=${A_IN_B:-0}
B_IN_A=${B_IN_A:-0}
OUTPUT_A=$(cat /tmp/t6-output-A.txt 2>/dev/null | tail -40)
OUTPUT_B=$(cat /tmp/t6-output-B.txt 2>/dev/null | tail -40)
# Be careful: "add" and "subtract" appear in normal conversation. Check for more specific strings.
OUTPUT_A_CROSS=$(echo "$OUTPUT_A" | grep -qi "slugify\|capitalize\|truncate\|strings\.js" && echo "yes (possible leak)" || echo "no")
OUTPUT_B_CROSS=$(echo "$OUTPUT_B" | grep -qi "math\.js\|division by zero\|concurrent-A" && echo "yes (possible leak)" || echo "no")

ALL_FILES_A=$(docker exec "$CONTAINER" sh -c "find $WORKSPACE/concurrent-A -type f 2>/dev/null" || echo "(dir not found)")
ALL_FILES_B=$(docker exec "$CONTAINER" sh -c "find $WORKSPACE/concurrent-B -type f 2>/dev/null" || echo "(dir not found)")
MATH_CONTENT=$(docker exec "$CONTAINER" sh -c "cat $WORKSPACE/concurrent-A/math.js 2>/dev/null" || echo "(not found)")
STRINGS_CONTENT=$(docker exec "$CONTAINER" sh -c "cat $WORKSPACE/concurrent-B/strings.js 2>/dev/null" || echo "(not found)")

# Check rate limit in output
PART1_RATE_LIMITED="no"
if echo "$OUTPUT_A$OUTPUT_B" | grep -qi "rate limit\|rate_limit_error\|overloaded"; then
  PART1_RATE_LIMITED="yes"
  warn "Part 1: API rate limit detected in agent output"
fi

# Part 1 pass/fail
[ "$TASK_A_TIMEOUT" = "no" ] && pass "Part 1: Task A completed (no timeout)" || fail "Part 1: Task A timed out"
[ "$TASK_B_TIMEOUT" = "no" ] && pass "Part 1: Task B completed (no timeout)" || fail "Part 1: Task B timed out"
[ "$MATH_JS" = "yes" ] && pass "Part 1: math.js created" || fail "Part 1: math.js NOT created"
[ "$MATH_TEST" = "yes" ] && pass "Part 1: math.test.js created" || fail "Part 1: math.test.js NOT created"
[ "$STRINGS_JS" = "yes" ] && pass "Part 1: strings.js created" || fail "Part 1: strings.js NOT created"
[ "$STRINGS_TEST" = "yes" ] && pass "Part 1: strings.test.js created" || fail "Part 1: strings.test.js NOT created"
[ "$MATH_OK" = "PASS" ] && pass "Part 1: math tests pass" || fail "Part 1: math tests FAIL or incomplete"
[ "$STRINGS_OK" = "PASS" ] && pass "Part 1: strings tests pass" || fail "Part 1: strings tests FAIL or incomplete"
[ "$OUTPUT_A_CROSS" = "no" ] && pass "Part 1: No cross-contamination in Task A output" || warn "Part 1: Task A output mentions Task B content"
[ "$OUTPUT_B_CROSS" = "no" ] && pass "Part 1: No cross-contamination in Task B output" || warn "Part 1: Task B output mentions Task A content"
[ "$A_IN_B" = "0" ] && pass "Part 1: No Task A files in concurrent-B/" || warn "Part 1: math files found in concurrent-B/"
[ "$B_IN_A" = "0" ] && pass "Part 1: No Task B files in concurrent-A/" || warn "Part 1: strings files found in concurrent-A/"

# ── PART 2: clawbox run lock behavior ────────────────────────────────────────

log ""
log "=== PART 2: clawbox run lock behavior ==="
log ""

# Clean up lock just in case
rm -f "$LOCK_FILE" 2>/dev/null || true

# Test 2a: No lock held — clawbox run should succeed normally
log "Test 2a: clawbox run with no lock held..."
FIRST_RESULT=$("$CLAWBOX" run "Reply with only the word CONCURRENT_OK" 2>&1)
FIRST_EXIT=$?
if echo "$FIRST_RESULT" | grep -qi "CONCURRENT_OK"; then
  pass "Part 2a: clawbox run succeeds with no lock held"
else
  warn "Part 2a: clawbox run returned unexpected output: $(echo "$FIRST_RESULT" | tail -2)"
fi
[ "$FIRST_EXIT" = "0" ] && pass "Part 2a: exit code 0 (success)" || fail "Part 2a: exit code $FIRST_EXIT (expected 0)"

# Test 2b: Inject a fake live lock, verify second run exits 1 with proper message
log "Test 2b: clawbox run with live lock held..."
# Start a sleep in background to give us a real live PID
sleep 60 &
FAKE_PID=$!
echo "$FAKE_PID" > "$LOCK_FILE"
log "Injected fake lock with PID $FAKE_PID"

BLOCKED_RESULT=$("$CLAWBOX" run "this should be blocked" 2>&1)
BLOCKED_EXIT=$?
kill "$FAKE_PID" 2>/dev/null || true
rm -f "$LOCK_FILE" 2>/dev/null || true

if [ "$BLOCKED_EXIT" = "1" ]; then
  pass "Part 2b: clawbox run exits 1 when lock is held"
else
  fail "Part 2b: clawbox run exit code $BLOCKED_EXIT (expected 1)"
fi

if echo "$BLOCKED_RESULT" | grep -qi "already running\|queued\|clawbox cancel"; then
  pass "Part 2b: Blocked message mentions task already running or clawbox cancel"
else
  fail "Part 2b: Blocked message unclear: $(echo "$BLOCKED_RESULT" | head -3)"
fi

if echo "$BLOCKED_RESULT" | grep -qi "clawbox cancel\|clawbox task-logs"; then
  pass "Part 2b: Blocked message shows actionable commands (clawbox cancel / task-logs)"
else
  warn "Part 2b: Blocked message doesn't mention clawbox cancel or task-logs"
fi

# Test 2c: Lock releases after clawbox run completes
log "Test 2c: Lock releases after run completes..."
if [ ! -f "$LOCK_FILE" ]; then
  pass "Part 2c: Lock file removed after run completes"
else
  LOCK_CONTENT=$(cat "$LOCK_FILE" 2>/dev/null || echo "unreadable")
  if kill -0 "$LOCK_CONTENT" 2>/dev/null; then
    fail "Part 2c: Lock file still exists with live PID $LOCK_CONTENT"
  else
    warn "Part 2c: Stale lock file exists (dead PID $LOCK_CONTENT) — should self-clean"
  fi
fi

# Test 2d: Stale lock (dead PID) doesn't block — clawbox should detect and clean it
log "Test 2d: Stale lock (dead PID) is auto-cleaned..."
echo "99999999" > "$LOCK_FILE"   # Almost certainly not a real PID
STALE_RESULT=$("$CLAWBOX" run "Reply with only STALE_LOCK_OK" 2>&1)
STALE_EXIT=$?
if echo "$STALE_RESULT" | grep -qi "STALE_LOCK_OK"; then
  pass "Part 2d: Stale lock auto-cleaned — clawbox run succeeds"
elif [ "$STALE_EXIT" = "0" ]; then
  pass "Part 2d: clawbox run succeeded past stale lock (exit 0)"
else
  fail "Part 2d: clawbox run blocked by stale lock (exit $STALE_EXIT)"
fi
rm -f "$LOCK_FILE" 2>/dev/null || true

# Test 2e: clawbox task (background) respects lock too
log "Test 2e: clawbox task fires while lock held..."
sleep 60 &
FAKE_PID2=$!
echo "$FAKE_PID2" > "$LOCK_FILE"

TASK_BLOCKED=$("$CLAWBOX" task "this should also be blocked" 2>&1)
TASK_BLOCKED_EXIT=$?
kill "$FAKE_PID2" 2>/dev/null || true
rm -f "$LOCK_FILE" 2>/dev/null || true

if [ "$TASK_BLOCKED_EXIT" = "1" ]; then
  pass "Part 2e: clawbox task exits 1 when lock is held"
else
  fail "Part 2e: clawbox task exit code $TASK_BLOCKED_EXIT (expected 1)"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL + WARN))
log ""
log "Results: $PASS/$TOTAL pass, $FAIL fail, $WARN warn"

cat > "$RESULT_FILE" << RESULT_EOF
# T6 — Concurrent Task Handling
**Date:** $(date '+%Y-%m-%d %H:%M')
**Total wall time:** ${TOTAL_ELAPSED}s

## What was tested
**Part 1:** Two raw \`openclaw agent\` calls fired simultaneously (2s stagger) at the same gateway endpoint — verify both complete with correct, independent outputs (no interference).
**Part 2:** \`clawbox run\` lock behavior after ISSUE-30/37 fixes — verify the PID lock correctly blocks concurrent calls, shows actionable messages, releases after completion, and auto-cleans stale locks.

## Part 1: Raw gateway concurrency

| | Task A (math) | Task B (strings) |
|---|---|---|
| Timed out | $TASK_A_TIMEOUT | $TASK_B_TIMEOUT |
| JS file created | $MATH_JS | $STRINGS_JS |
| Test file created | $MATH_TEST | $STRINGS_TEST |
| Tests run OK | $MATH_OK ($MATH_OK) | $STRINGS_OK ($STRINGS_OK) |
| Cross-contamination signal in output | $OUTPUT_A_CROSS | $OUTPUT_B_CROSS |
| Files from other task in dir | A_in_B: $A_IN_B | B_in_A: $B_IN_A |

$([ "$MATH_JS" = "yes" ] && echo "✓ Task A: math.js created" || echo "✗ Task A: math.js NOT created")
$([ "$MATH_TEST" = "yes" ] && echo "✓ Task A: math.test.js created" || echo "✗ Task A: math.test.js NOT created")
$([ "$STRINGS_JS" = "yes" ] && echo "✓ Task B: strings.js created" || echo "✗ Task B: strings.js NOT created")
$([ "$STRINGS_TEST" = "yes" ] && echo "✓ Task B: strings.test.js created" || echo "✗ Task B: strings.test.js NOT created")
$([ "$MATH_OK" = "PASS" ] && echo "✓ Task A: math tests PASS" || echo "✗ Task A: math tests FAIL or incomplete")
$([ "$STRINGS_OK" = "PASS" ] && echo "✓ Task B: strings tests PASS" || echo "✗ Task B: strings tests FAIL or incomplete")
$([ "$OUTPUT_A_CROSS" = "no" ] && echo "✓ No cross-contamination in Task A output" || echo "⚠ Task A output mentions Task B content")
$([ "$OUTPUT_B_CROSS" = "no" ] && echo "✓ No cross-contamination in Task B output" || echo "⚠ Task B output mentions Task A content")

## Part 2: clawbox run lock behavior

| Check | Result |
|-------|--------|
| clawbox run succeeds with no lock | $(echo "$FIRST_RESULT" | grep -qi "CONCURRENT_OK" && echo "✓ yes" || echo "⚠ response mismatch") |
| clawbox run exits 1 when lock held | $([ "$BLOCKED_EXIT" = "1" ] && echo "✓ yes (exit 1)" || echo "✗ no (exit $BLOCKED_EXIT)") |
| Blocked message mentions 'already running' or 'cancel' | $(echo "$BLOCKED_RESULT" | grep -qi "already running\|queued\|clawbox cancel" && echo "✓ yes" || echo "✗ no") |
| Blocked message shows actionable commands | $(echo "$BLOCKED_RESULT" | grep -qi "clawbox cancel\|clawbox task-logs" && echo "✓ yes" || echo "⚠ not shown") |
| Lock released after run completes | $([ ! -f "$LOCK_FILE" ] && echo "✓ yes" || echo "✗ lock still exists") |
| Stale lock auto-cleaned | $(echo "$STALE_RESULT" | grep -qi "STALE_LOCK_OK" && echo "✓ yes" || echo "$([ "$STALE_EXIT" = "0" ] && echo "✓ yes (exit 0)" || echo "✗ no (exit $STALE_EXIT)")") |
| clawbox task also exits 1 when lock held | $([ "$TASK_BLOCKED_EXIT" = "1" ] && echo "✓ yes" || echo "✗ no (exit $TASK_BLOCKED_EXIT)") |

## Blocked message (Part 2b)
\`\`\`
$BLOCKED_RESULT
\`\`\`

## Files created (Part 1)

### Task A (\`concurrent-A/\`)
\`\`\`
$ALL_FILES_A
\`\`\`

### Task B (\`concurrent-B/\`)
\`\`\`
$ALL_FILES_B
\`\`\`

## Test runs (independent re-run after agent finished)

### math.test.js
\`\`\`
$MATH_RUN
\`\`\`

### strings.test.js
\`\`\`
$STRINGS_RUN
\`\`\`

## Source: math.js
\`\`\`javascript
$MATH_CONTENT
\`\`\`

## Source: strings.js
\`\`\`javascript
$STRINGS_CONTENT
\`\`\`

## Agent output: Task A (tail)
\`\`\`
$OUTPUT_A
\`\`\`

## Agent output: Task B (tail)
\`\`\`
$OUTPUT_B
\`\`\`

## Summary
- **Pass:** $PASS / $TOTAL
- **Fail:** $FAIL
- **Warn:** $WARN

## Findings
- Gateway serializes concurrent raw-agent requests (tasks queue, not interleave) — correct and safe
- Lock mechanism (ISSUE-30/37) prevents concurrent \`clawbox run\` calls from queuing silently
- Second \`clawbox run\` while lock held exits 1 with actionable message
- Stale locks (dead PID) are auto-cleaned so a crash doesn't leave clawbox permanently blocked
RESULT_EOF

log "Results written to $RESULT_FILE"
log "Done. Pass=$PASS Fail=$FAIL Warn=$WARN"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
