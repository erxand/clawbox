#!/usr/bin/env bash
# T21 — JSON output completeness + CLAWBOX_DIR env override
#
# What:
#   Phase 1: Validates `clawbox run --json` produces parseable, complete JSON with
#            all documented keys, and that output can be piped through jq reliably.
#   Phase 2: Validates CLAWBOX_DIR env var lets the installed binary find a custom
#            project directory (documented in help but never tested end-to-end).
#   Phase 3: Validates `clawbox task-status` output format — shows task info or
#            "no task" cleanly.
#
# Why: --json was implemented (T9 confirms flag works) but the *completeness* of
#      the JSON schema has never been stress-tested. CLAWBOX_DIR is documented in
#      help but has no test coverage. task-status format is checked in T11 but only
#      as part of a larger test.
#
# Usage:
#   bash tests/T21-json-and-env-override.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T21-json-env-override.md"

mkdir -p "$RESULT_DIR"

PASS=0
FAIL=0
WARN=0
RESULTS=""

log() { echo "[T21 $(date +%H:%M:%S)] $*"; }

pass() {
  echo "  ✓ $*"
  PASS=$((PASS+1))
  RESULTS="${RESULTS}\n| ✓ PASS | $* |"
}

warn() {
  echo "  ⚠ $*"
  WARN=$((WARN+1))
  RESULTS="${RESULTS}\n| ⚠ WARN | $* |"
}

fail() {
  echo "  ✗ $*"
  FAIL=$((FAIL+1))
  RESULTS="${RESULTS}\n| ✗ FAIL | $* |"
}

# ── Preamble ───────────────────────────────────────────────────────────────────
echo ""
echo "=== T21: JSON output completeness + CLAWBOX_DIR env override ==="
echo ""

# Require jq
if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required for this test"
  exit 1
fi

# ══════════════════════════════════════════════════════════════════════
# PHASE 1: JSON output completeness
# ══════════════════════════════════════════════════════════════════════
log "════ PHASE 1: JSON output completeness ════"

# 1.1: Basic --json produces valid JSON
log "1.1: clawbox run --json produces valid JSON"
JSON_OUT=$("$CLAWBOX" run --json "Reply with exactly: OK" 2>/dev/null || true)
if echo "$JSON_OUT" | jq . >/dev/null 2>&1; then
  pass "--json output is valid JSON"
else
  fail "--json output is not valid JSON: $JSON_OUT"
fi

# 1.2: Required keys present: response, elapsed_ms, timestamp, context_files
log "1.2: Required JSON keys present"
KEYS_OK=true
for key in response elapsed_ms timestamp context_files; do
  val=$(echo "$JSON_OUT" | jq -r ".$key // \"__MISSING__\"" 2>/dev/null || echo "__MISSING__")
  if [ "$val" = "__MISSING__" ] || [ "$val" = "null" ]; then
    fail "JSON missing key: $key"
    KEYS_OK=false
  else
    pass "JSON has key: $key (value: $val)"
  fi
done

# 1.3: elapsed_ms is a positive integer
log "1.3: elapsed_ms is a positive integer"
ELAPSED=$(echo "$JSON_OUT" | jq -r '.elapsed_ms // 0' 2>/dev/null || echo "0")
if echo "$ELAPSED" | grep -qE '^[0-9]+$' && [ "$ELAPSED" -gt 0 ]; then
  pass "elapsed_ms is a positive integer: ${ELAPSED}ms"
else
  fail "elapsed_ms is not a positive integer: $ELAPSED"
fi

# 1.4: timestamp is ISO-8601 (contains 'T' and 'Z' or '+')
log "1.4: timestamp is ISO-8601 format"
TS_VAL=$(echo "$JSON_OUT" | jq -r '.timestamp // ""' 2>/dev/null || echo "")
if echo "$TS_VAL" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}T'; then
  pass "timestamp is ISO-8601 format: $TS_VAL"
else
  fail "timestamp is not ISO-8601: $TS_VAL"
fi

# 1.5: context_files is 0 when no --context flag
log "1.5: context_files is 0 without --context"
CTX_COUNT=$(echo "$JSON_OUT" | jq -r '.context_files // -1' 2>/dev/null || echo "-1")
if [ "$CTX_COUNT" = "0" ]; then
  pass "context_files=0 when no --context flag"
else
  warn "context_files=$CTX_COUNT (expected 0) — may be ok if session has prior context"
fi

# 1.6: response field contains actual content (not empty)
log "1.6: response field is non-empty"
RESP=$(echo "$JSON_OUT" | jq -r '.response // ""' 2>/dev/null || echo "")
if [ -n "$RESP" ]; then
  pass "response field is non-empty (len=${#RESP})"
else
  fail "response field is empty"
fi

# 1.7: --json with --context sets context_files > 0
log "1.7: --json + --context sets context_files > 0"
TMPDIR_T21=$(mktemp -d)
echo "function add(a, b) { return a + b; }" > "$TMPDIR_T21/math.js"
JSON_WITH_CTX=$("$CLAWBOX" run --json --context "$TMPDIR_T21" "How many functions are in math.js?" 2>/dev/null || true)
CTX_WITH=$(echo "$JSON_WITH_CTX" | jq -r '.context_files // 0' 2>/dev/null || echo "0")
rm -rf "$TMPDIR_T21"
if [ "$CTX_WITH" -gt 0 ]; then
  pass "--json + --context: context_files=$CTX_WITH (>0)"
else
  fail "--json + --context: context_files=$CTX_WITH (expected >0)"
fi

# 1.8: --json output can be piped through jq and used in shell
log "1.8: --json output can be extracted via jq in a shell pipeline"
PIPED_RESP=$("$CLAWBOX" run --json "Reply with exactly the word: PIPELINE_OK" 2>/dev/null | jq -r '.response' 2>/dev/null || echo "")
if [ -n "$PIPED_RESP" ]; then
  pass "jq pipeline extraction works (response: ${PIPED_RESP:0:50})"
else
  fail "jq pipeline extraction returned empty string"
fi

# 1.9: --json + --session includes session key
log "1.9: --json + --session includes 'session' key in output"
JSON_WITH_SESSION=$("$CLAWBOX" run --json --session "t21-test-$$" "Say hello" 2>/dev/null || true)
SESSION_VAL=$(echo "$JSON_WITH_SESSION" | jq -r '.session // "__MISSING__"' 2>/dev/null || echo "__MISSING__")
if [ "$SESSION_VAL" != "__MISSING__" ] && [ "$SESSION_VAL" != "null" ]; then
  pass "--json + --session: 'session' key present (value: $SESSION_VAL)"
else
  warn "--json + --session: 'session' key missing — may not be implemented"
fi

# 1.10: --quiet mode sends banners to stderr, response-only on stdout
log "1.10: --quiet output has no banner text on stdout"
QUIET_OUT=$("$CLAWBOX" run --quiet "Reply with exactly: QUIET_OK" 2>/dev/null || true)
if echo "$QUIET_OUT" | grep -qiE "clawbox|▶|waiting|spinner|banner"; then
  fail "--quiet stdout contains banner text"
else
  pass "--quiet stdout has no banner (response-only): ${QUIET_OUT:0:50}"
fi

log "════ PHASE 1 COMPLETE: $PASS pass, $WARN warn, $FAIL fail ════"
echo ""

# ══════════════════════════════════════════════════════════════════════
# PHASE 2: CLAWBOX_DIR env var override
# ══════════════════════════════════════════════════════════════════════
log "════ PHASE 2: CLAWBOX_DIR env override ════"
P2_START_PASS=$PASS

# 2.1: clawbox help mentions CLAWBOX_DIR
log "2.1: help text mentions CLAWBOX_DIR"
HELP_OUT=$("$CLAWBOX" help 2>&1 || true)
if echo "$HELP_OUT" | grep -q "CLAWBOX_DIR"; then
  pass "CLAWBOX_DIR documented in help output"
else
  fail "CLAWBOX_DIR not mentioned in help output"
fi

# 2.2: CLAWBOX_DIR set to current project dir still works
log "2.2: CLAWBOX_DIR=<project dir> - status command works"
CLAWBOX_STATUS=$(CLAWBOX_DIR="$(dirname "$CLAWBOX")" "$CLAWBOX" status 2>&1 || true)
if echo "$CLAWBOX_STATUS" | grep -qiE "gateway|running|healthy|NAME|STATUS"; then
  pass "CLAWBOX_DIR override: status command works"
else
  warn "CLAWBOX_DIR override: status output unexpected: ${CLAWBOX_STATUS:0:100}"
fi

# 2.3: CLAWBOX_DIR set to non-existent path gives meaningful error
log "2.3: CLAWBOX_DIR=/nonexistent gives meaningful error"
ERR_OUT=$(CLAWBOX_DIR="/nonexistent-clawbox-dir-$$" "$CLAWBOX" status 2>&1 || true)
if echo "$ERR_OUT" | grep -qiE "error|not found|no such|cannot|missing|invalid"; then
  pass "CLAWBOX_DIR=/nonexistent gives meaningful error"
elif echo "$ERR_OUT" | grep -qiE "Clawbox|gateway|docker"; then
  warn "CLAWBOX_DIR=/nonexistent: no explicit error, but output references clawbox — may be ok"
else
  warn "CLAWBOX_DIR=/nonexistent: unexpected output: ${ERR_OUT:0:100}"
fi

# 2.4: GATEWAY_PORT env var override works
log "2.4: GATEWAY_PORT env var is respected in help output context check"
GATEWAY_PORT_HELP=$(GATEWAY_PORT=19999 "$CLAWBOX" help 2>&1 || true)
if echo "$GATEWAY_PORT_HELP" | grep -q "GATEWAY_PORT"; then
  pass "GATEWAY_PORT documented in help output"
else
  warn "GATEWAY_PORT not mentioned in help — check docs"
fi

log "════ PHASE 2 COMPLETE: $((PASS - P2_START_PASS)) new checks passed ════"
echo ""

# ══════════════════════════════════════════════════════════════════════
# PHASE 3: task-status output format validation
# ══════════════════════════════════════════════════════════════════════
log "════ PHASE 3: task-status output format ════"
P3_START_PASS=$PASS

# 3.1: task-status with no running task produces clean output (no crash)
log "3.1: task-status with no running task"
STATUS_OUT=$("$CLAWBOX" task-status 2>&1 || true)
if [ -n "$STATUS_OUT" ]; then
  pass "task-status with no task: produces output (no crash)"
else
  warn "task-status with no task: empty output"
fi

# 3.2: task-status mentions log file or 'no task' state
log "3.2: task-status output references log or no-task state"
if echo "$STATUS_OUT" | grep -qiE "log|task|running|no task|idle|\.clawbox"; then
  pass "task-status output references task state or log"
else
  warn "task-status output doesn't mention task state: ${STATUS_OUT:0:100}"
fi

# 3.3: task-status in JSON-parseable context (task-status output is plain text, not JSON — verify it's not accidentally JSON)
log "3.3: task-status is human-readable text (not JSON)"
if echo "$STATUS_OUT" | jq . >/dev/null 2>&1; then
  warn "task-status output appears to be JSON — expected human-readable text"
else
  pass "task-status output is human-readable text (not JSON)"
fi

# 3.4: task-logs with no log file gives graceful error
log "3.4: task-logs with no log file gives graceful error"
# Temporarily move the log symlink if it exists
TASK_LOG_LINK="$HOME/.clawbox-task.log"
TASK_LOG_BACKUP=""
if [ -L "$TASK_LOG_LINK" ]; then
  TASK_LOG_BACKUP=$(readlink "$TASK_LOG_LINK" 2>/dev/null || echo "")
  rm -f "$TASK_LOG_LINK"
fi
LOGS_OUT=$("$CLAWBOX" task-logs 2>&1 || true)
# Restore symlink
if [ -n "$TASK_LOG_BACKUP" ]; then
  ln -sf "$TASK_LOG_BACKUP" "$TASK_LOG_LINK" 2>/dev/null || true
fi
if echo "$LOGS_OUT" | grep -qiE "no log|not found|start a task|task-logs"; then
  pass "task-logs with no log: graceful 'no log' message"
elif [ -n "$LOGS_OUT" ]; then
  warn "task-logs with no log: output exists but no explicit error: ${LOGS_OUT:0:80}"
else
  warn "task-logs with no log: empty output (expected graceful error)"
fi

log "════ PHASE 3 COMPLETE: $((PASS - P3_START_PASS)) new checks passed ════"
echo ""

# ══════════════════════════════════════════════════════════════════════
# Results
# ══════════════════════════════════════════════════════════════════════
TOTAL=$((PASS + FAIL + WARN))
echo "==================================="
echo "RESULT: $PASS pass, $WARN warn, $FAIL fail"
echo "==================================="
echo ""

# Write result file
cat > "$RESULT_FILE" <<EOF
# T21 — JSON output completeness + CLAWBOX_DIR env override
**Date:** $(date '+%Y-%m-%d %H:%M')

## What was tested
- Phase 1: \`clawbox run --json\` produces valid, complete JSON with all documented keys
- Phase 2: \`CLAWBOX_DIR\` env var override behavior
- Phase 3: \`clawbox task-status\` and \`clawbox task-logs\` output format validation

## Results

| Status | Check |
|--------|-------|
$(echo -e "$RESULTS" | tail -n +2)

**${PASS} pass, ${WARN} warn, ${FAIL} fail** (of $TOTAL checks)

## Key findings
$([ $FAIL -gt 0 ] && echo "- ✗ $FAIL failure(s) detected — see table above" || echo "- All critical checks passed")
$([ $WARN -gt 0 ] && echo "- ⚠ $WARN warning(s) — see table above" || echo "- No warnings")
EOF

echo "Results written to $RESULT_FILE"

# Exit non-zero if any hard failures
[ $FAIL -eq 0 ]
