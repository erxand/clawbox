#!/usr/bin/env bash
# T4 — Error recovery test
#
# What: Deliberately break something, then ask the agent to diagnose and fix it.
# Why:  Tests whether the agent can handle unexpected errors gracefully.
# Good: Agent identifies the problem, fixes it in few tool calls, node runs clean.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T4-error-recovery.md"
CONTAINER="clawbox-work"

mkdir -p "$RESULT_DIR"

log() { echo "[T4 $(date +%H:%M:%S)] $*"; }

wait_healthy() {
  for i in $(seq 1 60); do
    STATUS=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "missing")
    if [ "$STATUS" = "healthy" ]; then return 0; fi
    sleep 2
  done
  log "WARNING: container did not become healthy within 120s"
  return 1
}

# ── Setup ───────────────────────────────────────────────────────────

log "Starting fresh container..."
"$CLAWBOX" stop 2>/dev/null || true
"$CLAWBOX" start
wait_healthy

# ── Create the broken state ────────────────────────────────────────

log "Setting up npm project and breaking it..."

# Create a simple project, then introduce a broken require
docker exec "$CONTAINER" sh -c "
  cd /home/node/workspace &&
  mkdir -p broken-project &&
  cd broken-project &&
  npm init -y &&
  npm install express &&
  cat > index.js << 'INNEREOF'
const express = require('express');
const missing = require('nonexistent-package');

const app = express();
app.get('/', (req, res) => res.send('Hello'));
app.listen(3000);
INNEREOF
"

# Capture the error
INITIAL_ERROR=$(docker exec "$CONTAINER" sh -c "cd /home/node/workspace/broken-project && node index.js 2>&1" || true)
log "Initial error: $(echo "$INITIAL_ERROR" | head -3)"

# ── Ask agent to fix it ───────────────────────────────────────────

FIX_MSG="I was trying to build something in /home/node/workspace/broken-project but got an error. Check what went wrong and fix it so node runs without errors. Try running: cd /home/node/workspace/broken-project && node index.js"

log "Asking agent to diagnose and fix..."
FIX_START=$(date +%s)

AGENT_OUTPUT=$(OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw agent --agent main -m "$FIX_MSG" 2>&1 || true)

FIX_END=$(date +%s)
FIX_TIME=$((FIX_END - FIX_START))
log "Agent responded in ${FIX_TIME}s"

# ── Verify fix ─────────────────────────────────────────────────────

log "Verifying fix..."
VERIFY_OUTPUT=$(docker exec "$CONTAINER" sh -c "cd /home/node/workspace/broken-project && timeout 5 node index.js 2>&1 &
sleep 2
curl -s http://localhost:3000 2>/dev/null || echo 'CURL_FAIL'
kill %1 2>/dev/null || true
wait 2>/dev/null || true" || echo "VERIFY_FAIL")

FIXED_INDEX=$(docker exec "$CONTAINER" cat /home/node/workspace/broken-project/index.js 2>/dev/null || echo "(not found)")

# Check if the fix worked
FIX_WORKED="no"
if echo "$VERIFY_OUTPUT" | grep -qi "hello\|CURL_FAIL"; then
  # Even CURL_FAIL is OK if node started without error
  NODE_TEST=$(docker exec "$CONTAINER" sh -c "cd /home/node/workspace/broken-project && node -e \"require('./index.js')\" 2>&1 &
  sleep 1
  kill %1 2>/dev/null
  echo 'OK'" 2>/dev/null || echo "FAIL")
  if echo "$NODE_TEST" | grep -q "OK"; then FIX_WORKED="yes"; fi
fi

# Simpler check: does the file still reference nonexistent-package?
if ! docker exec "$CONTAINER" grep -q "nonexistent-package" /home/node/workspace/broken-project/index.js 2>/dev/null; then
  FIX_WORKED="yes"
fi

# ── Write results ──────────────────────────────────────────────────

cat > "$RESULT_FILE" << RESULT_EOF
# T4 — Error recovery test
**Date:** $(date '+%Y-%m-%d %H:%M')
**Fix time:** ${FIX_TIME}s

## What was tested
1. Created an npm project with Express
2. Added a \`require('nonexistent-package')\` to break it
3. Asked the agent to diagnose and fix

## Initial error
\`\`\`
$INITIAL_ERROR
\`\`\`

## Agent response (summary)
\`\`\`
$(echo "$AGENT_OUTPUT" | tail -30)
\`\`\`

## Fixed index.js
\`\`\`javascript
$FIXED_INDEX
\`\`\`

## Verification
\`\`\`
$VERIFY_OUTPUT
\`\`\`

## Assessment
$([ "$FIX_WORKED" = "yes" ] && echo "✓ Agent diagnosed and fixed the error" || echo "✗ Agent did NOT successfully fix the error")
- Time to fix: ${FIX_TIME}s
- Did it diagnose correctly? $(echo "$AGENT_OUTPUT" | grep -qi "nonexistent\|missing\|not found\|cannot find" && echo "Yes" || echo "Unclear")
RESULT_EOF

log "Results written to $RESULT_FILE"
log "Done."
