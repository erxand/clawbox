#!/usr/bin/env bash
# T6 — Concurrent task handling
#
# What: Fire two `clawbox run` commands simultaneously and observe behavior.
#       One task writes to dir-A, the other to dir-B. Check if both complete,
#       if the outputs are correct, and whether there's interference.
#
# Why:  Clawbox exposes a single OpenClaw session. Two concurrent `openclaw agent`
#       calls hitting the same ws://localhost:18790 endpoint could:
#         (a) queue properly — both complete independently
#         (b) interleave — responses are garbled or mixed
#         (c) collide — second request fails or gets first's output
#         (d) silently drop — one request disappears
#
# Good: Both tasks complete with correct, independent outputs. No cross-contamination.
# Bad:  Tasks interfere with each other, outputs are wrong, or one task fails silently.
#
# Note: This test deliberately does NOT use `set -e` globally because we expect
#       one path (parallel jobs) to potentially fail and we want to capture that.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T6-concurrent-tasks.md"
CONTAINER="clawbox-work"
TIMEOUT_SECONDS=300   # 5 minutes per task (they run in parallel)
WORKSPACE="/home/node/.openclaw/workspace"

mkdir -p "$RESULT_DIR"

log() { echo "[T6 $(date +%H:%M:%S)] $*"; }

# ── Setup ────────────────────────────────────────────────────────────────────

log "Checking container is running..."
RUNNING=$(docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null || echo "false")
if [ "$RUNNING" != "true" ]; then
  log "Starting container..."
  "$CLAWBOX" start
  sleep 5
fi

# Clean up any leftover dirs from previous runs
docker exec "$CONTAINER" sh -c "rm -rf $WORKSPACE/concurrent-A $WORKSPACE/concurrent-B" 2>/dev/null || true

# ── Tasks ────────────────────────────────────────────────────────────────────

# Task A: Write a small math utility module with tests
TASK_A="Create a file at $WORKSPACE/concurrent-A/math.js with these exported functions: add(a,b), subtract(a,b), multiply(a,b), divide(a,b) (throws Error('division by zero') when b=0). Also create $WORKSPACE/concurrent-A/math.test.js that tests all four functions using Node's built-in assert module (no extra deps). Then run: node $WORKSPACE/concurrent-A/math.test.js and report whether tests passed."

# Task B: Write a small string utility module with tests  
TASK_B="Create a file at $WORKSPACE/concurrent-B/strings.js with these exported functions: capitalize(s) (first letter uppercase), truncate(s,n) (truncate to n chars + '...' if longer), slugify(s) (lowercase, spaces→hyphens, strip non-alphanumeric). Also create $WORKSPACE/concurrent-B/strings.test.js that tests all three using Node's built-in assert. Then run: node $WORKSPACE/concurrent-B/strings.test.js and report whether tests passed."

# ── Fire both tasks simultaneously ────────────────────────────────────────────

log "Firing Task A and Task B simultaneously..."
START_TIME=$(date +%s)

OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw agent --agent main -m "$TASK_A" > /tmp/t6-output-A.txt 2>&1 &
PID_A=$!

# Small stagger (2s) to make the race condition more realistic but not trivial
sleep 2

OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw agent --agent main -m "$TASK_B" > /tmp/t6-output-B.txt 2>&1 &
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

# ── Verify results ────────────────────────────────────────────────────────────

log "Verifying results..."

# Check Task A deliverables
MATH_JS=$(docker exec "$CONTAINER" sh -c "test -f $WORKSPACE/concurrent-A/math.js && echo yes || echo no" 2>/dev/null || echo "no")
MATH_TEST=$(docker exec "$CONTAINER" sh -c "test -f $WORKSPACE/concurrent-A/math.test.js && echo yes || echo no" 2>/dev/null || echo "no")

# Check Task B deliverables
STRINGS_JS=$(docker exec "$CONTAINER" sh -c "test -f $WORKSPACE/concurrent-B/strings.js && echo yes || echo no" 2>/dev/null || echo "no")
STRINGS_TEST=$(docker exec "$CONTAINER" sh -c "test -f $WORKSPACE/concurrent-B/strings.test.js && echo yes || echo no" 2>/dev/null || echo "no")

# Run tests independently (not via agent, just verify they work)
MATH_RUN=$(docker exec "$CONTAINER" sh -c "node $WORKSPACE/concurrent-A/math.test.js 2>&1" 2>/dev/null || echo "(test run failed or file missing)")
STRINGS_RUN=$(docker exec "$CONTAINER" sh -c "node $WORKSPACE/concurrent-B/strings.test.js 2>&1" 2>/dev/null || echo "(test run failed or file missing)")

# Check for genuine failures (not "failed: 0" in passing output)
MATH_OK=$(echo "$MATH_RUN" | grep -qi "Tests failed: [^0]\|AssertionError\|SyntaxError\|Cannot find\|Error:" && echo "FAIL" || echo "PASS")
STRINGS_OK=$(echo "$STRINGS_RUN" | grep -qi "Tests failed: [^0]\|AssertionError\|SyntaxError\|Cannot find\|Error:" && echo "FAIL" || echo "PASS")

# Check for cross-contamination: did A create anything in B's dir, or vice versa?
A_IN_B=$(docker exec "$CONTAINER" sh -c "ls $WORKSPACE/concurrent-B/ 2>/dev/null" | grep -c "math" || echo "0")
B_IN_A=$(docker exec "$CONTAINER" sh -c "ls $WORKSPACE/concurrent-A/ 2>/dev/null" | grep -c "string" || echo "0")

# List all files created
ALL_FILES_A=$(docker exec "$CONTAINER" sh -c "find $WORKSPACE/concurrent-A -type f 2>/dev/null" || echo "(dir not found)")
ALL_FILES_B=$(docker exec "$CONTAINER" sh -c "find $WORKSPACE/concurrent-B -type f 2>/dev/null" || echo "(dir not found)")

# Get agent outputs
OUTPUT_A=$(cat /tmp/t6-output-A.txt 2>/dev/null | tail -40)
OUTPUT_B=$(cat /tmp/t6-output-B.txt 2>/dev/null | tail -40)

# Content spot-checks: does A's math.js export the right functions?
MATH_CONTENT=$(docker exec "$CONTAINER" sh -c "cat $WORKSPACE/concurrent-A/math.js 2>/dev/null" || echo "(not found)")
STRINGS_CONTENT=$(docker exec "$CONTAINER" sh -c "cat $WORKSPACE/concurrent-B/strings.js 2>/dev/null" || echo "(not found)")

# Did output A mention anything from task B's topic? (cross-contamination signal)
OUTPUT_A_CROSS=$(echo "$OUTPUT_A" | grep -qi "slugify\|capitalize\|truncate\|strings" && echo "yes (possible leak)" || echo "no")
OUTPUT_B_CROSS=$(echo "$OUTPUT_B" | grep -qi "divide\|multiply\|add\|subtract\|math" && echo "yes (possible leak)" || echo "no")

# ── Write results ─────────────────────────────────────────────────────────────

cat > "$RESULT_FILE" << RESULT_EOF
# T6 — Concurrent Task Handling
**Date:** $(date '+%Y-%m-%d %H:%M')
**Total wall time:** ${TOTAL_ELAPSED}s

## What was tested
Two tasks fired simultaneously (2s stagger) at the same clawbox gateway endpoint:
- **Task A:** Write math.js + math.test.js in \`concurrent-A/\`
- **Task B:** Write strings.js + strings.test.js in \`concurrent-B/\`

Both tasks asked the agent to write files to separate directories and run tests.
The key questions: do both complete? are outputs correct? is there interference?

## Task Completion

| | Task A (math) | Task B (strings) |
|---|---|---|
| Timed out | $TASK_A_TIMEOUT | $TASK_B_TIMEOUT |
| JS file created | $MATH_JS | $STRINGS_JS |
| Test file created | $MATH_TEST | $STRINGS_TEST |
| Tests run OK | $MATH_OK | $STRINGS_OK |
| Cross-contamination signal in output | $OUTPUT_A_CROSS | $OUTPUT_B_CROSS |
| Files from other task in dir | A_in_B: $A_IN_B | B_in_A: $B_IN_A |

## Assessment
$([ "$MATH_JS" = "yes" ] && echo "✓ Task A: math.js created" || echo "✗ Task A: math.js NOT created")
$([ "$MATH_TEST" = "yes" ] && echo "✓ Task A: math.test.js created" || echo "✗ Task A: math.test.js NOT created")
$([ "$STRINGS_JS" = "yes" ] && echo "✓ Task B: strings.js created" || echo "✗ Task B: strings.js NOT created")
$([ "$STRINGS_TEST" = "yes" ] && echo "✓ Task B: strings.test.js created" || echo "✗ Task B: strings.test.js NOT created")
$([ "$MATH_OK" = "PASS" ] && echo "✓ Task A: math tests pass" || echo "✗ Task A: math tests FAIL or incomplete")
$([ "$STRINGS_OK" = "PASS" ] && echo "✓ Task B: strings tests pass" || echo "✗ Task B: strings tests FAIL or incomplete")
$([ "$OUTPUT_A_CROSS" = "no" ] && echo "✓ No cross-contamination in Task A output" || echo "⚠ Task A output mentions Task B content")
$([ "$OUTPUT_B_CROSS" = "no" ] && echo "✓ No cross-contamination in Task B output" || echo "⚠ Task B output mentions Task A content")

## Files created

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
RESULT_EOF

log "Results written to $RESULT_FILE"
log "Done."
