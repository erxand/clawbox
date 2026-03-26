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

# ── Send task ───────────────────────────────────────────────────────

TASK_MSG="Build a full task management web app with: (1) Express backend with SQLite, (2) Multiple API endpoints: GET/POST/PUT/DELETE /tasks, GET /tasks/:id, POST /tasks/:id/complete, (3) User authentication (simple session-based), (4) A vanilla JS frontend with login, task list, add task, mark complete, delete. (5) Write a test suite that tests all API endpoints. Start both servers and run the tests. Use TASK.md to track your progress."

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

  # Check TASK.md
  TASK_CONTENT=$(docker exec "$CONTAINER" cat /home/node/workspace/TASK.md 2>/dev/null || echo "")
  if [ -n "$TASK_CONTENT" ]; then
    TASK_MD_FOUND="yes"
    CURRENT_STEP=$(echo "$TASK_CONTENT" | grep -A1 "Current Step" | tail -1 || echo "unknown")
    if [ "$CURRENT_STEP" != "$LAST_STEP" ]; then
      log "Progress: $CURRENT_STEP"
      LAST_STEP="$CURRENT_STEP"
    fi
  fi

  # Check git commits
  GIT_COMMITS=$(docker exec "$CONTAINER" sh -c "cd /home/node/workspace && git log --oneline 2>/dev/null | wc -l" || echo "0")
  GIT_COMMITS=$(echo "$GIT_COMMITS" | tr -d ' ')

  log "Poll #$POLLS — running=$RUNNING task_md=$TASK_MD_FOUND commits=$GIT_COMMITS"
done

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

# ── Verify results ─────────────────────────────────────────────────

log "Verifying endpoints..."
CURL_3000=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3000 2>/dev/null || echo "000")
CURL_3001=$(curl -s -o /dev/null -w "%{http_code}" http://localhost:3001/tasks 2>/dev/null || echo "000")

# Final TASK.md content
FINAL_TASK_MD=$(docker exec "$CONTAINER" cat /home/node/workspace/TASK.md 2>/dev/null || echo "(not found)")

# Git log
GIT_LOG=$(docker exec "$CONTAINER" sh -c "cd /home/node/workspace && git log --oneline 2>/dev/null" || echo "(no git repo)")

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
| Port 3000 (frontend) | HTTP $CURL_3000 |
| Port 3001 (API) | HTTP $CURL_3001 |
| Poll cycles | $POLLS |

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
$([ "$CURL_3000" = "200" ] && echo "✓ Frontend reachable" || echo "✗ Frontend not reachable (HTTP $CURL_3000)")
$([ "$CURL_3001" = "200" ] && echo "✓ API reachable" || echo "✗ API not reachable (HTTP $CURL_3001)")
RESULT_EOF

log "Results written to $RESULT_FILE"
log "Done."
