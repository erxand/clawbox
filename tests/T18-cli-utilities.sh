#!/usr/bin/env bash
# T18 — CLI Utility Commands
#
# Tests: clawbox cp, shell, logs-tail, ask, help, and edge cases
# for commands that have zero dedicated test coverage.
#
# Duration: ~60s (no agent calls, pure infrastructure)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULT_DIR="$SCRIPT_DIR/results"
RESULT_FILE="$RESULT_DIR/$(date '+%Y-%m-%d-%H-%M')-T18-cli-utilities.md"
CONTAINER="clawbox-work"
CLAWBOX="$PROJECT_DIR/clawbox"
GATEWAY_PORT="${GATEWAY_PORT:-18790}"

source "$SCRIPT_DIR/lib/common.sh"

PASS=0 WARN=0 FAIL=0
_pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
_warn() { echo "  ⚠ $*"; WARN=$((WARN+1)); }
_fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }

TOTAL=0
_count() { TOTAL=$((TOTAL+1)); }

# Container workspace (writable volume) — docker cp to non-volume paths
# fails on read-only rootfs containers, so all cp tests target the workspace.
WORKSPACE="/home/node/.openclaw/workspace"
T18_DIR="$WORKSPACE/.t18-test"

echo ""
echo "═══════════════════════════════════════"
echo " T18 — CLI Utility Commands"
echo "═══════════════════════════════════════"
echo ""

# ── Pre-flight: container must be running ──────────────────────────
running=$(docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null || echo "false")
if [ "$running" != "true" ]; then
  echo "SKIP: Container $CONTAINER is not running."
  mkdir -p "$RESULT_DIR"
  echo "# T18 — SKIPPED (container not running)" > "$RESULT_FILE"
  exit 0
fi

# ══════════════════════════════════════════════════════════════════════
# PHASE 1: clawbox cp
# ══════════════════════════════════════════════════════════════════════
echo "── Phase 1: clawbox cp ──"

# Create temp files on host
TMPDIR_HOST=$(mktemp -d)
trap 'rm -rf "$TMPDIR_HOST"; docker exec "$CONTAINER" rm -rf "$T18_DIR" 2>/dev/null || true' EXIT

echo "hello from T18" > "$TMPDIR_HOST/test-file.txt"
mkdir -p "$TMPDIR_HOST/test-dir"
echo "file-a" > "$TMPDIR_HOST/test-dir/a.txt"
echo "file-b" > "$TMPDIR_HOST/test-dir/b.txt"
echo '{"key": "value"}' > "$TMPDIR_HOST/test-dir/data.json"
echo "spaces work" > "$TMPDIR_HOST/file with spaces.txt"
dd if=/dev/urandom of="$TMPDIR_HOST/large-file.bin" bs=1024 count=1024 2>/dev/null

# Clean up any leftovers in container
docker exec "$CONTAINER" rm -rf "$T18_DIR" 2>/dev/null || true
docker exec "$CONTAINER" mkdir -p "$T18_DIR" 2>/dev/null || true

# Test 1: cp single file
_count
CP_OUT=$("$CLAWBOX" cp "$TMPDIR_HOST/test-file.txt" "$T18_DIR/test-file.txt" 2>&1) || true
if echo "$CP_OUT" | grep -q "Copied and ownership fixed"; then
  _pass "cp single file: success message shown"
else
  _fail "cp single file: expected 'Copied and ownership fixed', got: $CP_OUT"
fi

# Test 2: verify file content in container
_count
FILE_CONTENT=$(docker exec "$CONTAINER" cat "$T18_DIR/test-file.txt" 2>/dev/null || echo "NOT_FOUND")
if [ "$FILE_CONTENT" = "hello from T18" ]; then
  _pass "cp single file: content correct in container"
else
  _fail "cp single file: expected 'hello from T18', got: $FILE_CONTENT"
fi

# Test 3: verify file ownership (ISSUE-28 fix)
_count
FILE_OWNER=$(docker exec "$CONTAINER" stat -c '%U:%G' "$T18_DIR/test-file.txt" 2>/dev/null || echo "UNKNOWN")
if [ "$FILE_OWNER" = "node:node" ]; then
  _pass "cp single file: ownership is node:node (ISSUE-28 fix)"
else
  _fail "cp single file: ownership is '$FILE_OWNER', expected 'node:node'"
fi

# Test 4: cp directory
_count
CP_DIR_OUT=$("$CLAWBOX" cp "$TMPDIR_HOST/test-dir" "$T18_DIR/test-dir" 2>&1) || true
if echo "$CP_DIR_OUT" | grep -q "Copied and ownership fixed"; then
  _pass "cp directory: success message shown"
else
  _fail "cp directory: expected 'Copied and ownership fixed', got: $CP_DIR_OUT"
fi

# Test 5: verify directory contents
_count
DIR_FILES=$(docker exec "$CONTAINER" ls "$T18_DIR/test-dir/" 2>/dev/null | sort | tr '\n' ' ')
if echo "$DIR_FILES" | grep -q "a.txt" && echo "$DIR_FILES" | grep -q "b.txt" && echo "$DIR_FILES" | grep -q "data.json"; then
  _pass "cp directory: all 3 files present in container"
else
  _fail "cp directory: expected a.txt, b.txt, data.json — got: $DIR_FILES"
fi

# Test 6: verify directory file ownership
_count
DIR_OWNER=$(docker exec "$CONTAINER" stat -c '%U:%G' "$T18_DIR/test-dir/a.txt" 2>/dev/null || echo "UNKNOWN")
if [ "$DIR_OWNER" = "node:node" ]; then
  _pass "cp directory: nested file ownership is node:node"
else
  _fail "cp directory: nested file ownership is '$DIR_OWNER', expected 'node:node'"
fi

# Test 7: cp with missing args → usage hint
_count
CP_NOARGS=$("$CLAWBOX" cp 2>&1) || CP_EXIT=$?
if echo "$CP_NOARGS" | grep -qi "usage"; then
  _pass "cp no args: shows usage hint"
else
  _fail "cp no args: expected usage hint, got: $CP_NOARGS"
fi

# Test 8: cp with only one arg → usage hint
_count
CP_ONEARG=$("$CLAWBOX" cp "/tmp/foo" 2>&1) || CP_EXIT=$?
if echo "$CP_ONEARG" | grep -qi "usage"; then
  _pass "cp one arg: shows usage hint"
else
  _fail "cp one arg: expected usage hint, got: $CP_ONEARG"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════
# PHASE 2: clawbox shell (non-interactive check)
# ══════════════════════════════════════════════════════════════════════
echo "── Phase 2: clawbox shell ──"

# We can't test interactive shell fully, but we can verify the command
# exists in the help and that docker exec works into the container
_count
SHELL_HELP=$("$CLAWBOX" help 2>&1)
if echo "$SHELL_HELP" | grep -q "shell"; then
  _pass "shell: listed in help output"
else
  _fail "shell: not found in help output"
fi

# Test: can exec into the container (non-interactive equivalent)
_count
WHOAMI=$(docker exec "$CONTAINER" whoami 2>/dev/null || echo "FAIL")
if [ "$WHOAMI" = "node" ]; then
  _pass "shell context: container runs as 'node' user"
else
  _fail "shell context: expected 'node', got '$WHOAMI'"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════
# PHASE 3: clawbox logs-tail
# ══════════════════════════════════════════════════════════════════════
echo "── Phase 3: clawbox logs-tail ──"

# logs-tail reads the openclaw log file inside the container
_count
LOGS_OUT=$("$CLAWBOX" logs-tail 2>&1) || true
if [ -n "$LOGS_OUT" ]; then
  # If we got output, it either found the log file or said "No log file found"
  if echo "$LOGS_OUT" | grep -q "No log file found"; then
    _warn "logs-tail: no log file for today (container may not have run recently)"
  else
    _pass "logs-tail: returned log content ($(echo "$LOGS_OUT" | wc -l | tr -d ' ') lines)"
  fi
else
  _fail "logs-tail: returned empty output"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════
# PHASE 4: clawbox ask (alias for run)
# ══════════════════════════════════════════════════════════════════════
echo "── Phase 4: clawbox ask ──"

# Test: ask is listed in help
_count
if echo "$SHELL_HELP" | grep -q "ask"; then
  _pass "ask: listed in help output"
else
  _fail "ask: not found in help output"
fi

# Test: ask with no message shows usage hint
_count
ASK_NOARGS=$("$CLAWBOX" ask 2>&1) || true
if echo "$ASK_NOARGS" | grep -qi "usage\|message\|required"; then
  _pass "ask no args: shows usage/error hint"
else
  # It might fall through to cmd_run which also checks for empty args
  _warn "ask no args: output was: $(echo "$ASK_NOARGS" | head -3)"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════
# PHASE 5: help completeness
# ══════════════════════════════════════════════════════════════════════
echo "── Phase 5: help completeness ──"

# All commands should be listed in help
EXPECTED_COMMANDS="start stop restart status logs run ask chat task task-status task-logs cancel cp shell backup restore upgrade clean doctor"
for cmd in $EXPECTED_COMMANDS; do
  _count
  if echo "$SHELL_HELP" | grep -q "$cmd"; then
    _pass "help: '$cmd' present"
  else
    _fail "help: '$cmd' missing from help output"
  fi
done

echo ""

# ══════════════════════════════════════════════════════════════════════
# PHASE 6: clawbox status output validation
# ══════════════════════════════════════════════════════════════════════
echo "── Phase 6: status output ──"

_count
STATUS_OUT=$("$CLAWBOX" status 2>&1) || true

# Should show container state
if echo "$STATUS_OUT" | grep -qi "running\|healthy\|up"; then
  _pass "status: shows container running state"
else
  _fail "status: no running/healthy indicator in output"
fi

# Should show gateway URL (ISSUE-25 / T7 fix: ws:// shown for copy-paste)
_count
if echo "$STATUS_OUT" | grep -q "ws://"; then
  _pass "status: shows ws:// gateway URL"
else
  _warn "status: no ws:// URL shown"
fi

# Should show GATEWAY_PORT
_count
if echo "$STATUS_OUT" | grep -q "$GATEWAY_PORT\|18790"; then
  _pass "status: shows gateway port"
else
  _warn "status: no port number visible"
fi

echo ""

# ══════════════════════════════════════════════════════════════════════
# PHASE 7: cp with special characters in filenames
# ══════════════════════════════════════════════════════════════════════
echo "── Phase 7: edge cases ──"

# File with spaces in name
_count
CP_SPACES=$("$CLAWBOX" cp "$TMPDIR_HOST/file with spaces.txt" "$T18_DIR/file with spaces.txt" 2>&1) || true
SPACES_CONTENT=$(docker exec "$CONTAINER" cat "$T18_DIR/file with spaces.txt" 2>/dev/null || echo "NOT_FOUND")
if [ "$SPACES_CONTENT" = "spaces work" ]; then
  _pass "cp file with spaces: content preserved"
else
  _fail "cp file with spaces: expected 'spaces work', got '$SPACES_CONTENT'"
fi

# Large file (1MB)
_count
"$CLAWBOX" cp "$TMPDIR_HOST/large-file.bin" "$T18_DIR/large-file.bin" >/dev/null 2>&1
HOST_SIZE=$(stat -f%z "$TMPDIR_HOST/large-file.bin" 2>/dev/null || stat -c%s "$TMPDIR_HOST/large-file.bin" 2>/dev/null || echo "0")
CONTAINER_SIZE=$(docker exec "$CONTAINER" stat -c%s "$T18_DIR/large-file.bin" 2>/dev/null || echo "0")
if [ "$HOST_SIZE" = "$CONTAINER_SIZE" ] && [ "$HOST_SIZE" -gt 0 ]; then
  _pass "cp large file (1MB): size matches ($HOST_SIZE bytes)"
else
  _fail "cp large file: host=$HOST_SIZE, container=$CONTAINER_SIZE"
fi

# Unknown command → shows help
_count
UNKNOWN_OUT=$("$CLAWBOX" nonexistent-command 2>&1) || true
if echo "$UNKNOWN_OUT" | grep -qi "unknown\|usage\|help\|commands"; then
  _pass "unknown command: shows help/error"
else
  _fail "unknown command: output was: $(echo "$UNKNOWN_OUT" | head -3)"
fi

echo ""

# ── Summary ──────────────────────────────────────────────────────────
echo "════════════════════════════════════════"
echo "  T18 Results: Pass: $PASS   Warn: $WARN   Fail: $FAIL   (of $TOTAL checks)"
if [ "$FAIL" -eq 0 ]; then
  echo "  ✓ All critical checks pass!"
else
  echo "  ✗ $FAIL critical issue(s) found"
fi
echo "════════════════════════════════════════"

# ── Write result file ────────────────────────────────────────────────
mkdir -p "$RESULT_DIR"
cat > "$RESULT_FILE" << EOF
# T18 — CLI Utility Commands
**Date:** $(date '+%Y-%m-%d %H:%M')
**Duration:** Infrastructure-only (no agent calls)

## Summary
- **Pass:** $PASS
- **Warn:** $WARN
- **Fail:** $FAIL
- **Total:** $TOTAL

## Checks
### Phase 1: clawbox cp (8 checks)
- Single file copy + content verification + ownership (ISSUE-28)
- Directory copy + content + nested ownership
- Missing args → usage hint
- One arg → usage hint

### Phase 2: clawbox shell (2 checks)
- Listed in help
- Container runs as 'node' user

### Phase 3: clawbox logs-tail (1 check)
- Returns content or clear "no log" message

### Phase 4: clawbox ask (2 checks)
- Listed in help
- No-args shows usage hint

### Phase 5: help completeness ($(echo $EXPECTED_COMMANDS | wc -w | tr -d ' ') checks)
- All commands present in help output

### Phase 6: status output (3 checks)
- Running state visible
- ws:// gateway URL shown
- Port number visible

### Phase 7: edge cases (3 checks)
- File with spaces in name
- Large file (1MB) size preserved
- Unknown command → help/error

## Verdict
$([ "$FAIL" -eq 0 ] && echo "✅ All CLI utilities working correctly." || echo "⚠️ $FAIL check(s) failed — see above.")
EOF

echo ""
echo "Result: $RESULT_FILE"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
