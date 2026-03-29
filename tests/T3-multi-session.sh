#!/usr/bin/env bash
# T3 — Multi-session continuity test
#
# What: Start a task, stop the container, restart, and ask the agent to continue.
# Why:  Tests whether TASK.md + workspace persistence enables meaningful resume.
# Good: Agent finds TASK.md on resume, continues correctly, all endpoints work.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T3-multi-session.md"
CONTAINER="clawbox-work"

mkdir -p "$RESULT_DIR"

log() { echo "[T3 $(date +%H:%M:%S)] $*"; }

# Create a sentinel file so we can find only TASK.md files created during this run
SENTINEL="/tmp/t3-sentinel-$$"
touch "$SENTINEL"

wait_healthy() {
  for i in $(seq 1 60); do
    STATUS=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "missing")
    if [ "$STATUS" = "healthy" ]; then return 0; fi
    sleep 2
  done
  log "WARNING: container did not become healthy within 120s"
  return 1
}

wait_for_agent() {
  # Wait for the agent command to finish (poll for idle gateway)
  local max_wait=${1:-300}
  local elapsed=0
  while [ $elapsed -lt $max_wait ]; do
    sleep 10
    elapsed=$((elapsed + 10))
    # Check if TASK.md exists anywhere in workspace (agent may create it in a subdir)
    # Workspace is /home/node/.openclaw/workspace/ (not /home/node/workspace/)
    FOUND=$(docker exec "$CONTAINER" sh -c "find /home/node/.openclaw/workspace -name 'TASK.md' 2>/dev/null | head -1")
    [ -n "$FOUND" ] && break
  done
  # Give extra time for the agent to finish after TASK.md appears
  sleep 30
}

# ── Session 1 ──────────────────────────────────────────────────────

log "=== SESSION 1: Start bookstore API ==="

"$CLAWBOX" stop 2>/dev/null || true
"$CLAWBOX" start
wait_healthy

# Record the start time inside the container for find -newer filtering
SESSION1_START_MARKER=$(docker exec "$CONTAINER" sh -c "touch /tmp/t3-session1-start && echo /tmp/t3-session1-start" 2>/dev/null || echo "")

SESSION1_MSG="Start building an Express API for a bookstore. Create the project structure and the first endpoint: GET /books that returns a hardcoded list of 3 books. Save your progress plan to TASK.md then stop — I'll continue this task in a new session."

log "Sending session 1 message..."
SESSION1_START=$(date +%s)

OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw agent --agent main -m "$SESSION1_MSG" 2>&1 || true

SESSION1_END=$(date +%s)
SESSION1_TIME=$((SESSION1_END - SESSION1_START))
log "Session 1 completed in ${SESSION1_TIME}s"

# Capture session 1 state (workspace is /home/node/.openclaw/workspace/)
WORKSPACE="/home/node/.openclaw/workspace"
# Use -newer to find only TASK.md files created during this session (not leftovers from T15 etc.)
S1_TASK_MD_PATH=$(docker exec "$CONTAINER" sh -c "find $WORKSPACE -name 'TASK.md' -newer /tmp/t3-session1-start 2>/dev/null | grep -v '/.git/' | head -1" 2>/dev/null || echo "(not found)")
# Fallback: if no recent TASK.md, get newest by modification time
if [ -z "$S1_TASK_MD_PATH" ] || [ "$S1_TASK_MD_PATH" = "(not found)" ]; then
  S1_TASK_MD_PATH=$(docker exec "$CONTAINER" sh -c "find $WORKSPACE -name 'TASK.md' 2>/dev/null | grep -v '/.git/' | xargs ls -t 2>/dev/null | head -1" 2>/dev/null || echo "(not found)")
fi
S1_TASK_MD=$(docker exec "$CONTAINER" sh -c "cat '$S1_TASK_MD_PATH' 2>/dev/null" 2>/dev/null || echo "(not found)")
S1_FILES=$(docker exec "$CONTAINER" sh -c "find $WORKSPACE -type f \( -name '*.js' -o -name '*.json' \) 2>/dev/null | grep -v node_modules | grep -v '/.git/' | grep -v AGENTS.md | grep -v SOUL.md | head -20" || echo "(none)")
S1_GIT_LOG=$(docker exec "$CONTAINER" sh -c "cd $WORKSPACE && git log --oneline 2>/dev/null" || echo "(no git repo)")

log "Session 1 state captured. Stopping container..."

# ── Stop and restart (keep volume) ─────────────────────────────────

"$CLAWBOX" stop
sleep 3
log "Restarting container..."
"$CLAWBOX" start
wait_healthy

# ── Session 2 ──────────────────────────────────────────────────────

log "=== SESSION 2: Continue bookstore API ==="

SESSION2_MSG="Continue the bookstore API from where you left off. Check TASK.md for context. Add POST /books (add a book), GET /books/:id, and DELETE /books/:id. Then start the server and verify all endpoints work."

log "Sending session 2 message..."
SESSION2_START=$(date +%s)

OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw agent --agent main -m "$SESSION2_MSG" 2>&1 || true

SESSION2_END=$(date +%s)
SESSION2_TIME=$((SESSION2_END - SESSION2_START))
log "Session 2 completed in ${SESSION2_TIME}s"

# ── Verify endpoints ──────────────────────────────────────────────

log "Verifying endpoints..."

# Find the project main entry point and start the server explicitly for endpoint checks
# This handles the case where the agent's server exited after session 2
PROJECT_DIR=$(docker exec "$CONTAINER" sh -c "dirname '$S1_TASK_MD_PATH'" 2>/dev/null || echo "$WORKSPACE/bookstore-api")
log "Attempting to start server at $PROJECT_DIR for endpoint checks..."
docker exec -d "$CONTAINER" sh -c "cd '$PROJECT_DIR' && node index.js 2>/tmp/t3-server.log || node src/index.js 2>/tmp/t3-server.log || true" 2>/dev/null || true
sleep 5

# Check from inside container (ports not mapped to host by default)
GET_BOOKS=$(docker exec "$CONTAINER" sh -c "curl -s http://localhost:3000/books 2>/dev/null" || echo "FAIL")
GET_BOOK_1=$(docker exec "$CONTAINER" sh -c "curl -s http://localhost:3000/books/1 2>/dev/null" || echo "FAIL")
POST_BOOK=$(docker exec "$CONTAINER" sh -c 'curl -s -X POST http://localhost:3000/books -H "Content-Type: application/json" -d "{\"title\":\"Test Book\",\"author\":\"Test\"}" 2>/dev/null' || echo "FAIL")
DELETE_BOOK=$(docker exec "$CONTAINER" sh -c "curl -s -X DELETE http://localhost:3000/books/1 2>/dev/null" || echo "FAIL")

# Also try port 3001 in case agent used that
GET_BOOKS_ALT=$(docker exec "$CONTAINER" sh -c "curl -s http://localhost:3001/books 2>/dev/null" || echo "FAIL")

# Final state — get the same TASK.md path that was found in session 1 (it should be updated by session 2)
S2_TASK_MD_PATH="$S1_TASK_MD_PATH"
S2_TASK_MD=$(docker exec "$CONTAINER" sh -c "cat '$S2_TASK_MD_PATH' 2>/dev/null" 2>/dev/null || echo "(not found)")
S2_FILES=$(docker exec "$CONTAINER" sh -c "find $WORKSPACE -type f \( -name '*.js' -o -name '*.json' \) 2>/dev/null | grep -v node_modules | grep -v '/.git/' | grep -v AGENTS.md | head -20" || echo "(none)")
S2_GIT_LOG=$(docker exec "$CONTAINER" sh -c "cd $WORKSPACE && git log --oneline 2>/dev/null" || echo "(no git repo)")

# ── Write results ──────────────────────────────────────────────────

FOUND_TASK_MD="no"
# Check anywhere in workspace (agent may put TASK.md inside project subdir)
if [ -n "$S1_TASK_MD" ] && [ "$S1_TASK_MD" != "(not found)" ]; then FOUND_TASK_MD="yes"; fi

CONTINUED_OK="no"
# GET /books should return JSON array (even if it says "title" not "book")
if [ "$GET_BOOKS" != "FAIL" ] && [ -n "$GET_BOOKS" ] && echo "$GET_BOOKS" | grep -q '\['; then CONTINUED_OK="yes"; fi

cat > "$RESULT_FILE" << RESULT_EOF
# T3 — Multi-session continuity test
**Date:** $(date '+%Y-%m-%d %H:%M')

## What was tested
1. Session 1: Agent starts a bookstore API, creates GET /books, saves TASK.md
2. Container stopped and restarted (volume preserved)
3. Session 2: Agent asked to continue — add POST, GET/:id, DELETE/:id, verify

## Timing
- Session 1: ${SESSION1_TIME}s
- Session 2: ${SESSION2_TIME}s

## Session 1 State

### TASK.md after session 1
**Path:** $S1_TASK_MD_PATH
\`\`\`
$S1_TASK_MD
\`\`\`

### Files created
\`\`\`
$S1_FILES
\`\`\`

### Git log
\`\`\`
$S1_GIT_LOG
\`\`\`

## Session 2 State

### TASK.md after session 2
**Path:** $S2_TASK_MD_PATH
\`\`\`
$S2_TASK_MD
\`\`\`

### Files
\`\`\`
$S2_FILES
\`\`\`

### Git log
\`\`\`
$S2_GIT_LOG
\`\`\`

## Endpoint verification

| Endpoint | Response |
|----------|----------|
| GET /books (port 3000) | \`$(echo "$GET_BOOKS" | head -c 200)\` |
| GET /books/1 | \`$(echo "$GET_BOOK_1" | head -c 200)\` |
| POST /books | \`$(echo "$POST_BOOK" | head -c 200)\` |
| DELETE /books/1 | \`$(echo "$DELETE_BOOK" | head -c 200)\` |
| GET /books (port 3001) | \`$(echo "$GET_BOOKS_ALT" | head -c 200)\` |

## Assessment
$([ "$FOUND_TASK_MD" = "yes" ] && echo "✓ Agent created TASK.md in session 1" || echo "✗ Agent did NOT create TASK.md in session 1")
$([ "$CONTINUED_OK" = "yes" ] && echo "✓ Agent successfully continued in session 2" || echo "✗ Agent failed to continue properly in session 2")

### What was lost between sessions?
$([ "$FOUND_TASK_MD" = "yes" ] && echo "TASK.md was preserved across restart." || echo "No TASK.md found — continuity mechanism not used.")
RESULT_EOF

log "Results written to $RESULT_FILE"
log "Done."
