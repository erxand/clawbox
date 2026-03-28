#!/usr/bin/env bash
# T9 — Output modes test (--quiet, --json)
#
# What: Test that `clawbox run --quiet` suppresses banners and `--json` emits
#       valid JSON with the correct keys. Both should still return the agent's
#       response on stdout.
# Why:  Output modes enable scripting — pipelines, automation, CI checks.
# Pass: --quiet emits only the response; --json emits parseable JSON with all keys.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
CLAWBOX_SRC="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T9-output-modes.md"
CONTAINER="clawbox-work"

mkdir -p "$RESULT_DIR"

log() { echo "[T9 $(date +%H:%M:%S)] $*"; }
pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }
warn() { echo "  ⚠ $*"; WARN=$((WARN+1)); }

PASS=0; FAIL=0; WARN=0
START_TIME=$(date +%s)

# Extract cmd_run function from clawbox script using brace-depth tracking
# (works on macOS BSD tools without requiring GNU head -n -2)
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

# ── Unit tests: --quiet flag ───────────────────────────────────────

log "Testing --quiet flag parsing..."

# Use a temp file to avoid heredoc nesting issues
TMPTEST=$(mktemp /tmp/t9-test-XXXXXX.sh)
cat > "$TMPTEST" << SHELLEOF
#!/usr/bin/env bash
set -euo pipefail
GATEWAY_PORT=18790; GATEWAY_URL="ws://localhost:18790"; GATEWAY_TOKEN="clawbox"
LOCK_FILE="/tmp/.t9-lock"; TASKS_FILE="/tmp/.t9-tasks"; CONTAINER="clawbox-work"; CLAWBOX_DIR="/tmp"
assert_container_running() { :; }
assert_not_busy() { :; }
acquire_lock() { :; }
release_lock() { :; }
openclaw() { echo "AGENT_RESPONSE: hello from agent"; }
$(echo "$EXTRACT_CMD_RUN")
cmd_run --quiet "say hello"
SHELLEOF
QUIET_OUT=$(bash "$TMPTEST" 2>/dev/null || true)

if echo "$QUIET_OUT" | grep -q "AGENT_RESPONSE"; then
  pass "--quiet: agent response present on stdout"
else
  fail "--quiet: agent response NOT on stdout (got: $QUIET_OUT)"
fi
if echo "$QUIET_OUT" | grep -q "▶"; then
  fail "--quiet: banner leaked to stdout (should be stderr only)"
else
  pass "--quiet: no banner on stdout"
fi

# ── Unit test: --json output structure ─────────────────────────────

log "Testing --json flag..."

cat > "$TMPTEST" << SHELLEOF
#!/usr/bin/env bash
set -euo pipefail
GATEWAY_PORT=18790; GATEWAY_URL="ws://localhost:18790"; GATEWAY_TOKEN="clawbox"
LOCK_FILE="/tmp/.t9-lock"; TASKS_FILE="/tmp/.t9-tasks"; CONTAINER="clawbox-work"; CLAWBOX_DIR="/tmp"
assert_container_running() { :; }
assert_not_busy() { :; }
acquire_lock() { :; }
release_lock() { :; }
openclaw() { echo "Hello world"; }
$(echo "$EXTRACT_CMD_RUN")
cmd_run --json "say hello"
SHELLEOF
JSON_OUT=$(bash "$TMPTEST" 2>/dev/null || true)

if python3 -c "import json,sys; json.loads(sys.argv[1])" "$JSON_OUT" 2>/dev/null; then
  pass "--json: output is valid JSON"
else
  fail "--json: output is NOT valid JSON (got: $JSON_OUT)"
fi

for key in response elapsed_ms timestamp context_files; do
  if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert '$key' in d" "$JSON_OUT" 2>/dev/null; then
    pass "--json: key '$key' present"
  else
    fail "--json: key '$key' MISSING (json: $JSON_OUT)"
  fi
done

if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert isinstance(d['elapsed_ms'],int) and d['elapsed_ms']>=0" "$JSON_OUT" 2>/dev/null; then
  pass "--json: elapsed_ms is non-negative integer"
else
  fail "--json: elapsed_ms wrong type or negative"
fi

if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert 'T' in d['timestamp'] and 'Z' in d['timestamp']" "$JSON_OUT" 2>/dev/null; then
  pass "--json: timestamp is ISO-8601 format"
else
  fail "--json: timestamp malformed"
fi

if python3 -c "import json,sys; d=json.loads(sys.argv[1]); assert d['response']=='Hello world'" "$JSON_OUT" 2>/dev/null; then
  pass "--json: response field contains agent output"
else
  fail "--json: response field wrong (json: $JSON_OUT)"
fi

# ── Test: --json + --context tracks file count ─────────────────────

log "Testing --json + --context context_files count..."

TMPDIR=$(mktemp -d)
echo "const a = 1;" > "$TMPDIR/a.js"
echo "const b = 2;" > "$TMPDIR/b.js"

cat > "$TMPTEST" << SHELLEOF
#!/usr/bin/env bash
set -euo pipefail
GATEWAY_PORT=18790; GATEWAY_URL="ws://localhost:18790"; GATEWAY_TOKEN="clawbox"
LOCK_FILE="/tmp/.t9-lock"; TASKS_FILE="/tmp/.t9-tasks"; CONTAINER="clawbox-work"; CLAWBOX_DIR="/tmp"
assert_container_running() { :; }
assert_not_busy() { :; }
acquire_lock() { :; }
release_lock() { :; }
openclaw() { echo "ok"; }
$(echo "$EXTRACT_CMD_RUN")
cmd_run --json --context "$TMPDIR" "summarize"
SHELLEOF
JSON_CTX=$(bash "$TMPTEST" 2>/dev/null || true)
rm -rf "$TMPDIR"

CFCOUNT=$(python3 -c "import json,sys; d=json.loads(sys.argv[1]); print(d['context_files'])" "$JSON_CTX" 2>/dev/null || echo "-1")
if [ "$CFCOUNT" = "2" ]; then
  pass "--json + --context: context_files=2 (correct)"
else
  fail "--json + --context: expected context_files=2, got $CFCOUNT"
fi

# ── Test: short flags work too (-q and -j) ─────────────────────────

log "Testing short flag aliases..."

cat > "$TMPTEST" << SHELLEOF
#!/usr/bin/env bash
set -euo pipefail
GATEWAY_PORT=18790; GATEWAY_URL="ws://localhost:18790"; GATEWAY_TOKEN="clawbox"
LOCK_FILE="/tmp/.t9-lock"; TASKS_FILE="/tmp/.t9-tasks"; CONTAINER="clawbox-work"; CLAWBOX_DIR="/tmp"
assert_container_running() { :; }
assert_not_busy() { :; }
acquire_lock() { :; }
release_lock() { :; }
openclaw() { echo "pong"; }
$(echo "$EXTRACT_CMD_RUN")
cmd_run -j "say pong"
SHELLEOF
SHORT_J=$(bash "$TMPTEST" 2>/dev/null || true)
if python3 -c "import json,sys; json.loads(sys.argv[1])" "$SHORT_J" 2>/dev/null; then
  pass "-j (short): valid JSON output"
else
  fail "-j (short): not valid JSON (got: $SHORT_J)"
fi

cat > "$TMPTEST" << SHELLEOF
#!/usr/bin/env bash
set -euo pipefail
GATEWAY_PORT=18790; GATEWAY_URL="ws://localhost:18790"; GATEWAY_TOKEN="clawbox"
LOCK_FILE="/tmp/.t9-lock"; TASKS_FILE="/tmp/.t9-tasks"; CONTAINER="clawbox-work"; CLAWBOX_DIR="/tmp"
assert_container_running() { :; }
assert_not_busy() { :; }
acquire_lock() { :; }
release_lock() { :; }
openclaw() { echo "pong"; }
$(echo "$EXTRACT_CMD_RUN")
cmd_run -q "say pong"
SHELLEOF
SHORT_Q=$(bash "$TMPTEST" 2>/dev/null || true)
if echo "$SHORT_Q" | grep -q "pong"; then
  pass "-q (short): response on stdout"
else
  fail "-q (short): response not found (got: $SHORT_Q)"
fi

rm -f "$TMPTEST"

# ── Test: help documents new flags ────────────────────────────────

log "Testing help text..."
HELP=$("$CLAWBOX" help 2>&1)
if echo "$HELP" | grep -q "\-\-quiet"; then
  pass "help: --quiet documented"
else
  fail "help: --quiet NOT in help output"
fi
if echo "$HELP" | grep -q "\-\-json"; then
  pass "help: --json documented"
else
  fail "help: --json NOT in help output"
fi

# ── Live end-to-end (if container is running) ──────────────────────

CONTAINER_RUNNING=$(docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null || echo "false")
E2E_QUIET_STATUS="skipped"
E2E_JSON_STATUS="skipped"
E2E_QUIET_OUT=""
E2E_JSON_OUT=""

if [ "$CONTAINER_RUNNING" = "true" ]; then
  log "Container running — live e2e tests..."

  # --quiet: banners to stderr, only response on stdout
  E2E_QUIET_STDOUT=$("$CLAWBOX" run --quiet "Reply with exactly one word: pong" 2>/dev/null || true)
  if echo "$E2E_QUIET_STDOUT" | grep -qi "pong"; then
    pass "Live --quiet: response on stdout"
    E2E_QUIET_STATUS="pass"
  else
    warn "Live --quiet: response unclear (got: $E2E_QUIET_STDOUT)"
    E2E_QUIET_STATUS="warn"
  fi
  if echo "$E2E_QUIET_STDOUT" | grep -q "▶"; then
    fail "Live --quiet: banner leaked to stdout"
    E2E_QUIET_STATUS="fail"
  else
    pass "Live --quiet: no banner on stdout"
  fi
  E2E_QUIET_OUT="$E2E_QUIET_STDOUT"

  # --json: valid JSON on stdout
  E2E_JSON_RAW=$("$CLAWBOX" run --json "Reply with exactly one word: pong" 2>/dev/null || true)
  if python3 -c "import json,sys; json.loads(sys.argv[1])" "$E2E_JSON_RAW" 2>/dev/null; then
    pass "Live --json: valid JSON on stdout"
    E2E_JSON_STATUS="pass"
  else
    warn "Live --json: not valid JSON (got: $E2E_JSON_RAW)"
    E2E_JSON_STATUS="warn"
  fi
  E2E_JSON_OUT="$E2E_JSON_RAW"
else
  warn "Container not running — skipped live e2e"
fi

# ── Write results ──────────────────────────────────────────────────

END_TIME=$(date +%s)
ELAPSED=$((END_TIME - START_TIME))

cat > "$RESULT_FILE" << RESULT_EOF
# T9 — Output modes test (--quiet, --json)
**Date:** $(date '+%Y-%m-%d %H:%M')
**Duration:** ${ELAPSED}s

## Summary

| Metric | Value |
|--------|-------|
| Pass | $PASS |
| Warn | $WARN |
| Fail | $FAIL |
| E2E --quiet | $E2E_QUIET_STATUS |
| E2E --json | $E2E_JSON_STATUS |

## What was tested
- \`--quiet\` / \`-q\` flag: response on stdout, banners to stderr only
- \`--json\` / \`-j\` flag: valid JSON with keys response/elapsed_ms/timestamp/context_files
- \`--json + --context\`: context_files count is accurate
- Short flag aliases (-q, -j) work the same as long forms
- Help text documents both new flags

## Live E2E Results
### --quiet stdout
\`\`\`
$E2E_QUIET_OUT
\`\`\`

### --json stdout
\`\`\`
$E2E_JSON_OUT
\`\`\`

## Assessment
$([ $FAIL -eq 0 ] && echo "✓ All unit tests passed" || echo "✗ $FAIL test(s) failed")
$([ $WARN -gt 0 ] && echo "⚠ $WARN warning(s)" || echo "✓ No warnings")
RESULT_EOF

log "Results → $RESULT_FILE"
log "Done. Pass=$PASS Warn=$WARN Fail=$FAIL"

[ $FAIL -eq 0 ] || exit 1
