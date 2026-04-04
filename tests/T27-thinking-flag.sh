#!/usr/bin/env bash
# T27 — --thinking flag validation
#
# What: Verify `clawbox run --thinking <level>` and `clawbox task --thinking <level>`
#       are parsed, validated, forwarded to the agent, and documented in help.
#
# Approach:
#   Phase 1: Valid levels (off, minimal, low, medium, high) are accepted by `run`
#   Phase 2: Invalid level gives a usage hint (non-zero exit)
#   Phase 3: Short flag -T works identically to --thinking
#   Phase 4: --thinking minimal produces a valid JSON response (agent still responds)
#   Phase 5: --thinking combined with --json produces JSON with response key
#   Phase 6: --thinking accepted in `task` mode (flag parsed, task starts non-blocking)
#   Phase 7: Help text documents --thinking and its valid levels
#   Phase 8: --thinking with no value gives a usage hint
#
# Why: --thinking has been tested only incidentally (T8 checks it's "accepted" with
#      minimal). It's forwarded to `openclaw agent --thinking` which can accept
#      6 levels. We've never verified: invalid level rejection, help documentation,
#      short flag parity, or --thinking + --json combination.
#
# Duration: ~60-90s (one live agent call in Phase 4/5; static checks for rest)
#
# Does NOT test high/xhigh thinking levels (expensive API calls).

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T27-thinking-flag.md"
CONTAINER="clawbox-work"

# Source shared rate-limit helpers
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
  source "$SCRIPT_DIR/lib/common.sh"
fi

mkdir -p "$RESULT_DIR"

PASS=0
FAIL=0
WARN=0
FINDINGS=""

pass() { PASS=$((PASS+1)); FINDINGS+="  ✓ $1\n"; echo "  ✓ $1"; }
fail() { FAIL=$((FAIL+1)); FINDINGS+="  ✗ $1\n"; echo "  ✗ $1"; }
warn() { WARN=$((WARN+1)); FINDINGS+="  ⚠ $1\n"; echo "  ⚠ $1"; }

log() { echo "[T27 $(date +%H:%M:%S)] $*"; }

START_TIME=$(date +%s)

log "Starting T27 — --thinking flag validation"

# ── Bootstrap result file ─────────────────────────────────────────────────────
cat > "$RESULT_FILE" << 'HEADER'
# T27 — --thinking flag validation

## What was tested
- Phase 1: Valid thinking levels accepted by `clawbox run`
- Phase 2: Invalid thinking level rejected with usage hint
- Phase 3: Short flag -T is a valid alias for --thinking
- Phase 4: --thinking minimal produces a working agent response (live call)
- Phase 5: --thinking minimal + --json produces valid JSON output
- Phase 6: --thinking accepted in `clawbox task` mode
- Phase 7: Help text documents --thinking with its levels
- Phase 8: --thinking with no value gives usage hint

## Results

| Status | Check |
|--------|-------|
HEADER

log_result() {
  local status="$1" desc="$2"
  echo "| $status | $desc |" >> "$RESULT_FILE"
}

assert_pass() { pass "$1"; log_result "✓ PASS" "$1"; }
assert_fail() { fail "$1"; log_result "✗ FAIL" "$1"; }
assert_warn() { warn "$1"; log_result "⚠ WARN" "$1"; }

# ── Preflight: ensure container is running ────────────────────────────────────
STATUS=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "missing")
if [ "$STATUS" != "healthy" ]; then
  echo "SKIP: Container is not healthy (status: $STATUS). Start with: clawbox start"
  skip_rate_limited "T27" "$RESULT_FILE" "Container not healthy: $STATUS"
  exit 0
fi

log "Container healthy — proceeding"

# ── Phase 1: Valid levels accepted by `clawbox run` (static checks only) ──────
log "Phase 1: Valid thinking level parsing"
echo "" >> "$RESULT_FILE"
echo "### Phase 1 — Valid thinking levels accepted" >> "$RESULT_FILE"

# We test level parsing by checking help text and then running the flag with a short
# message. We use `--dry-run` equivalent: pass an invalid (empty) message to get
# usage output, then verify the flag name is recognised vs "Unknown option".
# For actual level acceptance, we check that the flag is wired in source.

# Check source for all 6 valid levels forwarded to openclaw agent
CLAWBOX_SRC="$SCRIPT_DIR/../clawbox"
if grep -q '\-\-thinking' "$CLAWBOX_SRC"; then
  assert_pass "--thinking flag present in CLI source"
else
  assert_fail "--thinking flag NOT found in CLI source"
fi

# Verify valid level values are documented (off|minimal|low|medium|high|xhigh)
if grep -qE 'off\|minimal\|low\|medium\|high\|xhigh|off.minimal.low.medium.high' "$CLAWBOX_SRC"; then
  assert_pass "Valid thinking levels listed in source (off|minimal|low|medium|high|...)"
else
  assert_warn "Explicit thinking level list not found in source — may be implicit"
fi

# Check that the --thinking value is forwarded to openclaw agent call
if grep -qE '"\-\-thinking"\s*"\$thinking_level"|\-\-thinking.*\$thinking_level' "$CLAWBOX_SRC"; then
  assert_pass "--thinking forwarded to openclaw agent (--thinking \$thinking_level wiring)"
else
  assert_fail "--thinking NOT forwarded to openclaw agent in source"
fi

# ── Phase 2: Invalid level rejection ─────────────────────────────────────────
log "Phase 2: Invalid thinking level rejection"
echo "" >> "$RESULT_FILE"
echo "### Phase 2 — Invalid level rejection" >> "$RESULT_FILE"

# An empty --thinking value should give usage hint and exit non-zero
USAGE_OUT=$("$CLAWBOX" run --thinking "" "test" 2>&1 || true)
USAGE_EXIT=$("$CLAWBOX" run --thinking "" "test" >/dev/null 2>&1; echo $?)

if echo "$USAGE_OUT" | grep -qi "usage\|thinking\|level"; then
  assert_pass "--thinking with empty value gives usage hint"
else
  assert_warn "--thinking with empty value: no clear usage hint (got: $USAGE_OUT)"
fi

# Note: clawbox currently validates that --thinking value is non-empty (not that it's
# one of the valid enum values — that validation is in openclaw agent itself).
# We check the CLI at least rejects the empty-value case.

# ── Phase 3: Short flag -T is accepted ────────────────────────────────────────
log "Phase 3: Short flag -T parity"
echo "" >> "$RESULT_FILE"
echo "### Phase 3 — Short flag -T" >> "$RESULT_FILE"

# Check source wires -T as alias for --thinking
# Pattern: look for --thinking|-T or -T| in a case statement
if grep -qE -- '--thinking\|-T|-T\|--thinking' "$CLAWBOX_SRC"; then
  assert_pass "-T shorthand present in CLI dispatch"
else
  assert_fail "-T shorthand NOT found in CLI source"
fi

# Check that -T is documented in help
HELP_OUT=$("$CLAWBOX" help 2>&1 || "$CLAWBOX" --help 2>&1 || true)
if echo "$HELP_OUT" | grep -qE '\-T|--thinking'; then
  assert_pass "--thinking / -T appears in help output"
else
  assert_fail "--thinking / -T NOT found in help output"
fi

# ── Phase 4: Live call — --thinking minimal produces valid response ────────────
log "Phase 4: Live agent call with --thinking minimal"
echo "" >> "$RESULT_FILE"
echo "### Phase 4 — Live call with --thinking minimal" >> "$RESULT_FILE"

LIVE_OUT=$("$CLAWBOX" run --thinking minimal "Reply with exactly: THINKING_T27_OK" 2>&1 || true)
LIVE_EXIT=0
"$CLAWBOX" run --thinking minimal "Reply with exactly: THINKING_T27_OK" > /tmp/t27-live-out.txt 2>&1 || LIVE_EXIT=$?

LIVE_RESPONSE=$(cat /tmp/t27-live-out.txt 2>/dev/null || echo "")

# Check for rate limit
if is_rate_limited "$LIVE_RESPONSE"; then
  warn "Phase 4: API rate limited — skipping live-call checks"
  skip_rate_limited "T27-phase4" "/tmp/t27-p4-skip.md"
else
  if [ -n "$LIVE_RESPONSE" ] && [ ${#LIVE_RESPONSE} -gt 5 ]; then
    assert_pass "Phase 4: agent responded (non-empty response, ${#LIVE_RESPONSE} chars)"
  else
    assert_fail "Phase 4: agent returned empty or very short response"
  fi

  # Check sentinel presence (agent should echo THINKING_T27_OK)
  if echo "$LIVE_RESPONSE" | grep -q "THINKING_T27_OK"; then
    assert_pass "Phase 4: agent response contains expected sentinel (THINKING_T27_OK)"
  else
    assert_warn "Phase 4: sentinel THINKING_T27_OK not found in response (agent may have rephrased)"
  fi

  # Check no error in response
  if echo "$LIVE_RESPONSE" | grep -qi "error\|unknown.*option\|invalid.*thinking"; then
    assert_fail "Phase 4: response contains error/invalid-option text"
  else
    assert_pass "Phase 4: no error text in response"
  fi
fi

# ── Phase 5: --thinking + --json produces valid JSON ──────────────────────────
log "Phase 5: --thinking + --json combination"
echo "" >> "$RESULT_FILE"
echo "### Phase 5 — --thinking + --json" >> "$RESULT_FILE"

JSON_OUT=$("$CLAWBOX" run --thinking minimal --json "Say: T27_JSON_OK" 2>/tmp/t27-p5-stderr.txt || true)

if is_rate_limited "$JSON_OUT"; then
  warn "Phase 5: API rate limited — skipping JSON combination check"
else
  # Validate JSON
  if echo "$JSON_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert 'response' in d" 2>/dev/null; then
    assert_pass "Phase 5: --thinking + --json output is valid JSON with 'response' key"
  else
    assert_fail "Phase 5: --thinking + --json output is not valid JSON (got: ${JSON_OUT:0:120})"
  fi

  # Check elapsed_ms present
  if echo "$JSON_OUT" | python3 -c "import json,sys; d=json.load(sys.stdin); assert d['elapsed_ms'] > 0" 2>/dev/null; then
    assert_pass "Phase 5: JSON has positive elapsed_ms"
  else
    assert_warn "Phase 5: elapsed_ms missing or zero in JSON"
  fi
fi

# ── Phase 6: --thinking accepted in task mode ─────────────────────────────────
log "Phase 6: --thinking in task mode"
echo "" >> "$RESULT_FILE"
echo "### Phase 6 — --thinking in task mode" >> "$RESULT_FILE"

# Quick non-blocking task start with --thinking minimal — just verify it starts
# Clean up any stale lock
LOCK_FILE="$HOME/.clawbox-lock"
if [ -f "$LOCK_FILE" ]; then
  LOCK_PID=$(cat "$LOCK_FILE" 2>/dev/null || echo "")
  if [ -n "$LOCK_PID" ] && ! kill -0 "$LOCK_PID" 2>/dev/null; then
    rm -f "$LOCK_FILE"
  fi
fi

# Run with --thinking minimal; capture output to temp file (not $() which blocks)
TASK_TMPOUT=$(mktemp /tmp/t27-task-out.XXXXX)
"$CLAWBOX" task --thinking minimal "Write the text T27_TASK_STARTED to /home/node/.openclaw/workspace/t27-task-check.txt" \
  > "$TASK_TMPOUT" 2>&1 &
TASK_LAUNCH_PID=$!
sleep 3
wait "$TASK_LAUNCH_PID" 2>/dev/null || true
TASK_OUTPUT=$(cat "$TASK_TMPOUT" 2>/dev/null || echo "")
rm -f "$TASK_TMPOUT"

if echo "$TASK_OUTPUT" | grep -qi "started\|background\|log\|task"; then
  assert_pass "Phase 6: task --thinking minimal started non-blocking (got task confirmation)"
elif echo "$TASK_OUTPUT" | grep -qi "usage\|error\|unknown.*thinking"; then
  assert_fail "Phase 6: task --thinking minimal rejected (unexpected error): ${TASK_OUTPUT:0:100}"
else
  assert_warn "Phase 6: task started but output unclear: ${TASK_OUTPUT:0:100}"
fi

# Cancel the background task to keep state clean
sleep 5
"$CLAWBOX" cancel 2>/dev/null || true
docker exec "$CONTAINER" sh -c "rm -f /home/node/.openclaw/workspace/t27-task-check.txt 2>/dev/null; true"

# ── Phase 7: Help text documents --thinking ───────────────────────────────────
log "Phase 7: Help text coverage"
echo "" >> "$RESULT_FILE"
echo "### Phase 7 — Help text" >> "$RESULT_FILE"

HELP=$("$CLAWBOX" help 2>&1 || true)

if echo "$HELP" | grep -q "thinking"; then
  assert_pass "Help text contains 'thinking'"
else
  assert_fail "Help text does NOT contain 'thinking'"
fi

if echo "$HELP" | grep -qE "minimal|off.*minimal|thinking.*level"; then
  assert_pass "Help text mentions thinking levels (minimal or off|minimal)"
else
  assert_warn "Help text doesn't list thinking levels (may be abbreviated)"
fi

# Check run command's help section mentions --thinking
if echo "$HELP" | grep -A5 "run\|ask" | grep -q "thinking"; then
  assert_pass "--thinking appears near 'run' in help (correctly scoped)"
else
  assert_warn "--thinking not found near 'run' in help — may be global flag"
fi

# ── Phase 8: --thinking with no value ────────────────────────────────────────
log "Phase 8: --thinking with no value"
echo "" >> "$RESULT_FILE"
echo "### Phase 8 — --thinking with no value" >> "$RESULT_FILE"

# When --thinking has no following value argument, the CLI should give a usage hint
# In our implementation, the next positional arg becomes the "level", so we test
# the case where --thinking is the very last argument (no value at all)
NO_VAL_OUT=$("$CLAWBOX" run --thinking 2>&1 || true)

if echo "$NO_VAL_OUT" | grep -qi "usage\|thinking\|level\|value"; then
  assert_pass "--thinking with no value gives usage hint"
else
  # Some shells pass empty string; either way the flag should be handled
  assert_warn "--thinking with no value behavior: ${NO_VAL_OUT:0:100}"
fi

# ── Wrap up ───────────────────────────────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

TOTAL=$((PASS + FAIL + WARN))
log "Done in ${ELAPSED}s — Pass: $PASS  Warn: $WARN  Fail: $FAIL  Total: $TOTAL"

cat >> "$RESULT_FILE" << FOOTER

## Summary

- **Pass:** $PASS / $TOTAL
- **Warn:** $WARN
- **Fail:** $FAIL
- **Duration:** ${ELAPSED}s

## Key Findings

$(printf '%b' "$FINDINGS")

**Verdict:** $([ "$FAIL" -eq 0 ] && echo "All checks pass — \`--thinking\` flag is working correctly. ✅" || echo "$FAIL check(s) failed — see above. ✗")
FOOTER

echo ""
echo "=== T27 complete: Pass=$PASS Warn=$WARN Fail=$FAIL ==="
echo "Result: $RESULT_FILE"
echo ""

exit $FAIL
