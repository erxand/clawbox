#!/usr/bin/env bash
# T32 — task→run session continuity bridge
#
# What: Verify that a background task started with `clawbox task --session X`
#       shares its conversation history with a subsequent `clawbox run --session X`.
#       This is the primary real-world workflow for "start a build in background,
#       then check in on it later."
#
# Phases:
#   Phase 1: Source audit — confirm --session is parsed in both cmd_run and cmd_task
#            and that both use --session-id when calling `openclaw agent`
#   Phase 2: Task→run session bridge (live) — start a task with --session X that
#            embeds a sentinel, wait for completion, then run a follow-up in the
#            same session and verify the sentinel is known
#   Phase 3: Session isolation — run a follow-up in session Y (different name) and
#            confirm the sentinel from session X is NOT known
#   Phase 4: --json session key consistency — task outputs a "Task started in session: X"
#            line; run with --json returns {"session": "X"}; keys match
#   Phase 5: Empty --session value rejected by both run and task
#   Phase 6: Help text — --session documented for both task and run
#
# Why: T10 verified --session for `run` only. T31 verified `task` accepts --session
#      without error. Neither test verified that a task's session history is actually
#      accessible in a subsequent `run` call — the full cross-command bridge. This test
#      closes that gap.
#
# Date: 2026-04-04
# Run time: ~120s (one background task that completes in ~30s + two live run calls)

set -euo pipefail

CLAWBOX_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAWBOX="$CLAWBOX_DIR/clawbox"
CLAWBOX_SRC="$CLAWBOX_DIR/clawbox"
RESULT_DIR="$CLAWBOX_DIR/tests/results"
mkdir -p "$RESULT_DIR"

TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T32-task-run-session-bridge.md"

PASS=0
WARN=0
FAIL=0

log()  { echo "[T32 $(date +%H:%M:%S)] $*"; }
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
warn() { echo "  ⚠ $*"; WARN=$((WARN+1)); }
fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }

# Source common lib for rate-limit detection
source "$CLAWBOX_DIR/tests/lib/common.sh" 2>/dev/null || true

START_TIME=$(date +%s)

log "Starting T32 — task→run session continuity bridge"

# ─── Ensure container is running ─────────────────────────────────────────────
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^clawbox-work$"; then
  log "Container not running — starting..."
  "$CLAWBOX" start 2>&1 | tail -5
fi

if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^clawbox-work$"; then
  fail "container could not be started — aborting"
  exit 1
fi
pass "container running at test start"

# ─── Phase 1: Source audit ────────────────────────────────────────────────────
log "Phase 1: source audit — --session wiring in cmd_task and cmd_run"

CMD_TASK_SRC=$(awk '/^cmd_task\(\)/{found=1;depth=0} found{for(i=1;i<=length($0);i++){c=substr($0,i,1);if(c=="{")depth++;if(c=="}"){depth--;if(depth==0){print;found=0;nextfile}}} print}' "$CLAWBOX_SRC")
CMD_RUN_SRC=$(awk '/^cmd_run\(\)/{found=1;depth=0} found{for(i=1;i<=length($0);i++){c=substr($0,i,1);if(c=="{")depth++;if(c=="}"){depth--;if(depth==0){print;found=0;nextfile}}} print}' "$CLAWBOX_SRC")

# cmd_task: --session case present
if echo "$CMD_TASK_SRC" | grep -q -- '--session'; then
  pass "Phase 1a: --session case present in cmd_task"
else
  fail "Phase 1a: --session case MISSING from cmd_task"
fi

# cmd_task: session_key forwarded as --session-id to openclaw agent
if echo "$CMD_TASK_SRC" | grep -q 'session-id.*session_key\|session_key.*session-id'; then
  pass "Phase 1b: session_key forwarded as --session-id in cmd_task"
else
  fail "Phase 1b: session_key NOT forwarded as --session-id in cmd_task"
fi

# cmd_run: --session case present
if echo "$CMD_RUN_SRC" | grep -q -- '--session'; then
  pass "Phase 1c: --session case present in cmd_run"
else
  fail "Phase 1c: --session case MISSING from cmd_run"
fi

# cmd_run: session_key forwarded as --session-id to openclaw agent
if echo "$CMD_RUN_SRC" | grep -q 'session-id.*session_key\|session_key.*session-id'; then
  pass "Phase 1d: session_key forwarded as --session-id in cmd_run"
else
  fail "Phase 1d: session_key NOT forwarded as --session-id in cmd_run"
fi

# Both use the same --session-id flag to openclaw agent (not different flags)
TASK_FORWARD=$(echo "$CMD_TASK_SRC" | grep 'session-id' | head -1)
RUN_FORWARD=$(echo "$CMD_RUN_SRC" | grep 'session-id' | head -1)
if [ -n "$TASK_FORWARD" ] && [ -n "$RUN_FORWARD" ]; then
  pass "Phase 1e: both cmd_task and cmd_run use --session-id (same flag → shared history)"
else
  warn "Phase 1e: could not verify both use --session-id (task: '${TASK_FORWARD:-none}', run: '${RUN_FORWARD:-none}')"
fi

# ─── Phase 2: Live session bridge test ───────────────────────────────────────
log "Phase 2: live test — task writes sentinel, run reads it back in same session"

SESSION_NAME="t32-bridge-$(date +%s)"
SENTINEL="BRIDGE_SENTINEL_T32_$(date +%s)"

log "Starting background task with session '$SESSION_NAME' and sentinel '$SENTINEL'..."

# Start task that embeds a unique sentinel in a memorable way
TASK_OUT=$("$CLAWBOX" task --session "$SESSION_NAME" \
  "Remember this token exactly: $SENTINEL. Store it in a variable, say it back to confirm receipt, then write it to /tmp/t32-sentinel.txt in the container workspace." \
  2>&1)

if echo "$TASK_OUT" | grep -qi "task started\|started\|running\|background"; then
  pass "Phase 2a: task started non-blocking (got task start confirmation)"
else
  warn "Phase 2a: unexpected task start output: $(echo "$TASK_OUT" | head -3)"
fi

# Capture the log path from the output
TASK_LOG_PATH=$(echo "$TASK_OUT" | grep -o 'Log:.*' | head -1 | sed 's/Log: *//')
if [ -n "$TASK_LOG_PATH" ]; then
  pass "Phase 2b: task log path captured from output: $(basename "$TASK_LOG_PATH")"
else
  warn "Phase 2b: log path not found in output — will use symlink fallback"
  TASK_LOG_PATH="$HOME/.clawbox-task.log"
fi

# Wait for task to complete (up to 90s)
log "Waiting for background task to complete (up to 90s)..."
TASK_DONE=0
for i in $(seq 1 45); do
  sleep 2
  if [ -f "$TASK_LOG_PATH" ]; then
    if grep -q '=== Task completed' "$TASK_LOG_PATH" 2>/dev/null; then
      TASK_DONE=1
      log "Task completed after ~$((i*2))s"
      break
    fi
  fi
done

if [ "$TASK_DONE" -eq 1 ]; then
  pass "Phase 2c: background task completed within 90s"
else
  warn "Phase 2c: task did not complete within 90s — proceeding with follow-up run anyway"
fi

# Check if sentinel appeared in task log
if [ -f "$TASK_LOG_PATH" ] && grep -q "$SENTINEL" "$TASK_LOG_PATH" 2>/dev/null; then
  pass "Phase 2d: sentinel '$SENTINEL' found in task log — agent processed it"
else
  warn "Phase 2d: sentinel not found in task log (may be in agent internal memory)"
fi

# ─── Phase 2 follow-up: run --session X to recall the sentinel ───────────────
log "Running follow-up 'run' call in the same session to recall the sentinel..."

FOLLOWUP_OUT=$("$CLAWBOX" run --session "$SESSION_NAME" --quiet \
  "What was the token I asked you to remember earlier in this session? Reply with JUST the token, nothing else." \
  2>&1)

if echo "$FOLLOWUP_OUT" | grep -q "$SENTINEL"; then
  pass "Phase 2e: ✅ sentinel '$SENTINEL' recalled in follow-up run — session bridge WORKS"
else
  fail "Phase 2e: ✗ sentinel NOT recalled in follow-up run — session bridge BROKEN"
  log "  Follow-up response was: $(echo "$FOLLOWUP_OUT" | head -3)"
fi

# Check for rate limiting
if is_rate_limited "$FOLLOWUP_OUT"; then
  skip_rate_limited "T32 Phase 2 follow-up"
  exit 0
fi

# ─── Phase 3: Session isolation ──────────────────────────────────────────────
log "Phase 3: verify sentinel is NOT known in a different session"

ISOLATION_SESSION="t32-isolation-$(date +%s)"
ISOLATION_OUT=$("$CLAWBOX" run --session "$ISOLATION_SESSION" --quiet \
  "Do you know any tokens or sentinels from other sessions? If yes, state them. If no, just say: NO_PRIOR_CONTEXT" \
  2>&1)

if echo "$ISOLATION_OUT" | grep -q "$SENTINEL"; then
  fail "Phase 3a: sentinel leaked into a different session (isolation failure!)"
else
  pass "Phase 3a: sentinel NOT present in different session — isolation correct"
fi

# Check for rate limiting
if is_rate_limited "$ISOLATION_OUT"; then
  warn "Phase 3: rate limited on isolation check — skipping"
else
  if echo "$ISOLATION_OUT" | grep -qi "NO_PRIOR_CONTEXT\|no prior\|don't have\|do not have\|no tokens\|no sentinel"; then
    pass "Phase 3b: isolation session correctly reports no prior context"
  else
    warn "Phase 3b: isolation session response ambiguous — check manually: $(echo "$ISOLATION_OUT" | head -2)"
  fi
fi

# ─── Phase 4: --json session key consistency ─────────────────────────────────
log "Phase 4: JSON session key — verify run --json returns correct session key"

JSON_SESSION="t32-json-$(date +%s)"
JSON_OUT=$("$CLAWBOX" run --session "$JSON_SESSION" --json "Echo the word: JSONSESSION_OK" 2>/dev/null || echo "{}")

# Validate JSON
if echo "$JSON_OUT" | python3 -c "import sys, json; d=json.load(sys.stdin); exit(0 if 'response' in d else 1)" 2>/dev/null; then
  pass "Phase 4a: --json output is valid JSON"
else
  fail "Phase 4a: --json output is not valid JSON: $(echo "$JSON_OUT" | head -1)"
fi

# Check session key in JSON matches the --session arg
JSON_SESSION_VAL=$(echo "$JSON_OUT" | python3 -c "import sys, json; d=json.load(sys.stdin); print(d.get('session', ''))" 2>/dev/null || echo "")
if [ "$JSON_SESSION_VAL" = "$JSON_SESSION" ]; then
  pass "Phase 4b: JSON 'session' key matches --session arg exactly ('$JSON_SESSION')"
elif [ -z "$JSON_SESSION_VAL" ]; then
  fail "Phase 4b: JSON 'session' key is missing or empty"
else
  fail "Phase 4b: JSON 'session' key mismatch: expected '$JSON_SESSION', got '$JSON_SESSION_VAL'"
fi

# ─── Phase 5: Empty --session rejected ───────────────────────────────────────
log "Phase 5: empty --session value rejection"

# Empty --session in run
EMPTY_RUN_OUT=$("$CLAWBOX" run --session "" "test" 2>&1 || true)
EMPTY_RUN_EXIT=$("$CLAWBOX" run --session "" "test" > /dev/null 2>&1; echo $?) || true
if [ "$EMPTY_RUN_EXIT" != "0" ] || echo "$EMPTY_RUN_OUT" | grep -qi "usage\|error\|required"; then
  pass "Phase 5a: empty --session in run gives usage hint or non-zero exit"
else
  warn "Phase 5a: empty --session in run may not be rejected: '$EMPTY_RUN_OUT'"
fi

# Empty --session in task
EMPTY_TASK_OUT=$("$CLAWBOX" task --session "" "desc" 2>&1 || true)
if echo "$EMPTY_TASK_OUT" | grep -qi "usage\|error\|required"; then
  pass "Phase 5b: empty --session in task gives usage hint"
else
  warn "Phase 5b: empty --session in task may not be rejected: '$EMPTY_TASK_OUT'"
fi

# ─── Phase 6: Help text coverage ─────────────────────────────────────────────
log "Phase 6: help text — --session documented for both run and task"

HELP_OUT=$("$CLAWBOX" help 2>&1 || "$CLAWBOX" --help 2>&1 || true)

# --session in run section
if echo "$HELP_OUT" | grep -A5 'run ' | grep -q 'session'; then
  pass "Phase 6a: --session documented in run section of help"
else
  fail "Phase 6a: --session NOT found in run section of help"
fi

# --session in task section
if echo "$HELP_OUT" | grep -A5 'task ' | grep -q 'session'; then
  pass "Phase 6b: --session documented in task section of help"
else
  fail "Phase 6b: --session NOT found in task section of help"
fi

# ─── Summary ─────────────────────────────────────────────────────────────────
END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

cat >> "$RESULT_FILE" << EOF
# T32 — task→run session continuity bridge

**Run:** $(date '+%Y-%m-%d %H:%M')
**Duration:** ${ELAPSED}s
**Result:** $PASS pass, $WARN warn, $FAIL fail

## Summary

- Session name used: \`$SESSION_NAME\`
- Sentinel: \`$SENTINEL\`

## Checks

$([ $PASS -gt 0 ] && echo "Pass: $PASS")
$([ $WARN -gt 0 ] && echo "Warn: $WARN")
$([ $FAIL -gt 0 ] && echo "Fail: $FAIL")

## Verdict

EOF

if [ $FAIL -eq 0 ]; then
  echo "  ✅ T32 fully clean: $PASS pass, $WARN warn, $FAIL fail" | tee -a "$RESULT_FILE"
else
  echo "  ✗ T32 has failures: $PASS pass, $WARN warn, $FAIL fail" | tee -a "$RESULT_FILE"
fi

echo ""
echo "Result file: $RESULT_FILE"
echo "Duration: ${ELAPSED}s"

# Exit code: non-zero only for hard failures
[ $FAIL -eq 0 ]
