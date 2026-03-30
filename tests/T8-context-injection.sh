#!/usr/bin/env bash
# T8 — Context injection test
#
# What: Test that `clawbox run --context <path>` correctly builds a context
#       block and passes it to the agent with the user's message appended.
# Why:  Context injection is a core UX feature for working with existing code.
# Pass: Context files are read, agent output references the injected code.
#
# Strategy: Behavioral (live container) tests + CLI/help checks.
# The old unit test approach (eval-extracting cmd_run) was fragile due to
# complex quoting inside the function body.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
LIB_DIR="${SCRIPT_DIR}/lib"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T8-context-injection.md"
CONTAINER="clawbox-work"

mkdir -p "$RESULT_DIR"

# Source shared helpers if available
[ -f "$LIB_DIR/common.sh" ] && source "$LIB_DIR/common.sh"

log() { echo "[T8 $(date +%H:%M:%S)] $*"; }
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠ $*"; WARN=$((WARN+1)); }

PASS=0; FAIL=0; WARN=0
START_TIME=$(date +%s)

# ── Setup: create a temp project for context injection ─────────────

TMPDIR_CTX=$(mktemp -d)
mkdir -p "$TMPDIR_CTX/src"

cat > "$TMPDIR_CTX/src/math.js" << 'JSEOF'
// Simple math utilities
function add(a, b) { return a + b; }
function subtract(a, b) { return a - b; }
module.exports = { add, subtract };
JSEOF

cat > "$TMPDIR_CTX/src/constants.js" << 'JSEOF'
module.exports = {
  PI: 3.14159,
  E: 2.71828,
};
JSEOF

cat > "$TMPDIR_CTX/src/index.js" << 'JSEOF'
const { add, subtract } = require('./math');
const { PI } = require('./constants');
module.exports = { add, subtract, PI };
JSEOF

# Ignored dirs (should be excluded from context)
mkdir -p "$TMPDIR_CTX/node_modules/fake-pkg"
echo '{"name":"fake-pkg"}' > "$TMPDIR_CTX/node_modules/fake-pkg/index.js"
mkdir -p "$TMPDIR_CTX/.git"
echo "gitblob" > "$TMPDIR_CTX/.git/HEAD"

log "Created temp project: $TMPDIR_CTX"

# ── Check: container running ───────────────────────────────────────

CONTAINER_RUNNING=$(docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null || echo "false")

# ── 1. Help text covers --context and --thinking ───────────────────

log "Checking help text..."

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

# ── 2. Error: invalid context path ────────────────────────────────

log "Testing error handling for invalid path..."

INVALID_OUTPUT=$("$CLAWBOX" run --context /nonexistent/path/xyz "hello" 2>&1 || true)
if echo "$INVALID_OUTPUT" | grep -qiE "(not found|no such|error)"; then
  pass "Invalid context path: clear error shown"
else
  fail "Invalid context path: no error shown (got: $INVALID_OUTPUT)"
fi

# ── 3. Error: missing message ──────────────────────────────────────

MISSING_MSG_OUTPUT=$("$CLAWBOX" run --context "$TMPDIR_CTX/src/math.js" 2>&1 || true)
if echo "$MISSING_MSG_OUTPUT" | grep -qi "usage"; then
  pass "Missing message with --context: usage shown"
else
  warn "Missing message with --context: unclear error (got: $MISSING_MSG_OUTPUT)"
fi

# ── 4. Live e2e tests (require running container) ──────────────────

if [ "$CONTAINER_RUNNING" != "true" ]; then
  warn "Container not running — skipping live e2e tests"
  E2E_SINGLE_RESULT="(skipped)"
  E2E_DIR_RESULT="(skipped)"
  E2E_THINKING_RESULT="(skipped)"
else
  log "Container running — performing live e2e tests..."

  # 4a. Single file context
  log "Test 4a: single-file context (math.js)..."
  E2E_SINGLE_RESULT=$("$CLAWBOX" run --context "$TMPDIR_CTX/src/math.js" \
    "In one line, what functions does this file export?" 2>&1 || true)

  # Rate limit check
  if type -f is_rate_limited &>/dev/null && is_rate_limited "$E2E_SINGLE_RESULT"; then
    warn "API rate limited during single-file context test — skipping"
    skip_rate_limited "$RESULT_FILE" "T8" || true
    exit 0
  fi

  if echo "$E2E_SINGLE_RESULT" | grep -qiE "(add|subtract)"; then
    pass "Single-file context: agent response references injected code (add/subtract found)"
  else
    fail "Single-file context: agent response doesn't mention exported functions"
  fi

  if echo "$E2E_SINGLE_RESULT" | grep -qi "multiply"; then
    warn "Single-file context: agent hallucinated 'multiply' function (not in file)"
  fi

  # 4b. Directory context
  log "Test 4b: directory context (src/)..."
  E2E_DIR_RESULT=$("$CLAWBOX" run --context "$TMPDIR_CTX/src" \
    "Name all the exported values from this codebase in a comma-separated list." 2>&1 || true)

  if type -f is_rate_limited &>/dev/null && is_rate_limited "$E2E_DIR_RESULT"; then
    warn "API rate limited during directory context test"
    E2E_DIR_RESULT="(rate limited)"
  else
    MENTIONED=0
    echo "$E2E_DIR_RESULT" | grep -qi "add"      && MENTIONED=$((MENTIONED+1))
    echo "$E2E_DIR_RESULT" | grep -qi "subtract"  && MENTIONED=$((MENTIONED+1))
    echo "$E2E_DIR_RESULT" | grep -qi "PI"        && MENTIONED=$((MENTIONED+1))

    if [ $MENTIONED -ge 2 ]; then
      pass "Directory context: agent mentions ≥2 of add/subtract/PI (score: $MENTIONED/3)"
    else
      fail "Directory context: agent only mentioned $MENTIONED/3 expected symbols"
    fi

    # Verify node_modules/fake-pkg NOT mentioned (was excluded)
    if echo "$E2E_DIR_RESULT" | grep -qi "fake-pkg"; then
      fail "Directory context: node_modules NOT excluded (fake-pkg found in response)"
    else
      pass "Directory context: node_modules correctly excluded from context"
    fi
  fi

  # 4c. --thinking flag is forwarded (use --quiet to suppress banners)
  log "Test 4c: --thinking flag forwarded..."
  E2E_THINKING_RESULT=$("$CLAWBOX" run --thinking minimal --quiet \
    "Say the word HELLO" 2>&1 || true)

  if type -f is_rate_limited &>/dev/null && is_rate_limited "$E2E_THINKING_RESULT"; then
    warn "API rate limited during thinking flag test"
    E2E_THINKING_RESULT="(rate limited)"
  else
    # The agent should respond normally even with thinking enabled
    if echo "$E2E_THINKING_RESULT" | grep -qi "hello"; then
      pass "--thinking minimal: agent responded normally with thinking enabled"
    else
      warn "--thinking minimal: unexpected response (got: ${E2E_THINKING_RESULT:0:200})"
    fi
  fi

  # 4d. --quiet suppresses banners (stderr), response only on stdout
  log "Test 4d: --quiet mode suppresses banners..."
  E2E_QUIET_STDOUT=$("$CLAWBOX" run --quiet "Say QUIETTEST in your response" 2>/dev/null || true)
  E2E_QUIET_STDERR=$("$CLAWBOX" run --quiet "Say QUIETTEST2 in your response" 2>&1 >/dev/null || true)

  if ! echo "$E2E_QUIET_STDOUT" | grep -qi "▶"; then
    pass "--quiet: stdout has no banners"
  else
    fail "--quiet: banners found on stdout (should be stderr only)"
  fi

  # 4e. --json mode produces valid JSON
  log "Test 4e: --json output mode..."
  E2E_JSON_OUTPUT=$("$CLAWBOX" run --json "Say the word JSON" 2>/dev/null || true)

  if type -f is_rate_limited &>/dev/null && is_rate_limited "$E2E_JSON_OUTPUT"; then
    warn "API rate limited during JSON mode test"
  elif echo "$E2E_JSON_OUTPUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'response' in d and 'elapsed_ms' in d" 2>/dev/null; then
    pass "--json: valid JSON output with response and elapsed_ms keys"
  else
    fail "--json: output is not valid JSON (got: ${E2E_JSON_OUTPUT:0:200})"
  fi
fi

# ── Cleanup ────────────────────────────────────────────────────────

rm -rf "$TMPDIR_CTX"

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

# ── Write results ──────────────────────────────────────────────────

cat > "$RESULT_FILE" << RESULT_EOF
# T8 — Context injection test
**Date:** $(date '+%Y-%m-%d %H:%M')
**Duration:** ${ELAPSED}s
**Container running:** $CONTAINER_RUNNING

## Summary

| Metric | Value |
|--------|-------|
| Pass | $PASS |
| Warn | $WARN |
| Fail | $FAIL |

## What was tested
- \`--context <file>\`: single-file injection, agent references injected code
- \`--context <dir>\`: directory injection, all files included, node_modules excluded
- \`--thinking <level>\`: flag forwarded, agent still responds normally
- \`--quiet\`: banners suppressed on stdout (sent to stderr)
- \`--json\`: valid JSON output with required keys
- Invalid path → clear error message
- Missing message → usage hint

## Live E2E — Single file context
\`\`\`
${E2E_SINGLE_RESULT:-skipped}
\`\`\`

## Live E2E — Directory context
\`\`\`
${E2E_DIR_RESULT:-skipped}
\`\`\`

## Live E2E — --thinking flag
\`\`\`
${E2E_THINKING_RESULT:-skipped}
\`\`\`

## Assessment
$([ $FAIL -eq 0 ] && echo "✓ All checks passed" || echo "✗ $FAIL check(s) failed")
$([ $WARN -gt 0 ] && echo "⚠ $WARN warning(s)" || echo "✓ No warnings")
RESULT_EOF

log "Results written to $RESULT_FILE"
log "Done. Pass=$PASS Warn=$WARN Fail=$FAIL"

[ $FAIL -eq 0 ] || exit 1
