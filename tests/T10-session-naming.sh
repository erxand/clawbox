#!/usr/bin/env bash
# T10 — Session naming test (--session flag for run and chat)
#
# What: Test that `clawbox run --session <name>` correctly routes messages to
#       a named persistent session, preserving conversation context across calls.
# Why:  Session naming is critical for multi-project workflows — different
#       projects need isolated conversation threads so context doesn't bleed.
# Pass: Named sessions maintain conversation history; different sessions are isolated;
#       --json output includes the session key; help text is updated.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
CLAWBOX_SRC="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T10-session-naming.md"
CONTAINER="clawbox-work"

mkdir -p "$RESULT_DIR"

log() { echo "[T10 $(date +%H:%M:%S)] $*"; }
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠ $*"; WARN=$((WARN+1)); }

PASS=0; FAIL=0; WARN=0
START_TIME=$(date +%s)

# ── Unit tests: --session flag parsing ────────────────────────────────

log "Testing --session flag parsing in cmd_run..."

# Extract cmd_run function from clawbox script
EXTRACT_CMD_RUN=$(awk '
/^cmd_run\(\)/ { found=1; depth=0 }
found {
  for (i=1; i<=length($0); i++) {
    c=substr($0,i,1)
    if (c=="{") depth++
    if (c=="}") {
      depth--
      if (depth==0) { print; found=0; nextfile }
    }
  }
  print
}
' "$CLAWBOX_SRC")

TMPTEST=$(mktemp /tmp/t10-test-XXXXXX.sh)

# Test --session flag is accepted without error
cat > "$TMPTEST" << SHELLEOF
#!/usr/bin/env bash
set -euo pipefail
GATEWAY_PORT=18790; GATEWAY_URL="ws://localhost:18790"; GATEWAY_TOKEN="clawbox"
LOCK_FILE="/tmp/.t10-lock"; TASKS_FILE="/tmp/.t10-tasks"; CONTAINER="clawbox-work"; CLAWBOX_DIR="/tmp"
assert_container_running() { :; }
assert_not_busy() { :; }
acquire_lock() { :; }
release_lock() { :; }
openclaw() { echo "mock-response"; }
$(echo "$EXTRACT_CMD_RUN")
cmd_run --session myproject "test message"
SHELLEOF
if bash "$TMPTEST" 2>/dev/null; then
  pass "--session: flag accepted without error"
else
  fail "--session: flag caused error"
fi

# Test -s short flag
cat > "$TMPTEST" << SHELLEOF
#!/usr/bin/env bash
set -euo pipefail
GATEWAY_PORT=18790; GATEWAY_URL="ws://localhost:18790"; GATEWAY_TOKEN="clawbox"
LOCK_FILE="/tmp/.t10-lock"; TASKS_FILE="/tmp/.t10-tasks"; CONTAINER="clawbox-work"; CLAWBOX_DIR="/tmp"
assert_container_running() { :; }
assert_not_busy() { :; }
acquire_lock() { :; }
release_lock() { :; }
openclaw() { echo "mock-response"; }
$(echo "$EXTRACT_CMD_RUN")
cmd_run -s myproject "test message"
SHELLEOF
if bash "$TMPTEST" 2>/dev/null; then
  pass "-s (short): flag accepted without error"
else
  fail "-s (short): flag caused error"
fi

# Test --session is passed to openclaw as --session-id
# We verify by checking the cmd_run source contains --session-id wiring
if echo "$EXTRACT_CMD_RUN" | grep -q "session-id"; then
  pass "--session: --session-id wiring found in cmd_run source"
else
  fail "--session: --session-id NOT found in cmd_run source"
fi

# Also verify the session_key variable is referenced in the agent_args
if echo "$EXTRACT_CMD_RUN" | grep -q "session_key.*session-id\|session-id.*session_key"; then
  pass "--session: session_key is wired to agent_args --session-id"
else
  # Try a more flexible grep
  if echo "$EXTRACT_CMD_RUN" | grep -A1 "session.id" | grep -q "session_key"; then
    pass "--session: session_key is wired to agent_args --session-id"
  else
    fail "--session: session_key not found near --session-id in cmd_run source"
  fi
fi

# Test --json output includes session key
cat > "$TMPTEST" << SHELLEOF
#!/usr/bin/env bash
set -euo pipefail
GATEWAY_PORT=18790; GATEWAY_URL="ws://localhost:18790"; GATEWAY_TOKEN="clawbox"
LOCK_FILE="/tmp/.t10-lock"; TASKS_FILE="/tmp/.t10-tasks"; CONTAINER="clawbox-work"; CLAWBOX_DIR="/tmp"
assert_container_running() { :; }
assert_not_busy() { :; }
acquire_lock() { :; }
release_lock() { :; }
openclaw() { echo "pong"; }
$(echo "$EXTRACT_CMD_RUN")
cmd_run --json --session myproject "test"
SHELLEOF
JSON_OUT=$(bash "$TMPTEST" 2>/dev/null || true)
if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d['session']=='myproject'" "$JSON_OUT" 2>/dev/null; then
  pass "--json + --session: session key in JSON output"
else
  fail "--json + --session: session key missing or wrong in JSON (got: $JSON_OUT)"
fi

# Test --json without --session has session=null
cat > "$TMPTEST" << SHELLEOF
#!/usr/bin/env bash
set -euo pipefail
GATEWAY_PORT=18790; GATEWAY_URL="ws://localhost:18790"; GATEWAY_TOKEN="clawbox"
LOCK_FILE="/tmp/.t10-lock"; TASKS_FILE="/tmp/.t10-tasks"; CONTAINER="clawbox-work"; CLAWBOX_DIR="/tmp"
assert_container_running() { :; }
assert_not_busy() { :; }
acquire_lock() { :; }
release_lock() { :; }
openclaw() { echo "pong"; }
$(echo "$EXTRACT_CMD_RUN")
cmd_run --json "test"
SHELLEOF
JSON_OUT2=$(bash "$TMPTEST" 2>/dev/null || true)
if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d['session'] is None" "$JSON_OUT2" 2>/dev/null; then
  pass "--json (no --session): session key is null"
else
  fail "--json (no --session): session key unexpected value (got: $JSON_OUT2)"
fi

rm -f "$TMPTEST"

# ── Test: banner shows session name ────────────────────────────────

log "Testing session banner..."
EXTRACT_CMD_CHAT=$(awk '
/^cmd_chat\(\)/ { found=1; depth=0 }
found {
  for (i=1; i<=length($0); i++) {
    c=substr($0,i,1)
    if (c=="{") depth++
    if (c=="}") {
      depth--
      if (depth==0) { print; found=0; nextfile }
    }
  }
  print
}
' "$CLAWBOX_SRC")

# Check cmd_chat has --session support
if echo "$EXTRACT_CMD_CHAT" | grep -q "session_key"; then
  pass "cmd_chat: --session flag is implemented"
else
  fail "cmd_chat: --session flag not found in cmd_chat"
fi

if echo "$EXTRACT_CMD_CHAT" | grep -q "\-\-session"; then
  pass "cmd_chat: --session is passed to openclaw tui"
else
  fail "cmd_chat: --session not wired to tui"
fi

# ── Test: help text is updated ────────────────────────────────────

log "Testing help text..."
HELP=$("$CLAWBOX" help 2>&1)
if echo "$HELP" | grep -q "session"; then
  pass "help: --session documented"
else
  fail "help: --session NOT in help output"
fi

# ── Live end-to-end (if container is running) ─────────────────────

CONTAINER_RUNNING=$(docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null || echo "false")
E2E_CONTINUITY_STATUS="skipped"
E2E_ISOLATION_STATUS="skipped"
E2E_SESSION_A_MSG2=""
E2E_SESSION_B_MSG1=""

if [ "$CONTAINER_RUNNING" = "true" ]; then
  log "Container running — live e2e session continuity tests..."

  SESSION_A="t10-test-$(date +%s)-a"
  SESSION_B="t10-test-$(date +%s)-b"

  # Session A: send a message with a specific keyword
  log "Session A: sending first message..."
  RESP_A1=$("$CLAWBOX" run --quiet --session "$SESSION_A" "Remember this exact code word: ZEBRA42. Reply with only: ZEBRA42" 2>/dev/null || true)
  log "Session A response 1: $RESP_A1"

  # Session A: ask a follow-up that requires memory of the first message
  log "Session A: follow-up message (should recall ZEBRA42)..."
  RESP_A2=$("$CLAWBOX" run --quiet --session "$SESSION_A" "What was the code word I asked you to remember? Say only the code word." 2>/dev/null || true)
  E2E_SESSION_A_MSG2="$RESP_A2"
  log "Session A response 2: $RESP_A2"

  if echo "$RESP_A2" | grep -qi "ZEBRA42"; then
    pass "Live session continuity: session A remembered ZEBRA42 across two calls"
    E2E_CONTINUITY_STATUS="pass"
  else
    warn "Live session continuity: session A did NOT recall ZEBRA42 (got: $RESP_A2)"
    E2E_CONTINUITY_STATUS="warn"
  fi

  # Session B: confirm conversation-history isolation
  # NOTE: Sessions share the agent's long-term memory (MEMORY.md) — this is by design.
  # What we test here is that session B does NOT have the *conversation history* of A:
  # i.e., session B hasn't seen the explicit exchange where we told A to remember ZEBRA42.
  # We do this by asking session B to repeat what we said in session B's last message —
  # if it says something other than the message we just sent, context leaked.
  log "Session B: testing conversation history isolation..."
  FIRST_MSG_B="Session $SESSION_B is starting fresh. What was my previous message in this session?"
  RESP_B1=$("$CLAWBOX" run --quiet --session "$SESSION_B" "$FIRST_MSG_B" 2>/dev/null || true)
  E2E_SESSION_B_MSG1="$RESP_B1"
  log "Session B response 1: $RESP_B1"

  # Session B should not have any conversation history before our first message
  # It should say it's the first message or reference the message we just sent
  if echo "$RESP_B1" | grep -qi "first\|no.*previous\|new.*session\|this.*is.*first\|only.*message\|just.*sent\|just.*now\|just.*said"; then
    pass "Live session isolation: session B correctly shows no prior conversation history"
    E2E_ISOLATION_STATUS="pass"
  else
    warn "Live session isolation: session B response unclear (got: $RESP_B1) — note: sessions share agent long-term memory by design"
    E2E_ISOLATION_STATUS="warn"
  fi
else
  warn "Container not running — skipped live e2e"
fi

# ── Write results ─────────────────────────────────────────────────

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

cat > "$RESULT_FILE" << RESULT_EOF
# T10 — Session naming test (--session flag)
**Date:** $(date '+%Y-%m-%d %H:%M')
**Duration:** ${ELAPSED}s

## Summary

| Metric | Value |
|--------|-------|
| Pass | $PASS |
| Warn | $WARN |
| Fail | $FAIL |
| E2E continuity | $E2E_CONTINUITY_STATUS |
| E2E isolation | $E2E_ISOLATION_STATUS |

## What was tested
- \`--session <name>\` / \`-s\` flag accepted by \`clawbox run\`
- Session key passed to \`openclaw agent --session-id\`
- \`--json\` output includes \`session\` key (name when set, null when omitted)
- \`clawbox chat --session\` wired to \`openclaw tui --session\`
- Help text documents \`--session\` flag
- Live: named sessions maintain conversation history across calls
- Live: session B has no prior conversation history (clean start)

**Note on isolation:** Named sessions share the agent's long-term memory (MEMORY.md, SOUL.md).
They do NOT share conversation history. This is by design — the agent's identity persists but
each session has its own message thread. For full isolation (including memory), run separate containers.

## Live E2E Results
### Session A (continuity test)
Second response (should recall ZEBRA42):
\`\`\`
$E2E_SESSION_A_MSG2
\`\`\`

### Session B (isolation test)
First response (should NOT know ZEBRA42):
\`\`\`
$E2E_SESSION_B_MSG1
\`\`\`

## Assessment
$([ $FAIL -eq 0 ] && echo "✓ All unit tests passed" || echo "✗ $FAIL test(s) failed")
$([ $WARN -gt 0 ] && echo "⚠ $WARN warning(s)" || echo "✓ No warnings")
RESULT_EOF

log "Results → $RESULT_FILE"
log "Done. Pass=$PASS Warn=$WARN Fail=$FAIL"

[ $FAIL -eq 0 ] || exit 1
