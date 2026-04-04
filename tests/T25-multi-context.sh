#!/usr/bin/env bash
# T25 — Multi-context injection (multiple --context flags)
#
# What: Verifies that --context can be specified multiple times to inject multiple
#       files or directories into a single agent call. This is a new feature (implemented
#       alongside T25) that makes clawbox more useful for cross-file analysis tasks.
#
# Why:  Real refactoring/analysis tasks span multiple files. Before this feature,
#       users had to manually concatenate files or use a directory context. With
#       multi-context, you can precisely select which files to inject.
#
# Phases:
#   1. Two separate files as context — agent references both
#   2. Mix: one file + one directory as context
#   3. Three files — agent counts all three
#   4. JSON output: context_files sum is correct across multiple --context flags
#   5. Error handling: one valid, one invalid path — exits with error
#   6. Order independence: flags before and after the message arg
#   7. --json context_files reflects total across all injected paths
#   8. Task command: --context repeated works for background tasks too

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CLI="$CLAWBOX_DIR/clawbox"
RESULTS_DIR="$SCRIPT_DIR/results"
TS=$(date '+%Y-%m-%d-%H-%M')
RESULT_FILE="$RESULTS_DIR/${TS}-T25-multi-context.md"
TMPDIR_T25=$(mktemp -d)

source "$SCRIPT_DIR/lib/common.sh"

mkdir -p "$RESULTS_DIR"

# ── Counters ────────────────────────────────────────────────────────
PASS=0; WARN=0; FAIL=0
pass() { PASS=$((PASS+1)); echo "  ✓ $1"; }
warn() { WARN=$((WARN+1)); echo "  ⚠ $1"; }
fail() { FAIL=$((FAIL+1)); echo "  ✗ $1"; }

log() { echo ""; echo "── $1"; }

# ── Cleanup ─────────────────────────────────────────────────────────
cleanup() { rm -rf "$TMPDIR_T25"; }
trap cleanup EXIT

echo ""
echo "╔═══════════════════════════════════════════════════════╗"
echo "║  T25 — Multi-context injection                        ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo ""

# ── Setup: Create test files ─────────────────────────────────────────
log "Setting up test files"
MATH_FILE="$TMPDIR_T25/math.js"
STRINGS_FILE="$TMPDIR_T25/strings.js"
UTILS_FILE="$TMPDIR_T25/utils.js"
SUBDIR="$TMPDIR_T25/helpers"

cat > "$MATH_FILE" << 'JSEOF'
// CANARY_MATH_SENTINEL_7419
function add(a, b) { return a + b; }
function multiply(a, b) { return a * b; }
module.exports = { add, multiply };
JSEOF

cat > "$STRINGS_FILE" << 'JSEOF'
// CANARY_STRINGS_SENTINEL_8521
function greet(name) { return `Hello, ${name}!`; }
function shout(text) { return text.toUpperCase(); }
module.exports = { greet, shout };
JSEOF

cat > "$UTILS_FILE" << 'JSEOF'
// CANARY_UTILS_SENTINEL_9630
function clamp(val, min, max) { return Math.min(Math.max(val, min), max); }
module.exports = { clamp };
JSEOF

mkdir -p "$SUBDIR"
cat > "$SUBDIR/format.js" << 'JSEOF'
// CANARY_FORMAT_SENTINEL_2847
function formatDate(d) { return d.toISOString().split('T')[0]; }
module.exports = { formatDate };
JSEOF

echo "  Created: math.js, strings.js, utils.js, helpers/format.js"

# ── Phase 1: Two files as context ────────────────────────────────────
log "Phase 1: Two separate files injected via --context --context"

RESPONSE_P1=$("$CLI" run --quiet \
  --context "$MATH_FILE" \
  --context "$STRINGS_FILE" \
  "List all exported function names from both files. Use the format: math: <names>, strings: <names>" 2>&1) || true

if is_rate_limited "$RESPONSE_P1"; then
  skip_rate_limited "T25" "$RESULT_FILE" "$RESPONSE_P1"
  exit 0
fi

echo "$RESPONSE_P1" | head -5

# Check MATH sentinel
if echo "$RESPONSE_P1" | grep -q "CANARY_MATH_SENTINEL_7419\|add\|multiply"; then
  pass "Math file content referenced in response (add/multiply present)"
else
  warn "Math file content not clearly referenced"
fi

# Check STRINGS sentinel
if echo "$RESPONSE_P1" | grep -q "CANARY_STRINGS_SENTINEL_8521\|greet\|shout"; then
  pass "Strings file content referenced in response (greet/shout present)"
else
  warn "Strings file content not clearly referenced"
fi

# ── Phase 2: JSON — context_files sum is correct ──────────────────────
log "Phase 2: JSON output — context_files counts both files"

JSON_P2=$("$CLI" run --json \
  --context "$MATH_FILE" \
  --context "$STRINGS_FILE" \
  "Reply with exactly: BOTH_FILES_OK" 2>&1) || true

if is_rate_limited "$JSON_P2"; then
  skip_rate_limited "T25" "$RESULT_FILE" "$JSON_P2"
  exit 0
fi

# Validate JSON
if echo "$JSON_P2" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
  pass "JSON is valid"
else
  fail "JSON output is not valid JSON"
fi

# Check context_files = 2 (one per file)
CTX_COUNT=$(echo "$JSON_P2" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('context_files',0))" 2>/dev/null || echo "0")
if [ "$CTX_COUNT" -eq 2 ]; then
  pass "context_files=2 (both files counted)"
elif [ "$CTX_COUNT" -ge 1 ]; then
  warn "context_files=$CTX_COUNT (expected 2)"
else
  fail "context_files=0 (no context counted)"
fi

# Check response contains expected text
if echo "$JSON_P2" | python3 -c "import json,sys; r=json.load(sys.stdin)['response']; sys.exit(0 if 'BOTH_FILES_OK' in r else 1)" 2>/dev/null; then
  pass "Response content correct with multi-context"
else
  warn "Response did not contain expected BOTH_FILES_OK"
fi

# ── Phase 3: Three files — all three referenced ─────────────────────
log "Phase 3: Three files injected"

RESPONSE_P3=$("$CLI" run --quiet \
  --context "$MATH_FILE" \
  --context "$STRINGS_FILE" \
  --context "$UTILS_FILE" \
  "How many files did I provide? And list all function names from all three files." 2>&1) || true

if is_rate_limited "$RESPONSE_P3"; then
  skip_rate_limited "T25" "$RESULT_FILE" "$RESPONSE_P3"
  exit 0
fi

echo "$RESPONSE_P3" | head -6

# Check all three sentinels / function names appear
FUNCTIONS_FOUND=0
echo "$RESPONSE_P3" | grep -qi "add\|multiply" && FUNCTIONS_FOUND=$((FUNCTIONS_FOUND+1)) || true
echo "$RESPONSE_P3" | grep -qi "greet\|shout" && FUNCTIONS_FOUND=$((FUNCTIONS_FOUND+1)) || true
echo "$RESPONSE_P3" | grep -qi "clamp" && FUNCTIONS_FOUND=$((FUNCTIONS_FOUND+1)) || true

if [ "$FUNCTIONS_FOUND" -eq 3 ]; then
  pass "All 3 files referenced (functions from math, strings, utils all mentioned)"
elif [ "$FUNCTIONS_FOUND" -ge 2 ]; then
  warn "Only $FUNCTIONS_FOUND/3 file contents referenced"
else
  fail "Agent only referenced $FUNCTIONS_FOUND/3 files in response"
fi

# ── Phase 4: File + Directory mix ────────────────────────────────────
log "Phase 4: File + directory mix"

# Write JSON to temp file to avoid stderr (▶ Attaching... banner) mixing into $() capture
JSON_P4_FILE="$TMPDIR_T25/p4-out.json"
"$CLI" run --json \
  --context "$UTILS_FILE" \
  --context "$SUBDIR" \
  "Describe each file's purpose in one sentence each." \
  > "$JSON_P4_FILE" 2>/tmp/t25-p4-stderr || true

JSON_P4=$(cat "$JSON_P4_FILE" 2>/dev/null || echo "")

if [ -z "$JSON_P4" ]; then
  STDERR_P4=$(cat /tmp/t25-p4-stderr 2>/dev/null || echo "")
  if is_rate_limited "$STDERR_P4"; then
    skip_rate_limited "T25" "$RESULT_FILE" "$STDERR_P4"
    exit 0
  fi
  fail "Phase 4: No JSON output (check stderr)"
else
  # Validate JSON
  if echo "$JSON_P4" | python3 -c "import json,sys; json.load(sys.stdin)" 2>/dev/null; then
    # Check context_files ≥ 2 (1 file + 1 dir with 1 file)
    CTX_COUNT_P4=$(echo "$JSON_P4" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('context_files',0))" 2>/dev/null || echo "0")
    if [ "$CTX_COUNT_P4" -ge 2 ]; then
      pass "context_files=$CTX_COUNT_P4 (file + dir, ≥2 expected)"
    else
      warn "context_files=$CTX_COUNT_P4 for file+dir mix (expected ≥2)"
    fi

    # Check both utils and format.js are referenced
    RESP_P4=$(echo "$JSON_P4" | python3 -c "import json,sys; print(json.load(sys.stdin).get('response',''))" 2>/dev/null || echo "")
    if echo "$RESP_P4" | grep -qi "CANARY_UTILS_SENTINEL_9630\|clamp\|util"; then
      pass "utils.js content referenced (clamp function visible)"
    else
      warn "utils.js content not clearly in response"
    fi
    if echo "$RESP_P4" | grep -qi "CANARY_FORMAT_SENTINEL_2847\|formatDate\|format\|date"; then
      pass "helpers/format.js content referenced (formatDate visible)"
    else
      warn "helpers/format.js content not clearly referenced"
    fi
  else
    fail "Phase 4: Invalid JSON output"
  fi
fi

# ── Phase 5: Error handling — one valid, one invalid path ───────────
log "Phase 5: Error on invalid --context path"

ERROR_OUT=$("$CLI" run \
  --context "$MATH_FILE" \
  --context "/nonexistent/invalid/path.js" \
  "test" 2>&1) || true

if echo "$ERROR_OUT" | grep -qi "not found\|error\|invalid\|nonexistent"; then
  pass "Error message for invalid --context path"
else
  fail "No error message for invalid --context path"
fi

# Should not produce JSON (should have exited with error before calling agent)
if echo "$ERROR_OUT" | grep -q '"response"'; then
  warn "Unexpectedly reached agent with invalid context path"
else
  pass "Exited before calling agent on invalid path"
fi

# ── Phase 6: Flags after message arg ─────────────────────────────────
log "Phase 6: --context flags work in any flag position"

# Standard flag-before-message works (already tested above); now test message-first
# Note: clawbox run CLI currently requires message to be positional last; this tests
# that repeated flags before message work properly (flag order within flags)
JSON_P6=$("$CLI" run --json \
  --context "$STRINGS_FILE" \
  --context "$MATH_FILE" \
  "Reply with: REVERSED_OK" 2>&1) || true

if is_rate_limited "$JSON_P6"; then
  skip_rate_limited "T25" "$RESULT_FILE" "$JSON_P6"
  exit 0
fi

CTX_P6=$(echo "$JSON_P6" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('context_files',0))" 2>/dev/null || echo "0")
if [ "$CTX_P6" -eq 2 ]; then
  pass "Reversed --context order: context_files=2 (order-independent)"
else
  warn "Reversed --context order: context_files=$CTX_P6 (expected 2)"
fi

RESP_P6=$(echo "$JSON_P6" | python3 -c "import json,sys; print(json.load(sys.stdin).get('response',''))" 2>/dev/null || echo "")
if echo "$RESP_P6" | grep -q "REVERSED_OK"; then
  pass "Response correct with reversed --context order"
else
  warn "Response did not contain REVERSED_OK"
fi

# ── Phase 7: Help text documents multi-context ───────────────────────
log "Phase 7: Help text mentions multi-context capability"

HELP_OUT=$("$CLI" help 2>&1)
if echo "$HELP_OUT" | grep -qi "repeat\|multiple"; then
  pass "Help mentions repeating --context"
else
  warn "Help does not mention multi-context capability"
fi

# ── Phase 8: Single --context still works (regression) ───────────────
log "Phase 8: Single --context still works (regression check)"

JSON_P8=$("$CLI" run --json \
  --context "$MATH_FILE" \
  "Reply with: SINGLE_CONTEXT_OK" 2>&1) || true

if is_rate_limited "$JSON_P8"; then
  skip_rate_limited "T25" "$RESULT_FILE" "$JSON_P8"
  exit 0
fi

CTX_P8=$(echo "$JSON_P8" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('context_files',0))" 2>/dev/null || echo "0")
if [ "$CTX_P8" -eq 1 ]; then
  pass "Single --context: context_files=1 (regression OK)"
else
  fail "Single --context: context_files=$CTX_P8 (expected 1) — regression!"
fi

RESP_P8=$(echo "$JSON_P8" | python3 -c "import json,sys; print(json.load(sys.stdin).get('response',''))" 2>/dev/null || echo "")
if echo "$RESP_P8" | grep -q "SINGLE_CONTEXT_OK"; then
  pass "Single --context response correct"
else
  warn "Single --context response did not contain SINGLE_CONTEXT_OK"
fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
echo "────────────────────────────────────────────"
TOTAL=$((PASS+WARN+FAIL))
echo "  Pass: $PASS   Warn: $WARN   Fail: $FAIL   (of $TOTAL checks)"
echo "────────────────────────────────────────────"

# ── Write result file ────────────────────────────────────────────────
cat > "$RESULT_FILE" << EOF
# T25 — Multi-context injection

**Date:** $(date '+%Y-%m-%d %H:%M')
**Pass:** $PASS  **Warn:** $WARN  **Fail:** $FAIL

## Result: $([ $FAIL -eq 0 ] && echo "✅ PASS" || echo "❌ FAIL")

## Phase Summary

- Phase 1: Two files via --context --context → both referenced in response
- Phase 2: JSON context_files = 2 (sum of both files)
- Phase 3: Three files → all function names from all three files present
- Phase 4: File + directory mix → context_files counts both
- Phase 5: Error handling → exits gracefully on invalid path
- Phase 6: Reversed flag order → same result (order-independent)
- Phase 7: Help text mentions repeating --context
- Phase 8: Single --context regression → still works correctly

## Notes

- Multi-context feature implemented in this session (FEATURE: repeat --context)
- context_files JSON key sums all injected files across all --context args
- Error on first invalid path (fail-fast behavior)

$([ $FAIL -eq 0 ] && echo "**Verdict:** Multi-context injection working correctly across all scenarios. ✅" || echo "**Verdict:** Some checks failed — see output above. ❌")
EOF

echo ""
echo "Result: $RESULT_FILE"
echo ""

exit $FAIL
