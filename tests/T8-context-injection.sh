#!/usr/bin/env bash
# T8 — Context injection test
#
# What: Test that `clawbox run --context <path>` correctly builds a context
#       block and passes it to the agent with the user's message appended.
# Why:  Context injection is a core UX feature for working with existing code.
# Pass: Context files are read, agent output references the injected code.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T8-context-injection.md"
CONTAINER="clawbox-work"

mkdir -p "$RESULT_DIR"

log() { echo "[T8 $(date +%H:%M:%S)] $*"; }
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠ $*"; WARN=$((WARN+1)); }

PASS=0; FAIL=0; WARN=0
START_TIME=$(date +%s)

# ── Setup: create a temp project for context injection ─────────────

TMPDIR=$(mktemp -d)
mkdir -p "$TMPDIR/src"

cat > "$TMPDIR/src/math.js" << 'JSEOF'
// Simple math utilities
function add(a, b) { return a + b; }
function subtract(a, b) { return a - b; }
module.exports = { add, subtract };
JSEOF

cat > "$TMPDIR/src/constants.js" << 'JSEOF'
module.exports = {
  PI: 3.14159,
  E: 2.71828,
};
JSEOF

cat > "$TMPDIR/src/index.js" << 'JSEOF'
const { add, subtract } = require('./math');
const { PI } = require('./constants');
module.exports = { add, subtract, PI };
JSEOF

# Ignore dirs
mkdir -p "$TMPDIR/node_modules/fake-pkg"
echo '{"name":"fake"}' > "$TMPDIR/node_modules/fake-pkg/index.js"
mkdir -p "$TMPDIR/.git"
echo "gitblob" > "$TMPDIR/.git/HEAD"

log "Created temp project: $TMPDIR"

# ── Unit test: arg parsing and context block construction ──────────

log "Testing arg parsing..."

# Source the clawbox script in a test harness
# We override the functions that touch the outside world
export T8_TMPDIR="$TMPDIR"
TEST_OUTPUT=$(bash << 'BASHEOF'
set -euo pipefail
GATEWAY_PORT=18790
GATEWAY_URL="ws://localhost:18790"
GATEWAY_TOKEN="clawbox"
LOCK_FILE="/tmp/.t8-test-lock"
TASKS_FILE="/tmp/.t8-test-tasks"
CONTAINER="clawbox-work"
CLAWBOX_DIR="/tmp"

# Stub out external dependencies
assert_container_running() { :; }
assert_not_busy() { :; }
acquire_lock() { :; }
release_lock() { :; }
openclaw() {
  # Capture the -m argument (message)
  local msg=""
  while [[ $# -gt 0 ]]; do
    if [ "$1" = "-m" ]; then shift; msg="$1"; shift; continue; fi
    shift
  done
  echo "CAPTURED_MESSAGE_START"
  printf '%s' "$msg"
  echo "CAPTURED_MESSAGE_END"
}

# Source just the cmd_run function by extracting it
eval "$(sed -n '/^cmd_run\(\)/,/^}/p' /Users/arclo/.openclaw/workspace/projects/clawbox/clawbox)"

# Test 1: single file context
cmd_run --context "$T8_TMPDIR/src/math.js" "add a multiply function"
BASHEOF
)

# Check that file content appeared in the message
if echo "$TEST_OUTPUT" | grep -q "function add"; then
  pass "Single file context: math.js content injected"
else
  fail "Single file context: math.js content NOT found in message"
fi

if echo "$TEST_OUTPUT" | grep -q "add a multiply function"; then
  pass "Single file context: original message preserved"
else
  fail "Single file context: original message NOT preserved"
fi

# ── Test: directory context ────────────────────────────────────────

log "Testing directory context injection..."

DIR_OUTPUT=$(bash << 'BASHEOF'
set -euo pipefail
GATEWAY_PORT=18790
GATEWAY_URL="ws://localhost:18790"
GATEWAY_TOKEN="clawbox"
LOCK_FILE="/tmp/.t8-test-lock"
TASKS_FILE="/tmp/.t8-test-tasks"
CONTAINER="clawbox-work"
CLAWBOX_DIR="/tmp"

assert_container_running() { :; }
assert_not_busy() { :; }
acquire_lock() { :; }
release_lock() { :; }
openclaw() {
  local msg=""
  while [[ $# -gt 0 ]]; do
    if [ "$1" = "-m" ]; then shift; msg="$1"; shift; continue; fi
    shift
  done
  printf '%s' "$msg"
}

eval "$(sed -n '/^cmd_run\(\)/,/^}/p' /Users/arclo/.openclaw/workspace/projects/clawbox/clawbox)"
cmd_run --context "$T8_TMPDIR/src" "what does this codebase do?"
BASHEOF
)

if echo "$DIR_OUTPUT" | grep -q "math.js"; then
  pass "Directory context: math.js included"
else
  fail "Directory context: math.js NOT found in context"
fi

if echo "$DIR_OUTPUT" | grep -q "constants.js"; then
  pass "Directory context: constants.js included"
else
  fail "Directory context: constants.js NOT found in context"
fi

if echo "$DIR_OUTPUT" | grep -q "index.js"; then
  pass "Directory context: index.js included"
else
  fail "Directory context: index.js NOT found in context"
fi

if echo "$DIR_OUTPUT" | grep -q "what does this codebase do"; then
  pass "Directory context: user message appended after context"
else
  fail "Directory context: user message NOT found after context"
fi

# ── Test: node_modules excluded ────────────────────────────────────

if echo "$DIR_OUTPUT" | grep -q "fake-pkg"; then
  fail "node_modules NOT excluded from context"
else
  pass "node_modules correctly excluded from context"
fi

if echo "$DIR_OUTPUT" | grep -q "gitblob"; then
  fail ".git NOT excluded from context"
else
  pass ".git correctly excluded from context"
fi

# ── Test: invalid path error ───────────────────────────────────────

log "Testing error handling..."

INVALID_OUTPUT=$(bash 2>&1 <<'BASHEOF' || true
set -uo pipefail
GATEWAY_PORT=18790; GATEWAY_URL="ws://localhost:18790"; GATEWAY_TOKEN="clawbox"
LOCK_FILE="/tmp/.t8-lock"; TASKS_FILE="/tmp/.t8-tasks"; CONTAINER="clawbox-work"; CLAWBOX_DIR="/tmp"
assert_container_running() { :; }; assert_not_busy() { :; }; acquire_lock() { :; }; release_lock() { :; }
openclaw() { :; }
eval "$(sed -n '/^cmd_run\(\)/,/^}/p' /Users/arclo/.openclaw/workspace/projects/clawbox/clawbox)"
cmd_run --context /nonexistent/path "hello" 2>&1 || true
BASHEOF
)
if echo "$INVALID_OUTPUT" | grep -q "not found"; then
  pass "Invalid context path: clear error message shown"
else
  fail "Invalid context path: no error shown (got: $INVALID_OUTPUT)"
fi

# ── Test: --thinking flag ──────────────────────────────────────────

log "Testing --thinking flag..."

THINKING_OUTPUT=$(bash << 'BASHEOF'
set -euo pipefail
GATEWAY_PORT=18790
GATEWAY_URL="ws://localhost:18790"
GATEWAY_TOKEN="clawbox"
LOCK_FILE="/tmp/.t8-test-lock"
TASKS_FILE="/tmp/.t8-test-tasks"
CONTAINER="clawbox-work"
CLAWBOX_DIR="/tmp"

assert_container_running() { :; }
assert_not_busy() { :; }
acquire_lock() { :; }
release_lock() { :; }
openclaw() {
  echo "ARGS: $*"
}

eval "$(sed -n '/^cmd_run\(\)/,/^}/p' /Users/arclo/.openclaw/workspace/projects/clawbox/clawbox)"
cmd_run --thinking medium "solve this hard problem"
BASHEOF
)

if echo "$THINKING_OUTPUT" | grep -q "medium"; then
  pass "--thinking medium: thinking level passed to openclaw"
else
  fail "--thinking medium: thinking level NOT in openclaw args (got: $THINKING_OUTPUT)"
fi

# ── Test: help output ──────────────────────────────────────────────

log "Testing help output..."
HELP_OUTPUT=$("$CLAWBOX" help 2>&1)
if echo "$HELP_OUTPUT" | grep -q "\-\-context"; then
  pass "help: --context documented"
else
  fail "help: --context NOT in help output"
fi
if echo "$HELP_OUTPUT" | grep -q "\-\-thinking"; then
  pass "help: --thinking documented"
else
  fail "help: --thinking NOT in help output"
fi

# ── Live end-to-end test (if container is running) ─────────────────

CONTAINER_RUNNING=$(docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null || echo "false")
E2E_RESULT="(skipped — container not running)"
E2E_STATUS="skipped"

if [ "$CONTAINER_RUNNING" = "true" ]; then
  log "Container is running — doing live e2e test..."
  E2E_START=$(date +%s)
  E2E_OUTPUT=$("$CLAWBOX" run --context "$TMPDIR/src" "List the exported functions from this codebase in one sentence." 2>&1 || true)
  E2E_END=$(date +%s)
  E2E_ELAPSED=$((E2E_END - E2E_START))
  E2E_RESULT="$E2E_OUTPUT"

  if echo "$E2E_OUTPUT" | grep -qiE "(add|subtract|PI)"; then
    pass "Live e2e: agent response mentions injected code symbols"
    E2E_STATUS="pass"
  else
    warn "Live e2e: agent response may not reference injected code (or symbols changed)"
    E2E_STATUS="warn"
  fi
else
  warn "Container not running — skipped live e2e test"
fi

# ── Cleanup ────────────────────────────────────────────────────────

rm -rf "$TMPDIR"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# ── Write results ──────────────────────────────────────────────────

cat > "$RESULT_FILE" << RESULT_EOF
# T8 — Context injection test
**Date:** $(date '+%Y-%m-%d %H:%M')
**Duration:** ${ELAPSED}s

## Summary

| Metric | Value |
|--------|-------|
| Pass | $PASS |
| Warn | $WARN |
| Fail | $FAIL |
| E2E live test | $E2E_STATUS |

## What was tested
- Single-file context injection via \`--context <file>\`
- Directory context injection via \`--context <dir>\`
- node_modules and .git exclusion from context
- Invalid path error handling
- \`--thinking\` flag forwarding to openclaw
- Help text documentation

## Live E2E Result
\`\`\`
$E2E_RESULT
\`\`\`

## Assessment
$([ $FAIL -eq 0 ] && echo "✓ All unit tests passed" || echo "✗ $FAIL test(s) failed")
$([ $WARN -gt 0 ] && echo "⚠ $WARN warning(s)" || echo "✓ No warnings")
RESULT_EOF

log "Results written to $RESULT_FILE"
log "Done. Pass=$PASS Warn=$WARN Fail=$FAIL"

# Exit with failure if any tests failed
[ $FAIL -eq 0 ] || exit 1
