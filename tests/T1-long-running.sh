#!/usr/bin/env bash
# T1 — Long-running task test
#
# What: Give the agent a complex multi-step task (full-stack web app) and see
#        if it can sustain work over 10-20 minutes.
# Why:  Long tasks stress context windows, tool reliability, and self-organization.
# Good: Agent uses TASK.md, makes git commits, completes most/all steps, apps run.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T1-long-running.md"
CONTAINER="clawbox-work"
TIMEOUT_SECONDS=1200  # 20 minutes
POLL_INTERVAL=30

mkdir -p "$RESULT_DIR"

log() { echo "[T1 $(date +%H:%M:%S)] $*"; }

# ── Setup ───────────────────────────────────────────────────────────

log "Starting fresh container..."
"$CLAWBOX" stop 2>/dev/null || true
"$CLAWBOX" start
sleep 5

# Create a time sentinel for -newer comparisons — any TASK.md created after this is ours
docker exec "$CONTAINER" sh -c "touch /tmp/t1-start-sentinel"

# Each run gets a unique project dir so stale workspace state doesn't cause false cache hits
RUN_ID=$(date +%s)
PROJECT_NAME="taskman-${RUN_ID}"

# ── Send task ───────────────────────────────────────────────────────

TASK_MSG="Create a NEW project directory called '${PROJECT_NAME}' inside /home/node/.openclaw/workspace/ and build a full task management web app there. Requirements: (1) Express backend with SQLite, (2) API endpoints: GET/POST/PUT/DELETE /tasks, GET /tasks/:id, POST /tasks/:id/mark-done, (3) Simple session-based user authentication, (4) Vanilla JS frontend with login, task list, add/mark-done/delete tasks, (5) Test suite covering all API endpoints. Start both servers and run the tests. Use TASK.md inside the project dir to track progress. Initialize git inside the project dir and commit after each major step (scaffold, backend, tests passing, frontend done)."

log "Sending task to agent..."
START_TIME=$(date +%s)

"$CLAWBOX" task "$TASK_MSG"

# ── Poll for progress ──────────────────────────────────────────────

TASK_MD_FOUND="no"
LAST_STEP=""
GIT_COMMITS=0
POLLS=0

while [ $(($(date +%s) - START_TIME)) -lt $TIMEOUT_SECONDS ]; do
  sleep $POLL_INTERVAL
  POLLS=$((POLLS + 1))

  # Is container still running?
  RUNNING=$(docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null || echo "false")
  if [ "$RUNNING" != "true" ]; then
    log "Container stopped!"
    break
  fi

  # Check TASK.md (may be in project subdir, search recursively — ISSUE-34)
  # Use -newer flag relative to test start sentinel to avoid stale files from prior runs
  TASK_CONTENT=$(docker exec "$CONTAINER" sh -c "find /home/node/.openclaw/workspace -name TASK.md -not -path '*/node_modules/*' -newer /tmp/t1-start-sentinel 2>/dev/null | head -1 | xargs cat 2>/dev/null" || echo "")
  if [ -n "$TASK_CONTENT" ]; then
    TASK_MD_FOUND="yes"
    CURRENT_STEP=$(echo "$TASK_CONTENT" | grep -A1 "Current Step" | tail -1 || echo "unknown")
    if [ "$CURRENT_STEP" != "$LAST_STEP" ]; then
      log "Progress: $CURRENT_STEP"
      LAST_STEP="$CURRENT_STEP"
    fi
    # Early exit if task is complete — no need to wait the full timeout
    # Use anchored patterns to avoid matching content like "/tasks/:id/complete" or "mark complete"
    if echo "$TASK_CONTENT" | grep -qiE '^(\*\*)?Status:.*COMPLETE|^Status:.*COMPLETE|All objectives achieved|DONE — all steps complete'; then
      log "Task marked COMPLETE — exiting poll loop early."
      break
    fi
  fi

  # Check git commits (find project git repo created this run)
  GIT_COMMITS=$(docker exec "$CONTAINER" sh -c "find /home/node/.openclaw/workspace -name '.git' -newer /tmp/t1-start-sentinel -maxdepth 3 2>/dev/null | head -1 | xargs dirname 2>/dev/null | xargs -I{} sh -c 'cd {} && git log --oneline 2>/dev/null | wc -l'" 2>/dev/null || echo "0")
  GIT_COMMITS=$(echo "$GIT_COMMITS" | tr -d ' ')

  log "Poll #$POLLS — running=$RUNNING task_md=$TASK_MD_FOUND commits=$GIT_COMMITS"
done

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

# ── Verify results ─────────────────────────────────────────────────

log "Verifying endpoints..."
# Check from INSIDE the container (ports not mapped to host by default in docker-compose.yml)
# The agent may use any port and any path — scan common ports AND common API paths.
# A 404 at root is EXPECTED for an API server; we check multiple paths and consider any
# non-000 (non-timeout) response as "server is responding".

# Helper: returns the best HTTP status for a given port across multiple paths
check_port_smart() {
  local port="$1"
  local paths="/ /tasks /api/tasks /api /health /ping /login /books /api/books"
  local best_code="000"
  local best_path="/"
  for path in $paths; do
    local code
    code=$(docker exec "$CONTAINER" sh -c "curl -s -o /dev/null -w '%{http_code}' http://localhost:${port}${path} 2>/dev/null" 2>/dev/null || echo "000")
    # Normalize: curl sometimes returns 000000 (6 digits) for connection refused — treat as 000
    code=$(echo "$code" | sed 's/^0*\([0-9]\)/\1/' | grep -oE '^[0-9]+' | head -1 || echo "0")
    [ -z "$code" ] && code="0"
    # 200 or 401 or 302 all mean "server is running" (401 = auth required, 302 = redirect)
    if [ "$code" != "0" ] && [ "$code" != "404" ]; then
      best_code="$code"
      best_path="$path"
      break
    elif [ "$code" = "404" ]; then
      # Better than 000 — server is responding, just not at this path
      best_code="$code"
      best_path="$path"
    fi
  done
  echo "${best_code}:${best_path}"
}

PORT_3000_RESULT=$(check_port_smart 3000)
PORT_3001_RESULT=$(check_port_smart 3001)
PORT_8080_RESULT=$(check_port_smart 8080)
CURL_3000=$(echo "$PORT_3000_RESULT" | cut -d: -f1)
CURL_3001=$(echo "$PORT_3001_RESULT" | cut -d: -f1)
CURL_8080=$(echo "$PORT_8080_RESULT" | cut -d: -f1)
PATH_3000=$(echo "$PORT_3000_RESULT" | cut -d: -f2)
PATH_3001=$(echo "$PORT_3001_RESULT" | cut -d: -f2)
PATH_8080=$(echo "$PORT_8080_RESULT" | cut -d: -f2)

# Check if any port has a running HTTP server (any non-0 code = server is up)
SERVER_ALIVE="no"
for code in $CURL_3000 $CURL_3001 $CURL_8080; do
  [ "$code" != "0" ] && SERVER_ALIVE="yes" && break
done

# Count running Node.js processes serving HTTP (more reliable than port check)
NODE_SERVERS=$(docker exec "$CONTAINER" sh -c "ps aux 2>/dev/null | grep -c '[n]ode'" 2>/dev/null || echo "0")
NODE_SERVERS=$(echo "$NODE_SERVERS" | tr -d ' ')

# Run tests inside the container (find the project dir and run npm test)
log "Running tests inside container..."
PROJECT_DIR=$(docker exec "$CONTAINER" sh -c "find /home/node/.openclaw/workspace -name 'package.json' -not -path '*/node_modules/*' -newer /tmp/t1-start-sentinel 2>/dev/null | head -1 | xargs dirname 2>/dev/null" 2>/dev/null || echo "")
TEST_RESULTS="(not run)"
TESTS_PASSING="unknown"
if [ -n "$PROJECT_DIR" ]; then
  TEST_OUTPUT=$(docker exec "$CONTAINER" sh -c "cd '$PROJECT_DIR' && npm test 2>&1 | tail -20" 2>/dev/null || echo "(test run failed)")
  TEST_RESULTS="$TEST_OUTPUT"
  # Check if tests passed (look for common pass indicators)
  if echo "$TEST_OUTPUT" | grep -qiE '(passing|tests passed|all.*pass|✓|✗.*0)'; then
    TESTS_PASSING="yes"
  elif echo "$TEST_OUTPUT" | grep -qiE '(failing|failed|error)'; then
    TESTS_PASSING="no"
  fi
fi

# Final TASK.md content (search recursively in project workspace — ISSUE-34)
FINAL_TASK_MD=$(docker exec "$CONTAINER" sh -c "find /home/node/.openclaw/workspace -name TASK.md -not -path '*/node_modules/*' -newer /tmp/t1-start-sentinel 2>/dev/null | head -1 | xargs cat 2>/dev/null" || echo "(not found)")
[ -z "$FINAL_TASK_MD" ] && FINAL_TASK_MD="(not found)"

# Git log (find project git repo created by this test run)
GIT_LOG=$(docker exec "$CONTAINER" sh -c "find /home/node/.openclaw/workspace -name '.git' -newer /tmp/t1-start-sentinel -maxdepth 3 2>/dev/null | head -1 | xargs dirname 2>/dev/null | xargs -I{} sh -c 'cd {} && git log --oneline 2>/dev/null'" 2>/dev/null || echo "(no git repo)")

# ── Write results ──────────────────────────────────────────────────

cat > "$RESULT_FILE" << RESULT_EOF
# T1 — Long-running task test
**Date:** $(date '+%Y-%m-%d %H:%M')
**Duration:** ${ELAPSED}s (~$((ELAPSED / 60)) min)

## What was tested
Agent was asked to build a full-stack task management web app with Express, SQLite, auth, frontend, and tests.

## Results

| Metric | Value |
|--------|-------|
| Total time | ${ELAPSED}s |
| Used TASK.md | $TASK_MD_FOUND |
| Git commits | $GIT_COMMITS |
| Port 3000 (best path: $PATH_3000) | HTTP $CURL_3000 |
| Port 3001 (best path: $PATH_3001) | HTTP $CURL_3001 |
| Port 8080 (best path: $PATH_8080) | HTTP $CURL_8080 |
| Any server alive | $SERVER_ALIVE |
| Node processes | $NODE_SERVERS |
| Tests passing | $TESTS_PASSING |
| Poll cycles | $POLLS |

## Test Output (last 20 lines)
\`\`\`
$TEST_RESULTS
\`\`\`

## Final TASK.md
\`\`\`
$FINAL_TASK_MD
\`\`\`

## Git log
\`\`\`
$GIT_LOG
\`\`\`

## Assessment
$([ "$TASK_MD_FOUND" = "yes" ] && echo "✓ Agent used TASK.md for progress tracking" || echo "✗ Agent did NOT use TASK.md")
$([ "$GIT_COMMITS" -gt 0 ] 2>/dev/null && echo "✓ Agent made $GIT_COMMITS git commits" || echo "✗ Agent made no git commits")
$([ "$TESTS_PASSING" = "yes" ] && echo "✓ Tests passing" || echo "⚠ Tests status: $TESTS_PASSING")
$([ "$SERVER_ALIVE" = "yes" ] && echo "✓ HTTP server responding on at least one port" || echo "✗ No HTTP server detected on ports 3000/3001/8080")
$([ "$CURL_3000" != "0" ] && echo "✓ Port 3000: HTTP $CURL_3000 (path: $PATH_3000)" || echo "⚠ Port 3000: no response (server may have stopped after test run)")
$([ "$CURL_3001" != "0" ] && echo "✓ Port 3001: HTTP $CURL_3001 (path: $PATH_3001)" || echo "⚠ Port 3001: no response")
$([ "$CURL_8080" != "0" ] && echo "✓ Port 8080: HTTP $CURL_8080 (path: $PATH_8080)" || echo "⚠ Port 8080: no response")
$([ "$NODE_SERVERS" -gt 0 ] 2>/dev/null && echo "✓ Node.js process(es) running ($NODE_SERVERS found)" || echo "⚠ No Node.js processes detected")

### Notes on endpoint detection
- A 404 at root is EXPECTED for API servers (real endpoints are /tasks, /api/etc.)
- This test now probes multiple paths and marks a server "alive" if any path responds
- Server may stop after completing the test suite (expected behavior for test runs)
RESULT_EOF

log "Results written to $RESULT_FILE"
log "Done."
