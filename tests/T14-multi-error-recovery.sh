#!/usr/bin/env bash
# T14 — Multi-error recovery
#
# What: Set up a project with MULTIPLE simultaneous errors, ask agent to diagnose
#       and fix everything so tests pass. Tests more complex diagnostic reasoning
#       than T4's single MODULE_NOT_FOUND.
#
# Errors introduced:
#   1. Syntax error in main server file (unexpected token)
#   2. Wrong import path (module exists but path is wrong)
#   3. Port conflict — start a listener on 3001 before agent tries to use it
#   4. Broken test (test calls a function that doesn't exist)
#
# Why:  Real projects fail in multiple places at once. Does the agent work through
#       all failures systematically, or fix one and give up? Phase 2 open item:
#       "Self-recovery prompts: If the agent gets a tool error, does it retry
#       intelligently? Test and document the failure modes."
#
# Success criteria:
#   - Agent identifies and fixes all (or most) errors
#   - Test suite ends with 0 failures
#   - Agent doesn't spiral or give up after first fix

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T14-multi-error-recovery.md"
CONTAINER="clawbox-work"

mkdir -p "$RESULT_DIR"

PASS=0
FAIL=0
WARN=0

log() { echo "[T14 $(date +%H:%M:%S)] $*"; }
pass() { echo "✓ $*"; PASS=$((PASS+1)); }
fail() { echo "✗ $*"; FAIL=$((FAIL+1)); }
warn() { echo "⚠ $*"; WARN=$((WARN+1)); }

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

log "Setting up multi-error project..."

# Create a project with 4 deliberate errors
docker exec "$CONTAINER" sh -c "
  mkdir -p /home/node/.openclaw/workspace/multi-error-app
  cd /home/node/.openclaw/workspace/multi-error-app

  # Initialize project
  npm init -y
  npm install express

  # Create a utility module (correct)
  cat > utils.js << 'EOF'
function add(a, b) { return a + b; }
function multiply(a, b) { return a * b; }
module.exports = { add, multiply };
EOF

  # ERROR 1: Syntax error in server — missing closing brace
  cat > server.js << 'EOF'
const express = require('express');
const { add, multiply } = require('./utils');

const app = express();

app.get('/add', (req, res) => {
  const a = parseInt(req.query.a) || 0;
  const b = parseInt(req.query.b) || 0;
  res.json({ result: add(a, b) });
// ERROR: missing closing brace for app.get

app.get('/multiply', (req, res) => {
  const a = parseInt(req.query.a) || 0;
  const b = parseInt(req.query.b) || 0;
  res.json({ result: multiply(a, b) });
});

const PORT = process.env.PORT || 3002;
app.listen(PORT, () => console.log('Running on ' + PORT));
module.exports = app;
EOF

  # ERROR 2: Test file imports from wrong path AND calls nonexistent function
  cat > test.js << 'EOF'
// Simple test runner (no external deps)
const assert = require('assert');

// ERROR 2a: wrong import path (./helpers does not exist; should be ./utils)
const { add, multiply } = require('./helpers');

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log('PASS:', name);
    passed++;
  } catch(e) {
    console.log('FAIL:', name, '-', e.message);
    failed++;
  }
}

test('add 2+3 = 5', () => assert.strictEqual(add(2, 3), 5));
test('multiply 3*4 = 12', () => assert.strictEqual(multiply(3, 4), 12));

// ERROR 2b: calls subtract() which doesn't exist in utils
test('subtract 10-4 = 6', () => assert.strictEqual(subtract(10, 4), 6));

console.log('Results:', passed, 'passed,', failed, 'failed');
process.exit(failed > 0 ? 1 : 0);
EOF

  echo 'Project created with deliberate errors'
  echo '--- files ---'
  ls -la
"

# ── Capture initial error state ────────────────────────────────────

log "Capturing initial error state..."

SERVER_ERROR=$(docker exec "$CONTAINER" sh -c "
  cd /home/node/.openclaw/workspace/multi-error-app
  node server.js 2>&1 || true
" 2>/dev/null | head -5)

TEST_ERROR=$(docker exec "$CONTAINER" sh -c "
  cd /home/node/.openclaw/workspace/multi-error-app
  node test.js 2>&1 || true
" 2>/dev/null | head -5)

log "Server error: $SERVER_ERROR"
log "Test error: $TEST_ERROR"

# ── Ask agent to diagnose and fix everything ───────────────────────

TASK_MSG="I have a Node.js project at /home/node/.openclaw/workspace/multi-error-app that's broken in multiple places. Please:
1. Run the server (node server.js) and see what error you get
2. Run the tests (node test.js) and see what errors you get
3. Fix ALL the errors you find — there may be more than one
4. Once everything is fixed, confirm: (a) node server.js starts without errors, and (b) all tests pass with 0 failures

Be systematic: fix one thing, test again, fix the next thing. Don't give up after fixing one error."

log "Asking agent to diagnose and fix all errors..."
AGENT_START=$(date +%s)

AGENT_OUTPUT=$(OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw agent --agent main -m "$TASK_MSG" 2>&1 || true)

AGENT_END=$(date +%s)
AGENT_TIME=$((AGENT_END - AGENT_START))
log "Agent finished in ${AGENT_TIME}s"

# ── Verify fixes ───────────────────────────────────────────────────

log "Verifying all fixes..."

# Check 1: server.js syntax fixed
SYNTAX_CHECK=$(docker exec "$CONTAINER" sh -c "
  cd /home/node/.openclaw/workspace/multi-error-app
  node --check server.js 2>&1; echo EXIT:\$?
" 2>/dev/null)
SYNTAX_EXIT=$(echo "$SYNTAX_CHECK" | grep "EXIT:" | cut -d: -f2 | tr -d ' \n')

if [ "$SYNTAX_EXIT" = "0" ]; then
  pass "server.js syntax is valid (Error 1 fixed)"
else
  fail "server.js still has syntax error: $SYNTAX_CHECK"
fi

# Check 2: test.js import path fixed (no ./helpers reference)
# Note: if all tests pass (check 3) the import is definitely fixed — this is a secondary signal
IMPORT_CHECK=$(docker exec "$CONTAINER" sh -c "grep -c 'helpers' /home/node/.openclaw/workspace/multi-error-app/test.js 2>/dev/null || echo 0" 2>/dev/null | tr -d ' \n')
if [ "$IMPORT_CHECK" = "0" ]; then
  pass "Wrong import path fixed — no 'helpers' reference remains in test.js (Error 2a fixed)"
else
  # Tests passing is the authoritative signal; this grep check is secondary
  warn "test.js grep found 'helpers' ($IMPORT_CHECK times) — if tests pass, import is fixed anyway"
fi

# Check 3: tests pass
TEST_RESULT=$(docker exec "$CONTAINER" sh -c "
  cd /home/node/.openclaw/workspace/multi-error-app
  node test.js 2>&1; echo EXIT:\$?
" 2>/dev/null)
TEST_EXIT=$(echo "$TEST_RESULT" | grep "EXIT:" | cut -d: -f2 | tr -d ' \n')
TESTS_FAILED=$(echo "$TEST_RESULT" | grep -o "[0-9]* failed" | head -1)

if [ "$TEST_EXIT" = "0" ]; then
  pass "All tests pass (Errors 2a + 2b fixed)"
elif echo "$TEST_RESULT" | grep -q "0 failed"; then
  pass "All tests pass (Errors 2a + 2b fixed)"
else
  fail "Tests still failing: $TESTS_FAILED — $(echo "$TEST_RESULT" | grep FAIL | head -3)"
fi

# Check 4: server starts without errors
SERVER_RESULT=$(docker exec "$CONTAINER" sh -c "
  cd /home/node/.openclaw/workspace/multi-error-app
  PORT=3002 timeout 5 node server.js 2>&1 &
  sleep 2
  kill %1 2>/dev/null || true
  wait 2>/dev/null || true
  echo EXIT:\$?
" 2>/dev/null)

if ! echo "$SERVER_RESULT" | grep -qiE "SyntaxError|Error:|Cannot find"; then
  pass "Server starts without errors (all errors fixed)"
else
  fail "Server still has errors on start: $(echo "$SERVER_RESULT" | grep -iE "Error" | head -2)"
fi

# Check 5: Did the agent work through errors systematically?
AGENT_FIXED_MULTIPLE=$(echo "$AGENT_OUTPUT" | grep -ci "fix\|error\|syntax\|import\|module" || echo "0")
if [ "$AGENT_FIXED_MULTIPLE" -gt 3 ]; then
  pass "Agent engaged with multiple errors (mentioned fix/error/import $AGENT_FIXED_MULTIPLE times)"
else
  warn "Unclear if agent systematically addressed all errors (only $AGENT_FIXED_MULTIPLE relevant mentions)"
fi

# Check 6: Agent didn't give up early
AGENT_LINES=$(echo "$AGENT_OUTPUT" | wc -l | tr -d ' ')
if [ "$AGENT_LINES" -gt 20 ]; then
  pass "Agent produced substantive output ($AGENT_LINES lines — didn't give up early)"
else
  warn "Agent output seems short ($AGENT_LINES lines) — may have given up"
fi

# ── Show final state of fixed files ───────────────────────────────

FINAL_SERVER=$(docker exec "$CONTAINER" cat /home/node/.openclaw/workspace/multi-error-app/server.js 2>/dev/null || echo "(not found)")
FINAL_TEST=$(docker exec "$CONTAINER" cat /home/node/.openclaw/workspace/multi-error-app/test.js 2>/dev/null || echo "(not found)")

# ── Summary ───────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL + WARN))
log "Results: $PASS pass, $FAIL fail, $WARN warn (of $TOTAL checks)"

cat > "$RESULT_FILE" << RESULT_EOF
# T14 — Multi-error recovery
**Date:** $(date '+%Y-%m-%d %H:%M')
**Agent time:** ${AGENT_TIME}s

## Errors introduced
1. **Syntax error:** Missing closing brace in \`server.js\` app.get handler
2a. **Wrong import path:** \`test.js\` imports from \`./helpers\` (doesn't exist; should be \`./utils\`)
2b. **Nonexistent function:** \`test.js\` calls \`subtract()\` which isn't exported from utils
*(No port conflict test in this run — port 3002 used to avoid conflict)*

## Initial error state
### server.js error:
\`\`\`
$SERVER_ERROR
\`\`\`

### test.js error:
\`\`\`
$TEST_ERROR
\`\`\`

## Results

| Check | Result |
|-------|--------|
| server.js syntax fixed | $([ "$SYNTAX_EXIT" = "0" ] && echo "✓ yes" || echo "✗ no") |
| Wrong import path fixed | $([ "$IMPORT_CHECK" = "0" ] && echo "✓ yes" || echo "⚠ check manually") |
| All tests pass | $([ "$TEST_EXIT" = "0" ] && echo "✓ yes" || echo "✗ no ($TESTS_FAILED)") |
| Server starts clean | $(echo "$SERVER_RESULT" | grep -qiE "SyntaxError|Error:|Cannot find" && echo "✗ no" || echo "✓ yes") |
| Agent worked systematically | $([ "$AGENT_FIXED_MULTIPLE" -gt 3 ] && echo "✓ yes ($AGENT_FIXED_MULTIPLE relevant mentions)" || echo "⚠ unclear ($AGENT_FIXED_MULTIPLE mentions)") |
| Agent didn't give up | $([ "$AGENT_LINES" -gt 20 ] && echo "✓ yes ($AGENT_LINES lines output)" || echo "⚠ may have given up ($AGENT_LINES lines)") |

**Pass:** $PASS / $TOTAL | **Fail:** $FAIL | **Warn:** $WARN

## Final server.js
\`\`\`javascript
$FINAL_SERVER
\`\`\`

## Final test.js
\`\`\`javascript
$FINAL_TEST
\`\`\`

## Test run output
\`\`\`
$TEST_RESULT
\`\`\`

## Agent output (last 40 lines)
\`\`\`
$(echo "$AGENT_OUTPUT" | tail -40)
\`\`\`

## Findings
- Agent time: ${AGENT_TIME}s
- Syntax error fix: $([ "$SYNTAX_EXIT" = "0" ] && echo "yes" || echo "no")
- Import path fix: $([ "$IMPORT_CHECK" = "0" ] && echo "yes" || echo "no")
- Missing function fix: $([ "$TEST_EXIT" = "0" ] && echo "yes" || echo "no/partial")
- All tests clean: $([ "$TEST_EXIT" = "0" ] && echo "yes" || echo "no")
RESULT_EOF

log "Results written to $RESULT_FILE"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
