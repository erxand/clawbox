#!/usr/bin/env bash
# T3 — Multi-session continuity test
#
# What: Start a task, stop the container, restart, and ask the agent to continue.
# Why:  Tests whether TASK.md + workspace persistence enables meaningful resume.
# Good: Agent finds TASK.md on resume, continues correctly, all endpoints work.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T3-multi-session.md"
CONTAINER="clawbox-work"

mkdir -p "$RESULT_DIR"

# Unique project name per run — avoids TASK.md collisions with leftover workspace dirs
RUN_ID=$(date +%Y%m%d-%H%M%S)
PROJECT_NAME="bookstore-${RUN_ID}"

log() { echo "[T3 $(date +%H:%M:%S)] $*"; }

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

log "=== SESSION 1: Start bookstore API (project: $PROJECT_NAME) ==="

"$CLAWBOX" stop 2>/dev/null || true
"$CLAWBOX" start
wait_healthy

# Clean up stale test project dirs from previous runs to avoid TASK.md false picks.
# Preserves seed files (AGENTS.md, SOUL.md, USER.md, TOOLS.md, MEMORY.md, HEARTBEAT.md etc.)
# and the .git repo. Only removes project subdirectories from previous test runs.
WORKSPACE="/home/node/.openclaw/workspace"
log "Cleaning up stale project dirs from workspace..."
docker exec "$CONTAINER" sh -c "
  cd $WORKSPACE
  for d in \$(ls -d */ 2>/dev/null); do
    d=\${d%/}
    # Keep known seed/system dirs
    case \$d in
      .git|.openclaw|memory) continue ;;
    esac
    # Remove everything else (stale test project dirs)
    rm -rf \"\$d\" && echo \"  removed: \$d\"
  done
  # Also remove any stale TASK.md in workspace root
  rm -f TASK.md
" 2>/dev/null || true
log "Workspace cleaned."

SESSION1_MSG="Create a NEW project directory called '${PROJECT_NAME}' in /home/node/.openclaw/workspace/ and start building an Express API for a bookstore there. Create the project structure and the first endpoint: GET /books that returns a hardcoded list of 3 books. Save your progress plan to TASK.md inside ${PROJECT_NAME}/ then stop — I'll continue this task in a new session."

log "Sending session 1 message..."
SESSION1_START=$(date +%s)

SESSION1_OUTPUT=$(OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw agent --agent main -m "$SESSION1_MSG" 2>&1 || true)

SESSION1_END=$(date +%s)
SESSION1_TIME=$((SESSION1_END - SESSION1_START))
log "Session 1 completed in ${SESSION1_TIME}s"

# ISSUE-44: Check for rate limit after session 1
if is_rate_limited "$SESSION1_OUTPUT"; then
  skip_rate_limited "T3 — Multi-session continuity (session 1)" "$RESULT_FILE" "$(echo "$SESSION1_OUTPUT" | grep -i "rate limit" | head -3)"
  log "SKIPPED due to API rate limit in session 1."
  exit 0
fi

# Capture session 1 state — look for TASK.md in the named project dir specifically
# This is deterministic: we told the agent exactly where to put the project
S1_TASK_MD_PATH=$(docker exec "$CONTAINER" sh -c "find $WORKSPACE/$PROJECT_NAME -name 'TASK.md' 2>/dev/null | grep -v '/.git/' | head -1" 2>/dev/null || echo "")
# Fallback: search anywhere in workspace (agent may have used a slightly different dir name)
if [ -z "$S1_TASK_MD_PATH" ]; then
  S1_TASK_MD_PATH=$(docker exec "$CONTAINER" sh -c "find $WORKSPACE -name 'TASK.md' 2>/dev/null | grep -v '/.git/' | head -1" 2>/dev/null || echo "(not found)")
fi
[ -z "$S1_TASK_MD_PATH" ] && S1_TASK_MD_PATH="(not found)"
S1_TASK_MD=$(docker exec "$CONTAINER" sh -c "cat '$S1_TASK_MD_PATH' 2>/dev/null" 2>/dev/null || echo "(not found)")
S1_FILES=$(docker exec "$CONTAINER" sh -c "find $WORKSPACE -type f \( -name '*.js' -o -name '*.json' \) 2>/dev/null | grep -v node_modules | grep -v '/.git/' | grep -v AGENTS.md | grep -v SOUL.md | head -20" || echo "(none)")
S1_GIT_LOG=$(docker exec "$CONTAINER" sh -c "cd $WORKSPACE/$PROJECT_NAME && git log --oneline 2>/dev/null || cd $WORKSPACE && git log --oneline 2>/dev/null" || echo "(no git repo)")

log "Session 1 state captured. Stopping container..."

# ── Stop and restart (keep volume) ─────────────────────────────────

"$CLAWBOX" stop
sleep 3
log "Restarting container..."
"$CLAWBOX" start
wait_healthy

# ── Session 2 ──────────────────────────────────────────────────────

log "=== SESSION 2: Continue bookstore API ==="

SESSION2_MSG="Continue the bookstore API from where you left off. The project is in /home/node/.openclaw/workspace/${PROJECT_NAME}/. Read TASK.md there first. Then: add POST /books (add a book), GET /books/:id, and DELETE /books/:id. Start the server and verify all endpoints work. IMPORTANT: as you complete each step, check it off in TASK.md (change [ ] to [x]), then commit your changes to git."

log "Sending session 2 message..."
SESSION2_START=$(date +%s)

SESSION2_OUTPUT=$(OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw agent --agent main -m "$SESSION2_MSG" 2>&1 || true)

SESSION2_END=$(date +%s)
SESSION2_TIME=$((SESSION2_END - SESSION2_START))
log "Session 2 completed in ${SESSION2_TIME}s"

# ISSUE-44: Check for rate limit after session 2
if is_rate_limited "$SESSION2_OUTPUT"; then
  skip_rate_limited "T3 — Multi-session continuity (session 2)" "$RESULT_FILE" "$(echo "$SESSION2_OUTPUT" | grep -i "rate limit" | head -3)"
  log "SKIPPED due to API rate limit in session 2."
  exit 0
fi

# ── Verify endpoints ──────────────────────────────────────────────

log "Verifying endpoints..."

# Find the project main entry point and start the server explicitly for endpoint checks
# This handles the case where the agent's server exited after session 2
PROJECT_DIR=$(docker exec "$CONTAINER" sh -c "dirname '$S1_TASK_MD_PATH'" 2>/dev/null || echo "$WORKSPACE/$PROJECT_NAME")
log "Attempting to start server at $PROJECT_DIR for endpoint checks..."
# Use 'npm start' (reads package.json main/scripts.start) — handles server.js, index.js, src/index.js, etc.
# Falls back to trying common entrypoints if npm start fails.
docker exec -d "$CONTAINER" sh -c "cd '$PROJECT_DIR' && (npm start 2>/tmp/t3-server.log || node index.js 2>>/tmp/t3-server.log || node src/index.js 2>>/tmp/t3-server.log || node server.js 2>>/tmp/t3-server.log) &" 2>/dev/null || true
sleep 6

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
S2_GIT_LOG=$(docker exec "$CONTAINER" sh -c "cd $WORKSPACE/$PROJECT_NAME && git log --oneline 2>/dev/null || cd $WORKSPACE && git log --oneline 2>/dev/null" || echo "(no git repo)")

# ── Write results ──────────────────────────────────────────────────

FOUND_TASK_MD="no"
# Check anywhere in workspace (agent may put TASK.md inside project subdir)
if [ -n "$S1_TASK_MD" ] && [ "$S1_TASK_MD" != "(not found)" ]; then FOUND_TASK_MD="yes"; fi

CONTINUED_OK="no"
# Primary signal: GET /books should return JSON array
if [ "$GET_BOOKS" != "FAIL" ] && [ -n "$GET_BOOKS" ] && echo "$GET_BOOKS" | grep -q '\['; then CONTINUED_OK="yes"; fi
# Secondary signal: TASK.md mentions completed POST/GET/:id/DELETE endpoints (agent finished even if server couldn't restart)
TASK_SHOWS_COMPLETE="no"
if echo "$S2_TASK_MD" | grep -qi "POST.*books\|books.*POST\|\[x\].*POST\|POST.*\[x\]" 2>/dev/null; then TASK_SHOWS_COMPLETE="yes"; fi

# New checks: did session 2 update TASK.md checkboxes? Did it commit new code?
TASK_MD_UPDATED="no"
# Count [x] lines in phase 2 section — session 1 leaves phase 2 unchecked; session 2 should check them
PHASE2_CHECKED=$(echo "$S2_TASK_MD" | grep -c "\[x\].*\(GET.*/:id\|POST.*books\|DELETE.*books\|CRUD\|endpoint\)" 2>/dev/null || echo "0")
# Also check raw [x] count increased beyond phase 1
S1_X_COUNT=$(echo "$S1_TASK_MD" | grep -c "\[x\]" 2>/dev/null || echo "0")
S2_X_COUNT=$(echo "$S2_TASK_MD" | grep -c "\[x\]" 2>/dev/null || echo "0")
if [ "$S2_X_COUNT" -gt "$S1_X_COUNT" ] 2>/dev/null; then TASK_MD_UPDATED="yes"; fi

# Did session 2 make new git commits?
NEW_COMMITS_ADDED="no"
S1_COMMIT_COUNT=$(echo "$S1_GIT_LOG" | grep -c "^[0-9a-f]" 2>/dev/null || echo "0")
S2_COMMIT_COUNT=$(echo "$S2_GIT_LOG" | grep -c "^[0-9a-f]" 2>/dev/null || echo "0")
if [ "$S2_COMMIT_COUNT" -gt "$S1_COMMIT_COUNT" ] 2>/dev/null; then NEW_COMMITS_ADDED="yes"; fi

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
$([ "$CONTINUED_OK" = "yes" ] && echo "✓ Agent successfully continued in session 2 (endpoints verified)" || \
  ([ "$TASK_SHOWS_COMPLETE" = "yes" ] && echo "⚠ Agent continued (TASK.md shows work done) but endpoint verification failed — server restart issue" || \
   echo "✗ Agent failed to continue properly in session 2"))
$([ "$TASK_MD_UPDATED" = "yes" ] && echo "✓ TASK.md checkboxes updated in session 2 (S1: ${S1_X_COUNT}x → S2: ${S2_X_COUNT}x)" || echo "✗ TASK.md NOT updated by session 2 (S1: ${S1_X_COUNT}x checked, S2: ${S2_X_COUNT}x checked — no progress recorded)")
$([ "$NEW_COMMITS_ADDED" = "yes" ] && echo "✓ New git commits made in session 2 (S1: ${S1_COMMIT_COUNT} → S2: ${S2_COMMIT_COUNT})" || echo "✗ No new git commits from session 2 (S1: ${S1_COMMIT_COUNT} commits, S2: ${S2_COMMIT_COUNT} commits — same)")

### What was lost between sessions?
$([ "$FOUND_TASK_MD" = "yes" ] && echo "TASK.md was preserved across restart." || echo "No TASK.md found — continuity mechanism not used.")
RESULT_EOF

log "Results written to $RESULT_FILE"
log "Done."
