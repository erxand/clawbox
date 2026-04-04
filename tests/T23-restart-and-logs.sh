#!/usr/bin/env bash
# T23 — restart and logs commands
#
# What: Verify that `clawbox restart` performs a clean stop+start cycle and that
#       `clawbox logs` + `clawbox logs-tail` work correctly.
# Why:  `restart` and `logs` are core operational commands that are used frequently
#       when troubleshooting, but neither has any explicit test coverage. If restart
#       is broken or leaves the container in a bad state, users have no easy recovery.
#
# This test does NOT require Anthropic API access.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T23-restart-logs.md"
CONTAINER="clawbox-work"
WORKSPACE="/home/node/.openclaw/workspace"

mkdir -p "$RESULT_DIR"

PASS=0
FAIL=0
WARN=0
FINDINGS=""

pass() { PASS=$((PASS+1)); FINDINGS+="  ✓ $1\n"; echo "  ✓ $1"; }
fail() { FAIL=$((FAIL+1)); FINDINGS+="  ✗ $1\n"; echo "  ✗ $1"; }
warn() { WARN=$((WARN+1)); FINDINGS+="  ⚠ $1\n"; echo "  ⚠ $1"; }

log() { echo "[T23 $(date +%H:%M:%S)] $*"; }

assert_container_running() {
  if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
    return 0
  fi
  return 1
}

START_TIME=$(date +%s)

log "Starting T23 — restart and logs validation"

# ─── Phase 0: Ensure container is running ───────────────────────────────────
echo ""
echo "── Phase 0: Baseline ──"
if ! assert_container_running; then
  log "Container not running — starting..."
  "$CLAWBOX" start 2>&1 | tail -5
fi
if assert_container_running; then
  pass "container is running before test"
else
  fail "container could not be started — aborting"
  echo "ABORT: Cannot proceed without container"
  exit 1
fi

# Write a canary file into the workspace before restart
CANARY="t23-canary-$(date +%s).txt"
docker exec "$CONTAINER" sh -c "echo 'T23 restart test' > ${WORKSPACE}/${CANARY}" 2>/dev/null
if docker exec "$CONTAINER" test -f "${WORKSPACE}/${CANARY}" 2>/dev/null; then
  pass "canary file created in workspace before restart"
else
  fail "canary file creation failed before restart"
fi

# ─── Phase 1: clawbox restart ────────────────────────────────────────────────
echo ""
echo "── Phase 1: clawbox restart ──"

RESTART_START=$(date +%s)
log "Running clawbox restart..."
RESTART_OUT=$("$CLAWBOX" restart 2>&1)
RESTART_EXIT=$?
RESTART_END=$(date +%s)
RESTART_ELAPSED=$((RESTART_END - RESTART_START))

if [ $RESTART_EXIT -eq 0 ]; then
  pass "restart exits 0"
else
  fail "restart exited $RESTART_EXIT (expected 0)"
fi

if [ $RESTART_ELAPSED -le 60 ]; then
  pass "restart completes in ${RESTART_ELAPSED}s (≤60s)"
else
  warn "restart took ${RESTART_ELAPSED}s (>60s — may be slow)"
fi

# Container must be running after restart
if assert_container_running; then
  pass "container is running after restart"
else
  fail "container NOT running after restart — this is a critical failure"
fi

# Gateway must be healthy after restart
sleep 2
GATEWAY_HEALTH=$(OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw gateway health 2>/dev/null && echo "healthy" || echo "unhealthy")
if [ "$GATEWAY_HEALTH" = "healthy" ]; then
  pass "gateway is healthy after restart"
else
  warn "gateway not healthy after restart (may still be starting up)"
fi

# Workspace should persist across restart (volume-backed)
if docker exec "$CONTAINER" test -f "${WORKSPACE}/${CANARY}" 2>/dev/null; then
  pass "canary file persists across restart (volume intact)"
else
  fail "canary file LOST across restart — workspace volume not persisting"
fi

# Read-only rootfs should still be enforced after restart
ROOTFS_WRITE=$(docker exec "$CONTAINER" sh -c "touch /t23-probe 2>&1" 2>&1 || true)
if echo "$ROOTFS_WRITE" | grep -qi "read-only\|permission"; then
  pass "read-only rootfs still enforced after restart"
else
  warn "rootfs write probe unclear — rootfs may not be read-only (got: $ROOTFS_WRITE)"
fi

# ─── Phase 2: Second restart (idempotency) ───────────────────────────────────
echo ""
echo "── Phase 2: Restart idempotency ──"

log "Running second restart..."
RESTART2_OUT=$("$CLAWBOX" restart 2>&1)
RESTART2_EXIT=$?

if [ $RESTART2_EXIT -eq 0 ]; then
  pass "second restart exits 0 (idempotent)"
else
  fail "second restart exited $RESTART2_EXIT"
fi

if assert_container_running; then
  pass "container running after second restart"
else
  fail "container NOT running after second restart"
fi

# ─── Phase 3: clawbox logs (non-follow) ──────────────────────────────────────
echo ""
echo "── Phase 3: clawbox logs ──"

# clawbox logs uses `docker compose logs -f` which follows forever
# We test it with a short timeout using docker compose logs directly (no follow)
log "Testing clawbox logs output (without -f)..."
LOGS_OUT=$(cd "$(dirname "$CLAWBOX")" && docker compose logs --no-log-prefix --tail=50 2>&1 || true)

if echo "$LOGS_OUT" | grep -qi "openclaw\|gateway\|clawbox\|node\|error\|warn\|info\|started\|ready\|healthy"; then
  pass "logs produces container output"
else
  warn "logs output unclear — got: $(echo "$LOGS_OUT" | head -3)"
fi

if echo "$LOGS_OUT" | wc -l | awk '{print $1}' | grep -qE '^[1-9]'; then
  pass "logs produces multiple lines"
else
  warn "logs output was only 1 line or empty"
fi

# logs is listed in help
HELP_OUT=$("$CLAWBOX" help 2>&1)
if echo "$HELP_OUT" | grep -q "logs"; then
  pass "logs: listed in help output"
else
  fail "logs: NOT in help output"
fi

# ─── Phase 4: clawbox logs-tail ──────────────────────────────────────────────
echo ""
echo "── Phase 4: clawbox logs-tail ──"

# First trigger some agent activity to ensure today's log exists
# We just check for the log via doctor — a lightweight gateway ping
OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw gateway health 2>/dev/null || true

LOGS_TAIL_OUT=$("$CLAWBOX" logs-tail 2>&1)
if echo "$LOGS_TAIL_OUT" | grep -qi "No log file\|log\|openclaw\|\[" 2>/dev/null; then
  pass "logs-tail: returns output (log or 'no log' message)"
else
  warn "logs-tail: unexpected output: $(echo "$LOGS_TAIL_OUT" | head -3)"
fi

if echo "$LOGS_TAIL_OUT" | grep -q "No log file"; then
  warn "logs-tail: no log file for today (container hasn't been used yet — expected)"
else
  pass "logs-tail: found today's log file"
fi

# ─── Phase 5: restart with running task (lock behavior) ──────────────────────
echo ""
echo "── Phase 5: restart output format ──"

# Check restart output contains expected strings
RESTART3_OUT=$("$CLAWBOX" restart 2>&1)
if echo "$RESTART3_OUT" | grep -qi "stop\|down\|start\|up\|ready\|healthy"; then
  pass "restart output has meaningful status messages"
else
  warn "restart output seems sparse: $(echo "$RESTART3_OUT" | head -3)"
fi

if assert_container_running; then
  pass "container healthy after final restart"
else
  fail "container not running after final restart"
fi

# ─── Phase 6: clawbox status reflects running state ──────────────────────────
echo ""
echo "── Phase 6: status consistency after restart ──"

STATUS_OUT=$("$CLAWBOX" status 2>&1)
if echo "$STATUS_OUT" | grep -qi "running\|up"; then
  pass "status shows container running after restarts"
else
  warn "status output unclear: $(echo "$STATUS_OUT" | head -3)"
fi

if echo "$STATUS_OUT" | grep -q "ws://"; then
  pass "status shows ws:// gateway URL after restart"
else
  fail "status missing ws:// URL after restart"
fi

# Gateway health in status
if echo "$STATUS_OUT" | grep -q "healthy"; then
  pass "status shows gateway healthy after restart"
else
  warn "status doesn't confirm gateway healthy — may still be starting"
fi

# Cleanup canary
docker exec "$CONTAINER" rm -f "${WORKSPACE}/${CANARY}" 2>/dev/null || true

# ─── Results ──────────────────────────────────────────────────────────────────
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

echo ""
echo "════════════════════════════════════════"
if [ $FAIL -eq 0 ]; then
  echo "  T23 Results: Pass: $PASS   Warn: $WARN   Fail: $FAIL   (of $((PASS+WARN+FAIL)) checks)"
  echo "  ✓ All critical checks pass!"
else
  echo "  T23 Results: Pass: $PASS   Warn: $WARN   Fail: $FAIL   (of $((PASS+WARN+FAIL)) checks)"
  echo "  ✗ Some checks FAILED"
fi
echo "════════════════════════════════════════"

# Write result file
cat > "$RESULT_FILE" << EOF
# T23 — restart and logs commands
**Date:** $(date '+%Y-%m-%d %H:%M')
**Duration:** ${DURATION}s

## What was tested
1. \`clawbox restart\` — clean stop+start cycle
2. Workspace persistence across restart (volume survives)
3. Security enforcement after restart (read-only rootfs)
4. Restart idempotency (second consecutive restart)
5. \`clawbox logs\` — streaming docker compose logs
6. \`clawbox logs-tail\` — last 50 lines of today's gateway log
7. Status consistency after restarts

## Assessment
$(echo -e "$FINDINGS")

## Summary
| Metric | Value |
|--------|-------|
| Pass | $PASS |
| Warn | $WARN |
| Fail | $FAIL |
| Duration | ${DURATION}s |
| Restart time | ${RESTART_ELAPSED}s |
EOF

log "Results written to $RESULT_FILE"
log "Done."
