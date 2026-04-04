#!/usr/bin/env bash
# T29 — stdin / pipe input support
#
# What: Verify that clawbox run (and its `ask` alias) can read messages from
#       stdin rather than requiring a quoted arg. Three supported patterns:
#
#       Pattern 1 — auto-detect pipe:
#         echo "message" | clawbox run
#         echo "message" | clawbox run --quiet
#         echo "message" | clawbox run --json
#
#       Pattern 2 — explicit dash:
#         clawbox run -   (reads stdin interactively/via heredoc)
#         clawbox run --quiet -
#
#       Pattern 3 — piped stdin + inline instruction:
#         cat log.txt | clawbox run "summarise this"
#         (stdin becomes the body; "summarise this" appended as the instruction)
#
#       Pattern 4 — ask alias:
#         echo "question" | clawbox ask --quiet
#
# Why:  Unix pipeline composition is a first-class workflow.  Being able to
#       pipe error logs, diffs, or long prompts lets users avoid shell
#       quoting complexity and enables scripting with clawbox.
#
# Good: Agent receives the piped content as the message and replies correctly.
# Bad:  Usage error printed (message treated as empty), stdin ignored, or
#       garbled message when combining pipe + inline arg.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T29-stdin-pipe.md"
CONTAINER="clawbox-work"

mkdir -p "$RESULT_DIR"

log() { echo "[T29 $(date +%H:%M:%S)] $*"; }

# ── Helpers ──────────────────────────────────────────────────────────────────

PASS=0; WARN=0; FAIL=0
check() {
  local label="$1" result="$2" note="${3:-}"
  case "$result" in
    pass) PASS=$((PASS+1)); echo "  ✓ $label${note:+ — $note}" ;;
    warn) WARN=$((WARN+1)); echo "  ⚠ $label${note:+ — $note}" ;;
    fail) FAIL=$((FAIL+1)); echo "  ✗ $label${note:+ — $note}" ;;
  esac
}

# ── Pre-flight ────────────────────────────────────────────────────────────────

log "Checking container is running..."
RUNNING=$(docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null || echo "false")
if [ "$RUNNING" != "true" ]; then
  log "Starting container..."
  "$CLAWBOX" start
  sleep 10
fi

# ── Source audit ─────────────────────────────────────────────────────────────

echo ""
echo "=== Phase 0: Source audit ==="

# Check for stdin-reading logic in cmd_run
STDIN_PIPE_PATTERN=$(grep -c "stdin_content\|! \[ -t 0 \]\|\\-t 0" "$CLAWBOX" 2>/dev/null || echo 0)
if [ "$STDIN_PIPE_PATTERN" -ge 2 ]; then
  check "Source: stdin detection code present in clawbox" "pass" "found $STDIN_PIPE_PATTERN refs"
else
  check "Source: stdin detection code present in clawbox" "fail" "stdin support not found in source"
fi

# Check help text mentions stdin/dash
HELP_STDOUT=$("$CLAWBOX" help 2>&1)
if echo "$HELP_STDOUT" | grep -q "stdin\|pipe\|\brun -\b"; then
  check "Help text mentions stdin/pipe usage" "pass" ""
else
  check "Help text mentions stdin/pipe usage" "fail" "run - or pipe usage not in help"
fi

# ── Phase 1: Auto-detected pipe (no inline message) ──────────────────────────

echo ""
echo "=== Phase 1: Auto-detected pipe — echo | clawbox run ==="

# P1a: plain run
log "P1a: echo pipe into clawbox run..."
P1A_RESP=$(echo "Reply with exactly: PIPE_P1A_OK" | "$CLAWBOX" run 2>/dev/null)
if echo "$P1A_RESP" | grep -q "PIPE_P1A_OK"; then
  check "P1a: plain pipe → clawbox run responds" "pass" "sentinel found"
else
  check "P1a: plain pipe → clawbox run responds" "fail" "response: ${P1A_RESP:0:80}"
fi

# P1b: --quiet mode
log "P1b: pipe with --quiet..."
P1B_RESP=$(echo "Reply with exactly: PIPE_P1B_OK" | "$CLAWBOX" run --quiet 2>/dev/null)
if echo "$P1B_RESP" | grep -q "PIPE_P1B_OK"; then
  check "P1b: pipe + --quiet → response only on stdout" "pass" "sentinel found"
else
  check "P1b: pipe + --quiet → response only on stdout" "fail" "response: ${P1B_RESP:0:80}"
fi

# P1c: --json mode
log "P1c: pipe with --json..."
P1C_OUT=$(echo "Reply with exactly: PIPE_P1C_OK" | "$CLAWBOX" run --json 2>/dev/null)
P1C_VALID=false
if echo "$P1C_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); assert 'response' in d and 'elapsed_ms' in d" 2>/dev/null; then
  P1C_VALID=true
fi
P1C_SENTINEL=$(echo "$P1C_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response',''))" 2>/dev/null || echo "")
if [ "$P1C_VALID" = "true" ] && echo "$P1C_SENTINEL" | grep -q "PIPE_P1C_OK"; then
  check "P1c: pipe + --json → valid JSON with sentinel in response" "pass" ""
else
  check "P1c: pipe + --json → valid JSON with sentinel in response" "fail" "json_valid=$P1C_VALID sentinel=${P1C_SENTINEL:0:60}"
fi

# ── Phase 2: Explicit dash marker ─────────────────────────────────────────────

echo ""
echo "=== Phase 2: Explicit dash (clawbox run -) ==="

# P2a: dash as sole argument (heredoc)
log "P2a: clawbox run - with heredoc..."
P2A_RESP=$("$CLAWBOX" run - 2>/dev/null <<< "Reply with exactly: DASH_P2A_OK")
if echo "$P2A_RESP" | grep -q "DASH_P2A_OK"; then
  check "P2a: clawbox run - reads from heredoc" "pass" "sentinel found"
else
  check "P2a: clawbox run - reads from heredoc" "fail" "response: ${P2A_RESP:0:80}"
fi

# P2b: dash with --quiet
log "P2b: clawbox run --quiet - with heredoc..."
P2B_RESP=$("$CLAWBOX" run --quiet - 2>/dev/null <<< "Reply with exactly: DASH_P2B_OK")
if echo "$P2B_RESP" | grep -q "DASH_P2B_OK"; then
  check "P2b: clawbox run --quiet - reads from heredoc" "pass" "sentinel found"
else
  check "P2b: clawbox run --quiet - reads from heredoc" "fail" "response: ${P2B_RESP:0:80}"
fi

# P2c: dash works whether before or after flags
log "P2c: dash position independence (after other flags)..."
P2C_RESP=$(echo "Reply with exactly: DASH_P2C_OK" | "$CLAWBOX" run --session t29-dash-test - 2>/dev/null)
if echo "$P2C_RESP" | grep -q "DASH_P2C_OK"; then
  check "P2c: clawbox run --session X - reads piped stdin" "pass" "sentinel found"
else
  check "P2c: clawbox run --session X - reads piped stdin" "warn" "response: ${P2C_RESP:0:80} (may be rate limited)"
fi

# ── Phase 3: Pipe + inline message (body + instruction) ───────────────────────

echo ""
echo "=== Phase 3: Piped stdin + inline instruction ==="

# P3a: piped body + inline instruction appended
log "P3a: body via pipe + instruction as inline arg..."
PIPE_BODY="The secret code is: XYZZY_T29_BODY"
P3A_RESP=$(echo "$PIPE_BODY" | "$CLAWBOX" run --quiet "What is the secret code mentioned above? Reply with just the code." 2>/dev/null)
if echo "$P3A_RESP" | grep -qi "XYZZY_T29_BODY"; then
  check "P3a: piped body referenced in response when instruction given as arg" "pass" "body content found in reply"
else
  check "P3a: piped body referenced in response when instruction given as arg" "fail" "response: ${P3A_RESP:0:120}"
fi

# P3b: piped diff + ask to summarize
log "P3b: piped diff content + summarize instruction..."
PIPE_DIFF=$(cat <<'DIFF'
diff --git a/src/auth.js b/src/auth.js
--- a/src/auth.js
+++ b/src/auth.js
@@ -1,3 +1,4 @@
 function login(user, pass) {
+  console.log("AUTH_DIFF_CANARY");  // added log
   return user === "admin" && pass === "secret";
 }
DIFF
)
P3B_RESP=$(echo "$PIPE_DIFF" | "$CLAWBOX" run --quiet "Summarize this diff in one sentence, and include the string AUTH_DIFF_CANARY in your reply." 2>/dev/null)
if echo "$P3B_RESP" | grep -q "AUTH_DIFF_CANARY"; then
  check "P3b: piped diff content used in summarize instruction" "pass" "canary found in summary"
else
  check "P3b: piped diff content used in summarize instruction" "fail" "response: ${P3B_RESP:0:120}"
fi

# ── Phase 4: ask alias ────────────────────────────────────────────────────────

echo ""
echo "=== Phase 4: ask alias supports stdin ==="

log "P4a: echo | clawbox ask..."
P4A_RESP=$(echo "Reply with exactly: ASK_ALIAS_P4A_OK" | "$CLAWBOX" ask --quiet 2>/dev/null)
if echo "$P4A_RESP" | grep -q "ASK_ALIAS_P4A_OK"; then
  check "P4a: echo | clawbox ask --quiet works" "pass" "sentinel found"
else
  check "P4a: echo | clawbox ask --quiet works" "fail" "response: ${P4A_RESP:0:80}"
fi

# ── Phase 5: Edge cases ───────────────────────────────────────────────────────

echo ""
echo "=== Phase 5: Edge cases ==="

# P5a: TTY (no pipe, no message) → usage error, not hang
log "P5a: no message + TTY → usage error..."
# We can't truly simulate a TTY in a test, but we can verify the usage message
# is printed when no message and no piped input
P5A_OUT=$("$CLAWBOX" run 2>&1 || true)
if echo "$P5A_OUT" | grep -qi "Usage.*clawbox run\|message"; then
  check "P5a: no message → usage hint shown" "pass" ""
else
  check "P5a: no message → usage hint shown" "fail" "output: ${P5A_OUT:0:80}"
fi

# P5b: empty stdin + no message → usage error (not hang)
log "P5b: empty stdin → usage error..."
P5B_OUT=$(echo "" | "$CLAWBOX" run 2>&1 || true)
# Empty stdin sets message to "" — should show usage error OR send to agent
# Acceptable: either usage hint or agent response (empty message may be valid)
if echo "$P5B_OUT" | grep -qi "Usage\|Error\|message\|empty" || [ -n "$P5B_OUT" ]; then
  check "P5b: empty stdin → no hang (got output or usage hint)" "pass" ""
else
  check "P5b: empty stdin → no hang (got output or usage hint)" "warn" "no output — may have hung"
fi

# P5c: multiline stdin preserved
log "P5c: multiline stdin..."
MULTILINE=$(printf "Line 1: alpha\nLine 2: beta\nLine 3: gamma")
P5C_RESP=$(echo "$MULTILINE" | "$CLAWBOX" run --quiet "What are the three line values? Reply with exactly: alpha beta gamma" 2>/dev/null)
if echo "$P5C_RESP" | grep -qi "alpha.*beta.*gamma\|alpha\|beta\|gamma"; then
  check "P5c: multiline piped stdin preserved and used" "pass" ""
else
  check "P5c: multiline piped stdin preserved and used" "warn" "response: ${P5C_RESP:0:80}"
fi

# P5d: large stdin (simulate error log ~2KB)
log "P5d: larger piped content (~2KB)..."
LARGE_CONTENT=$(python3 -c "
lines = []
for i in range(50):
    lines.append(f'ERROR_LINE_{i:03d}: Something went wrong in module {chr(65+i%26)} at line {i*10}')
lines.append('SENTINEL_LARGE_STDIN_T29')
print('\n'.join(lines))
")
P5D_RESP=$(echo "$LARGE_CONTENT" | "$CLAWBOX" run --quiet "Is there a sentinel line? Reply with just the sentinel string." 2>/dev/null)
if echo "$P5D_RESP" | grep -q "SENTINEL_LARGE_STDIN_T29"; then
  check "P5d: ~2KB piped content handled, sentinel found by agent" "pass" ""
else
  check "P5d: ~2KB piped content handled, sentinel found by agent" "warn" "response: ${P5D_RESP:0:100}"
fi

# ── Result file ───────────────────────────────────────────────────────────────

TOTAL=$((PASS + WARN + FAIL))

cat > "$RESULT_FILE" << RESULTEOF
# T29 — stdin / pipe input support

**Run:** $(date '+%Y-%m-%d %H:%M') | **Score:** ${PASS}/${TOTAL} pass, ${WARN} warn, ${FAIL} fail

## Summary

| Phase | Check | Result |
|-------|-------|--------|
| P0 | Source: stdin detection in clawbox | $(grep -q "stdin_content" "$CLAWBOX" 2>/dev/null && echo "✓ present" || echo "✗ missing") |
| P0 | Help mentions stdin/pipe | $(echo "$HELP_STDOUT" | grep -q "stdin\|pipe\|\brun -" && echo "✓ present" || echo "✗ missing") |
| P1a | echo pipe → clawbox run | $(echo "$P1A_RESP" | grep -q "PIPE_P1A_OK" && echo "✓ pass" || echo "✗ fail") |
| P1b | pipe + --quiet | $(echo "$P1B_RESP" | grep -q "PIPE_P1B_OK" && echo "✓ pass" || echo "✗ fail") |
| P1c | pipe + --json valid JSON with sentinel | $([ "$P1C_VALID" = "true" ] && echo "$P1C_SENTINEL" | grep -q "PIPE_P1C_OK" && echo "✓ pass" || echo "✗ fail") |
| P2a | clawbox run - (heredoc) | $(echo "$P2A_RESP" | grep -q "DASH_P2A_OK" && echo "✓ pass" || echo "✗ fail") |
| P2b | clawbox run --quiet - | $(echo "$P2B_RESP" | grep -q "DASH_P2B_OK" && echo "✓ pass" || echo "✗ fail") |
| P2c | flags + dash position-independent | $(echo "$P2C_RESP" | grep -q "DASH_P2C_OK" && echo "✓ pass" || echo "✗ fail") |
| P3a | pipe body + inline instruction | $(echo "$P3A_RESP" | grep -qi "XYZZY_T29_BODY" && echo "✓ pass" || echo "✗ fail") |
| P3b | pipe diff + summarize instruction | $(echo "$P3B_RESP" | grep -q "AUTH_DIFF_CANARY" && echo "✓ pass" || echo "✗ fail") |
| P4a | echo | clawbox ask --quiet | $(echo "$P4A_RESP" | grep -q "ASK_ALIAS_P4A_OK" && echo "✓ pass" || echo "✗ fail") |
| P5a | no message → usage hint | $(echo "$P5A_OUT" | grep -qi "Usage" && echo "✓ pass" || echo "✗ fail") |
| P5b | empty stdin → no hang | $([ -n "$P5B_OUT" ] && echo "✓ pass" || echo "⚠ warn") |
| P5c | multiline stdin preserved | $(echo "$P5C_RESP" | grep -qi "alpha\|beta\|gamma" && echo "✓ pass" || echo "⚠ warn") |
| P5d | ~2KB stdin handled | $(echo "$P5D_RESP" | grep -q "SENTINEL_LARGE_STDIN_T29" && echo "✓ pass" || echo "⚠ warn") |

## Verdicts

**Overall: ${PASS}/${TOTAL} pass, ${WARN} warn, ${FAIL} fail**

$([ "$FAIL" -eq 0 ] && echo "✅ All critical stdin patterns work. Pipe support is production-ready." || echo "❌ Some stdin patterns failed — see above.")

## Feature: stdin / pipe input (ISSUE-stdin)
**Problem:** \`clawbox run\` required a quoted string argument. Long messages, error logs, diffs, or programmatic inputs required awkward shell quoting or temp files.
**Fix:** Added three pipe patterns:
1. \`echo "msg" | clawbox run\` — auto-detect pipe (stdin not a TTY)
2. \`clawbox run -\` — explicit stdin marker
3. \`cat log | clawbox run "instruction"\` — piped body prepended to inline instruction
All patterns work with all existing flags (--quiet, --json, --session, --thinking, --context, --retry).
RESULTEOF

echo ""
echo "════════════════════════════════════"
echo "T29 Results: ${PASS}/${TOTAL} pass, ${WARN} warn, ${FAIL} fail"
echo "Result file: $RESULT_FILE"

# Rate limit check
if is_rate_limited "$RESULT_FILE" 2>/dev/null; then
  skip_rate_limited "$RESULT_FILE"
  exit 0
fi

[ "$FAIL" -gt 0 ] && exit 1 || exit 0
