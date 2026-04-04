#!/usr/bin/env bash
# T28 — Combined flags interaction test
#
# What: Verify that `clawbox run` handles combinations of flags correctly:
#       --thinking + --session + --json, --thinking + --context + --quiet,
#       --session + --quiet + --retry, and other pairings. Tests that flags
#       don't conflict or strip each other's effects when combined.
#
# Why:  All flags have been tested individually (T8, T9, T10, T22, T27) but
#       never together. Real-world usage almost always combines flags.
#       A parsing bug (e.g., arg-shift off-by-one, variable shadowing) would
#       only surface with multiple flags at once.
#
# Duration: ~60–90s (3 live agent calls)
# Requires: Container running, gateway healthy

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
RESULT_DIR="$SCRIPT_DIR/results"
TIMESTAMP="$(date '+%Y-%m-%d-%H-%M')"
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T28-combined-flags.md"
CLAWBOX="$PROJECT_DIR/clawbox"
CONTAINER="clawbox-work"
WORKSPACE="/home/node/.openclaw/workspace"
GATEWAY_PORT="${GATEWAY_PORT:-18790}"

source "$SCRIPT_DIR/lib/common.sh"

PASS=0 WARN=0 FAIL=0
_pass() { echo "  ✓ $*"; PASS=$((PASS+1)); }
_warn() { echo "  ⚠ $*"; WARN=$((WARN+1)); }
_fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); }

log() { echo "[$(date '+%H:%M:%S')] $*"; }

echo ""
echo "═══════════════════════════════════════"
echo " T28 — Combined flags interaction"
echo "═══════════════════════════════════════"
echo ""

# ── Pre-flight ────────────────────────────────────────────────────────
running=$(docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null || echo "false")
if [ "$running" != "true" ]; then
  echo "SKIP: Container $CONTAINER is not running."
  mkdir -p "$RESULT_DIR"
  echo "# T28 — SKIPPED (container not running)" > "$RESULT_FILE"
  exit 0
fi
log "Container running. Starting T28 combined-flags test."

# ─────────────────────────────────────────────────────────────────────
# PHASE 1: --thinking + --json (most common real-world combo)
# Expected: valid JSON with response, thinking level respected
# ─────────────────────────────────────────────────────────────────────
log "Phase 1: --thinking minimal + --json"

P1_OUT=$("$CLAWBOX" run --thinking minimal --json "Say exactly: COMBO_T28_P1" 2>/dev/null || echo "FAILED")

if echo "$P1_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'response' in d and 'elapsed_ms' in d else 1)" 2>/dev/null; then
  _pass "Phase 1: --thinking minimal + --json → valid JSON"
else
  _fail "Phase 1: --thinking minimal + --json → invalid JSON or error: $P1_OUT"
fi

P1_RESPONSE=$(echo "$P1_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('response',''))" 2>/dev/null || echo "")
if echo "$P1_RESPONSE" | grep -qi "COMBO_T28_P1"; then
  _pass "Phase 1: response contains expected sentinel"
else
  _warn "Phase 1: response didn't echo sentinel (got: ${P1_RESPONSE:0:80})"
fi

P1_ELAPSED=$(echo "$P1_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('elapsed_ms',-1))" 2>/dev/null || echo "-1")
if [ "$P1_ELAPSED" -gt 0 ] 2>/dev/null; then
  _pass "Phase 1: elapsed_ms positive ($P1_ELAPSED ms)"
else
  _warn "Phase 1: elapsed_ms unexpected ($P1_ELAPSED)"
fi

# ─────────────────────────────────────────────────────────────────────
# PHASE 2: --session + --json (session key appears in JSON output)
# Expected: JSON has 'session' key set to the provided session name
# ─────────────────────────────────────────────────────────────────────
log "Phase 2: --session + --json"

SESSION_NAME="t28-combo-$$"
P2_OUT=$("$CLAWBOX" run --session "$SESSION_NAME" --json "Say exactly: COMBO_T28_P2" 2>/dev/null || echo "FAILED")

if echo "$P2_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); sys.exit(0 if 'session' in d else 1)" 2>/dev/null; then
  _pass "Phase 2: --session + --json → JSON has 'session' key"
else
  _fail "Phase 2: --session + --json → no 'session' key in JSON: $P2_OUT"
fi

P2_SESSION=$(echo "$P2_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('session',''))" 2>/dev/null || echo "")
if [ "$P2_SESSION" = "$SESSION_NAME" ]; then
  _pass "Phase 2: JSON 'session' value matches --session arg ('$SESSION_NAME')"
else
  _warn "Phase 2: JSON 'session' = '$P2_SESSION', expected '$SESSION_NAME'"
fi

P2_RESPONSE=$(echo "$P2_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('response',''))" 2>/dev/null || echo "")
if echo "$P2_RESPONSE" | grep -qi "COMBO_T28_P2"; then
  _pass "Phase 2: response contains expected sentinel"
else
  _warn "Phase 2: response didn't echo sentinel (got: ${P2_RESPONSE:0:80})"
fi

# ─────────────────────────────────────────────────────────────────────
# PHASE 3: --context + --quiet (context injected, no banners on stdout)
# Expected: stdout = response only (no '▶ Attaching...' banner), context used
# ─────────────────────────────────────────────────────────────────────
log "Phase 3: --context + --quiet"

# Create a context file with a distinctive sentinel
CTX_FILE="$(mktemp /tmp/t28-ctx-XXXXXX.js)"
echo "// T28 test context file" > "$CTX_FILE"
echo "function t28_canary() { return 'XYZZY_T28_CONTEXT'; }" >> "$CTX_FILE"

P3_OUT=$("$CLAWBOX" run --context "$CTX_FILE" --quiet "What function is in the attached file? Quote it exactly." 2>/dev/null || echo "FAILED")
rm -f "$CTX_FILE"

# --quiet must suppress banners from stdout
if echo "$P3_OUT" | grep -q "Attaching"; then
  _fail "Phase 3: --context + --quiet → '▶ Attaching...' banner leaked to stdout"
else
  _pass "Phase 3: --context + --quiet → no banner on stdout"
fi

# Context must have been used
if echo "$P3_OUT" | grep -qi "XYZZY_T28_CONTEXT\|t28_canary"; then
  _pass "Phase 3: context injected and referenced in response"
else
  _warn "Phase 3: context may not have been used (response: ${P3_OUT:0:120})"
fi

# ─────────────────────────────────────────────────────────────────────
# PHASE 4: --thinking + --session + --quiet (3-flag combo, static checks)
# Expected: parses correctly, no error, response on stdout without banners
# ─────────────────────────────────────────────────────────────────────
log "Phase 4: --thinking + --session + --quiet (3-flag combo)"

P4_SESSION="t28-threeway-$$"
P4_OUT=$("$CLAWBOX" run --thinking minimal --session "$P4_SESSION" --quiet "Say exactly: COMBO_T28_P4" 2>/dev/null || echo "FAILED")

if [ "$P4_OUT" != "FAILED" ] && [ -n "$P4_OUT" ]; then
  _pass "Phase 4: --thinking + --session + --quiet → non-empty response (no crash)"
else
  _fail "Phase 4: --thinking + --session + --quiet → command failed or empty output"
fi

if echo "$P4_OUT" | grep -qi "COMBO_T28_P4"; then
  _pass "Phase 4: 3-flag combo: response contains expected sentinel"
else
  _warn "Phase 4: 3-flag combo: sentinel not found in response (got: ${P4_OUT:0:80})"
fi

if echo "$P4_OUT" | grep -q "▶\|Attaching\|Gateway"; then
  _fail "Phase 4: --quiet flag ignored — banners leaked to stdout"
else
  _pass "Phase 4: --quiet respected in 3-flag combo (no banner on stdout)"
fi

# ─────────────────────────────────────────────────────────────────────
# PHASE 5: Flag-order independence (flags after message arg)
# Expected: flags before OR after the message arg all parse correctly
# ─────────────────────────────────────────────────────────────────────
log "Phase 5: flag order independence"

# Flags before message (normal order)
P5A=$("$CLAWBOX" run --json --thinking minimal "Say: ORDER_A" 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response',''))" 2>/dev/null || echo "FAILED")

# --retry 0 flag after message (tests post-message arg parsing)
P5B=$("$CLAWBOX" run --json "Say: ORDER_B" --retry 0 2>/dev/null | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response',''))" 2>/dev/null || echo "FAILED")

if echo "$P5A" | grep -qi "ORDER_A"; then
  _pass "Phase 5: flags-before-message → correct response"
else
  _fail "Phase 5: flags-before-message → unexpected: $P5A"
fi

if echo "$P5B" | grep -qi "ORDER_B"; then
  _pass "Phase 5: flag-after-message (--retry 0) → correct response"
else
  _fail "Phase 5: flag-after-message (--retry 0) → unexpected: $P5B"
fi

# ─────────────────────────────────────────────────────────────────────
# PHASE 6: --json + --context file count accuracy with 2 paths
# Expected: context_files sums correctly (mirrors T25/T26 but via run --json)
# ─────────────────────────────────────────────────────────────────────
log "Phase 6: --json + two --context paths → context_files sum"

CTX1="$(mktemp /tmp/t28-ctx1-XXXXXX.js)"
CTX2="$(mktemp /tmp/t28-ctx2-XXXXXX.js)"
echo "function alpha() { return 1; }" > "$CTX1"
echo "function beta() { return 2; }" > "$CTX2"

P6_OUT=$("$CLAWBOX" run --json --context "$CTX1" --context "$CTX2" "What functions are defined?" 2>/dev/null || echo "FAILED")
rm -f "$CTX1" "$CTX2"

P6_CTX_FILES=$(echo "$P6_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('context_files',-1))" 2>/dev/null || echo "-1")
if [ "$P6_CTX_FILES" = "2" ]; then
  _pass "Phase 6: --json + 2x --context → context_files=2"
else
  _fail "Phase 6: --json + 2x --context → context_files=$P6_CTX_FILES (expected 2)"
fi

P6_RESPONSE=$(echo "$P6_OUT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('response',''))" 2>/dev/null || echo "")
if echo "$P6_RESPONSE" | grep -qi "alpha\|beta"; then
  _pass "Phase 6: both context files referenced in response (alpha/beta)"
else
  _warn "Phase 6: context functions not clearly referenced (got: ${P6_RESPONSE:0:120})"
fi

# ─────────────────────────────────────────────────────────────────────
# PHASE 7: Source code — no flag swallows next flag as its value
# Static check: --quiet / --json have no second arg, so they must not
# consume the next token (which would break the following flag).
# ─────────────────────────────────────────────────────────────────────
log "Phase 7: source code — boolean flags don't consume next arg"

CLI_SRC="$PROJECT_DIR/clawbox"
if grep -A3 "\-\-quiet\|-q)" "$CLI_SRC" | grep -q "shift 2"; then
  _fail "Phase 7: --quiet case uses 'shift 2' — would eat next arg as its value"
else
  _pass "Phase 7: --quiet case uses 'shift 1' (or similar) — boolean, correct"
fi

if grep -A3 "\-\-json\|-j)" "$CLI_SRC" | grep -q "shift 2"; then
  _fail "Phase 7: --json case uses 'shift 2' — would eat next arg as its value"
else
  _pass "Phase 7: --json case uses 'shift 1' (or similar) — boolean, correct"
fi

# ─────────────────────────────────────────────────────────────────────
# WRITE RESULT FILE
# ─────────────────────────────────────────────────────────────────────
TOTAL=$((PASS + WARN + FAIL))
VERDICT="✅ All $TOTAL checks pass (combined flags working correctly)."
if [ "$FAIL" -gt 0 ]; then
  VERDICT="❌ $FAIL failure(s) detected. Combined flag interaction has bugs."
elif [ "$WARN" -gt 0 ]; then
  VERDICT="⚠️  $WARN warning(s). Core functionality OK but some edge cases need attention."
fi

mkdir -p "$RESULT_DIR"
cat > "$RESULT_FILE" <<RESULT
# T28 — Combined flags interaction
**Date:** $(date '+%Y-%m-%d %H:%M')
**Duration:** ~60–90s

## Summary
- **Pass:** $PASS
- **Warn:** $WARN
- **Fail:** $FAIL
- **Total:** $TOTAL

## What was tested
- Phase 1: \`--thinking minimal + --json\` — JSON valid, elapsed_ms positive, sentinel returned
- Phase 2: \`--session + --json\` — JSON 'session' key matches --session arg
- Phase 3: \`--context + --quiet\` — no banner on stdout, context injected
- Phase 4: \`--thinking + --session + --quiet\` (3-flag combo) — no crash, response correct, quiet honored
- Phase 5: Flag-order independence — flags before vs. after message arg
- Phase 6: \`--json + 2x --context\` — context_files=2, both files referenced
- Phase 7: Source audit — boolean flags (--quiet, --json) don't consume next arg with shift 2

## Verdict
$VERDICT
RESULT

echo ""
echo "═══════════════════════════════════════"
echo " T28 Summary: $PASS pass / $WARN warn / $FAIL fail (of $TOTAL)"
echo " $VERDICT"
echo " Result: $RESULT_FILE"
echo "═══════════════════════════════════════"
echo ""

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
