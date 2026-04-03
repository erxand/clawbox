#!/usr/bin/env bash
# T20 — Workspace persistence across container restarts
#
# What: Validate that the clawbox workspace (Docker volume) persists across
#       container stop/start cycles. This is the fundamental guarantee that
#       makes multi-session workflows possible — if files disappear on restart,
#       all continuity features (TASK.md, git history, multi-session T3) break.
#
# Why:  T3 (multi-session continuity) implicitly relies on workspace persistence,
#       but it interleaves container restarts with agent sessions, making it hard
#       to isolate volume behavior from agent behavior. This test directly:
#       1. Writes known files to the workspace via docker exec
#       2. Stops and restarts the container
#       3. Verifies the files are still present and intact
#       4. Tests the inverse — container rootfs is NOT persisted (ephemeral)
#       5. Tests that the agent can read files written in a prior session
#
# Tests: 12 total

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T20-workspace-persistence.md"
CONTAINER="clawbox-work"
WORKSPACE="/home/node/.openclaw/workspace"

mkdir -p "$RESULT_DIR"

PASS=0
FAIL=0
WARN=0

log()  { echo "[T20 $(date +%H:%M:%S)] $*"; }
pass() { echo "✓ $*"; PASS=$((PASS+1)); }
fail() { echo "✗ $*"; FAIL=$((FAIL+1)); }
warn() { echo "⚠ $*"; WARN=$((WARN+1)); }

# ── Source rate-limit helpers ────────────────────────────────────────
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || true

# ── Teardown helper ─────────────────────────────────────────────────

cleanup() {
  log "Cleanup: removing T20 test artifacts..."
  docker exec "$CONTAINER" rm -rf "${WORKSPACE}/t20-persistence-test" 2>/dev/null || true
  # Re-start the container if we stopped it
  if ! docker ps --filter "name=$CONTAINER" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -q "$CONTAINER"; then
    log "Restarting container after test..."
    "$CLAWBOX" start 2>/dev/null || true
  fi
}
trap cleanup EXIT

# ── Setup: ensure container is running ──────────────────────────────

log "Ensuring container is running..."
if ! docker ps --filter "name=$CONTAINER" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -q "$CONTAINER"; then
  log "Container not running, starting..."
  "$CLAWBOX" start
  sleep 10
fi

TEST_DIR="${WORKSPACE}/t20-persistence-test"
CANARY_FILE="${TEST_DIR}/canary.txt"
CANARY_CONTENT="T20 persistence test — written at $(date +%Y%m%d-%H%M%S)"
NESTED_FILE="${TEST_DIR}/nested/deep/file.txt"
NESTED_CONTENT="Nested file persistence check"
GIT_COMMIT_MSG="T20 persistence test commit"

# ── Test 1: Write files to workspace ────────────────────────────────

log "Test 1: Writing test files to workspace..."
docker exec "$CONTAINER" sh -c "
  mkdir -p '${TEST_DIR}/nested/deep'
  echo '${CANARY_CONTENT}' > '${CANARY_FILE}'
  echo '${NESTED_CONTENT}' > '${NESTED_FILE}'
  cd '${TEST_DIR}'
  git init -q
  git config user.email 't20@clawbox.test'
  git config user.name 'T20 Test'
  git add -A
  git commit -q -m '${GIT_COMMIT_MSG}'
" 2>&1

if [ $? -eq 0 ]; then
  pass "Test files written to workspace and git-committed"
else
  fail "Failed to write test files to workspace"
fi

# Verify files exist before restart
CANARY_BEFORE=$(docker exec "$CONTAINER" cat "${CANARY_FILE}" 2>/dev/null || echo "MISSING")
if [ "$CANARY_BEFORE" = "${CANARY_CONTENT}" ]; then
  pass "Canary file readable before restart (content matches)"
else
  fail "Canary file not readable before restart (got: $CANARY_BEFORE)"
fi

# ── Test 2: Count git commits before restart ─────────────────────────

log "Test 2: Git commit count before restart..."
COMMITS_BEFORE=$(docker exec "$CONTAINER" sh -c "cd '${TEST_DIR}' && git log --oneline | wc -l | tr -d ' '" 2>/dev/null || echo "0")
if [ "$COMMITS_BEFORE" -ge 1 ] 2>/dev/null; then
  pass "Git repo has $COMMITS_BEFORE commit(s) before restart"
else
  warn "Could not confirm git commit count before restart (got: $COMMITS_BEFORE)"
fi

# ── Test 3: Stop container ──────────────────────────────────────────

log "Test 3: Stopping container..."
"$CLAWBOX" stop 2>/dev/null
sleep 3

if ! docker ps --filter "name=$CONTAINER" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -q "$CONTAINER"; then
  pass "Container stopped cleanly"
else
  warn "Container still appears to be running after stop"
fi

# ── Test 4: Restart container ───────────────────────────────────────

log "Test 4: Starting container again..."
START_TIME=$(date +%s)
"$CLAWBOX" start
END_TIME=$(date +%s)
START_ELAPSED=$((END_TIME - START_TIME))

if docker ps --filter "name=$CONTAINER" --filter "status=running" --format "{{.Names}}" 2>/dev/null | grep -q "$CONTAINER"; then
  pass "Container restarted in ${START_ELAPSED}s"
else
  fail "Container failed to restart"
fi

# Wait for gateway to be ready
log "Waiting 15s for gateway to stabilize..."
sleep 15

# ── Test 5: Canary file persists after restart ───────────────────────

log "Test 5: Canary file persists after restart..."
CANARY_AFTER=$(docker exec "$CONTAINER" cat "${CANARY_FILE}" 2>/dev/null || echo "MISSING")
if [ "$CANARY_AFTER" = "${CANARY_CONTENT}" ]; then
  pass "Canary file persists after restart (exact content match)"
else
  fail "Canary file lost after restart (expected: '${CANARY_CONTENT}', got: '${CANARY_AFTER}')"
fi

# ── Test 6: Nested files persist ────────────────────────────────────

log "Test 6: Nested directory structure persists..."
NESTED_AFTER=$(docker exec "$CONTAINER" cat "${NESTED_FILE}" 2>/dev/null || echo "MISSING")
if [ "$NESTED_AFTER" = "${NESTED_CONTENT}" ]; then
  pass "Nested file (${NESTED_FILE}) persists after restart"
else
  fail "Nested file lost after restart (got: $NESTED_AFTER)"
fi

# ── Test 7: Git history persists ────────────────────────────────────

log "Test 7: Git history persists after restart..."
COMMITS_AFTER=$(docker exec "$CONTAINER" sh -c "cd '${TEST_DIR}' && git log --oneline | wc -l | tr -d ' '" 2>/dev/null || echo "0")
if [ "$COMMITS_AFTER" -ge 1 ] 2>/dev/null && [ "$COMMITS_AFTER" = "$COMMITS_BEFORE" ] 2>/dev/null; then
  pass "Git history intact after restart ($COMMITS_AFTER commit(s))"
elif [ "$COMMITS_AFTER" -ge 1 ] 2>/dev/null; then
  warn "Git history present but commit count changed (before: $COMMITS_BEFORE, after: $COMMITS_AFTER)"
else
  fail "Git history lost after restart (got: $COMMITS_AFTER)"
fi

# ── Test 8: AGENTS.md (seed file) persists ──────────────────────────

log "Test 8: AGENTS.md (seed file) persists..."
AGENTS_SIZE=$(docker exec "$CONTAINER" sh -c "wc -c '${WORKSPACE}/AGENTS.md' 2>/dev/null | awk '{print \$1}'" | tr -d ' ' || echo "0")
if [ "${AGENTS_SIZE}" -gt 100 ] 2>/dev/null; then
  pass "AGENTS.md present and non-trivial after restart (${AGENTS_SIZE} bytes)"
else
  warn "AGENTS.md missing or empty after restart (got: ${AGENTS_SIZE} bytes)"
fi

# ── Test 9: Container rootfs is ephemeral (write to rootfs fails) ────

log "Test 9: Container rootfs is read-only (ephemeral, not persisted)..."
ROOTFS_WRITE=$(docker exec "$CONTAINER" sh -c "touch /t20-rootfs-probe 2>&1; echo exit:$?" 2>/dev/null || echo "failed")
if echo "$ROOTFS_WRITE" | grep -q "Read-only\|read-only\|cannot\|permission"; then
  pass "Container rootfs is read-only (writes rejected at OS level)"
elif echo "$ROOTFS_WRITE" | grep -q "exit:1\|exit:2"; then
  pass "Container rootfs is read-only (write exited with error)"
else
  warn "Container rootfs may not be read-only — rootfs persistence not guaranteed (output: $ROOTFS_WRITE)"
fi

# ── Test 10: Agent can read persisted files via clawbox run ──────────

log "Test 10: Agent can read workspace files via clawbox run..."
source "${SCRIPT_DIR}/lib/common.sh" 2>/dev/null || true

AGENT_READ_OUTPUT=$("$CLAWBOX" run --quiet --session "t20-read-test" \
  "Read the file ${CANARY_FILE} and tell me its EXACT first line. Just the line, nothing else." \
  2>/dev/null || echo "ERROR")

if [ -z "$AGENT_READ_OUTPUT" ] || [ "$AGENT_READ_OUTPUT" = "ERROR" ]; then
  fail "Agent failed to respond for read test"
elif is_rate_limited "$AGENT_READ_OUTPUT"; then
  warn "Rate limited during agent read test — skipping agent read verification"
elif echo "$AGENT_READ_OUTPUT" | grep -qi "t20 persistence\|persistence test\|written at"; then
  pass "Agent can read persisted workspace file (content referenced in response)"
else
  warn "Agent response may not reference file content (response: $(echo "$AGENT_READ_OUTPUT" | head -3))"
fi

# ── Test 11: Write a second file via agent, persist across micro-restart ──

log "Test 11: Agent writes a file, verifying workspace write works..."
AGENT_WRITE_OUTPUT=$("$CLAWBOX" run --quiet --session "t20-write-test" \
  "Write the text 'AGENT_WROTE_THIS_SUCCESSFULLY' to the file ${TEST_DIR}/agent-wrote.txt. Just do it directly, confirm when done." \
  2>/dev/null || echo "ERROR")

sleep 3  # Give the agent a moment to write

AGENT_FILE_CONTENT=$(docker exec "$CONTAINER" cat "${TEST_DIR}/agent-wrote.txt" 2>/dev/null || echo "MISSING")
if echo "$AGENT_FILE_CONTENT" | grep -q "AGENT_WROTE_THIS_SUCCESSFULLY"; then
  pass "Agent wrote file to workspace successfully (content verified)"
elif is_rate_limited "$AGENT_WRITE_OUTPUT" 2>/dev/null; then
  warn "Rate limited during agent write test — skipping verification"
elif [ "$AGENT_WRITE_OUTPUT" = "ERROR" ]; then
  fail "Agent failed to respond for write test"
else
  warn "Agent file not found or content mismatch (file content: $AGENT_FILE_CONTENT)"
fi

# ── Test 12: Workspace file count reasonable (not reset) ─────────────

log "Test 12: Workspace file count sanity check after restart..."
FILE_COUNT=$(docker exec "$CONTAINER" sh -c "find '${WORKSPACE}' -maxdepth 1 -mindepth 1 | wc -l | tr -d ' '" 2>/dev/null || echo "0")
if [ "$FILE_COUNT" -ge 3 ] 2>/dev/null; then
  pass "Workspace has $FILE_COUNT top-level items after restart (not wiped)"
else
  fail "Workspace appears empty after restart — volume may not be mounted correctly ($FILE_COUNT items)"
fi

# ── Summary ─────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL + WARN))

{
  echo "# T20 — Workspace Persistence Across Container Restarts"
  echo "**Date:** $(date '+%Y-%m-%d %H:%M')"
  echo ""
  echo "## Score"
  echo "- ✓ Pass: $PASS"
  echo "- ⚠ Warn: $WARN"
  echo "- ✗ Fail: $FAIL"
  echo "- Total checks: $TOTAL"
  echo ""
  echo "## What was tested"
  echo "- Files written to workspace volume before container restart"
  echo "- Container stopped and restarted with \`clawbox stop; clawbox start\`"
  echo "- Canary file, nested directory structure, git history all verified after restart"
  echo "- Container rootfs read-only enforcement"
  echo "- Agent (via \`clawbox run\`) can read and write workspace files"
  echo ""
  echo "## Key Findings"
  echo "- Canary before: '${CANARY_CONTENT}'"
  echo "- Canary after:  '${CANARY_AFTER:-unknown}'"
  echo "- Git commits: before=$COMMITS_BEFORE, after=${COMMITS_AFTER:-unknown}"
  echo "- Workspace top-level items after restart: ${FILE_COUNT:-unknown}"
  echo "- Container restart time: ${START_ELAPSED}s"
  echo ""
  echo "## Assessment"
  if [ $FAIL -eq 0 ] && [ $WARN -eq 0 ]; then
    echo "✅ All checks pass — workspace persistence fully reliable."
  elif [ $FAIL -eq 0 ]; then
    echo "⚠ No failures, but ${WARN} warning(s) — workspace persistence working with caveats."
  else
    echo "✗ ${FAIL} failure(s) — workspace persistence compromised."
  fi
} > "$RESULT_FILE"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  T20 RESULT: $PASS pass / $WARN warn / $FAIL fail (of $TOTAL)"
echo "  Result file: $RESULT_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

[ $FAIL -eq 0 ] && exit 0 || exit 1
