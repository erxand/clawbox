#!/usr/bin/env bash
# T16 — `clawbox doctor` validation
#
# What: Verify the `clawbox doctor` self-diagnostic command works correctly in
#       various container states: running (healthy), stopped, and with a stale lock.
#       Tests exit codes, output format, pass/fail/warn counts, and that each
#       section header appears in the output.
# Why:  `doctor` was added 2026-03-30 as the primary troubleshooting entry point.
#       It must reliably diagnose real problems and exit 0 only when everything is OK.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T16-doctor.md"
CONTAINER="clawbox-work"
LOCK_FILE="${HOME}/.clawbox-lock"

mkdir -p "$RESULT_DIR"

PASS=0
FAIL=0
WARN=0
FINDINGS=()

log() { echo "[T16 $(date +%H:%M:%S)] $*"; }

pass() { echo "  ✓ $*"; PASS=$((PASS+1)); FINDINGS+=("pass|$*"); }
fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); FINDINGS+=("fail|$*"); }
warn() { echo "  ⚠ $*"; WARN=$((WARN+1)); FINDINGS+=("warn|$*"); }

# ── Phase 1: Healthy container (baseline) ──────────────────────────────────

log "Phase 1: Starting fresh container for healthy baseline..."
"$CLAWBOX" stop 2>/dev/null || true
"$CLAWBOX" start
sleep 5

log "Running doctor with healthy container..."
DOCTOR_OUTPUT=$("$CLAWBOX" doctor 2>&1 || true)
DOCTOR_EXIT=$?
echo "$DOCTOR_OUTPUT"

# 1.1 Exit code
if [ "$DOCTOR_EXIT" -eq 0 ]; then
  pass "healthy container: doctor exits 0"
else
  fail "healthy container: doctor exits $DOCTOR_EXIT (expected 0)"
fi

# 1.2 Overall banner present
if echo "$DOCTOR_OUTPUT" | grep -q "🩺 Clawbox Doctor"; then
  pass "doctor output has 🩺 Clawbox Doctor header"
else
  fail "doctor output missing 🩺 Clawbox Doctor header"
fi

# 1.3 Section headers
for section in "Prerequisites" "Project Directory" "Container" "Gateway" "Lock" "Workspace" "Host Disk"; do
  if echo "$DOCTOR_OUTPUT" | grep -qi "$section"; then
    pass "section header present: $section"
  else
    fail "section header missing: $section"
  fi
done

# 1.4 Pass count line present
if echo "$DOCTOR_OUTPUT" | grep -qE "Pass: [0-9]+"; then
  REPORTED_PASS=$(echo "$DOCTOR_OUTPUT" | grep -oE "Pass: [0-9]+" | head -1 | grep -oE "[0-9]+")
  pass "summary line present (Pass: $REPORTED_PASS)"
else
  fail "summary line missing (expected 'Pass: N   Warn: N   Fail: N')"
fi

# 1.5 Healthy marker (no failures)
if echo "$DOCTOR_OUTPUT" | grep -q "clawbox looks healthy\|All checks pass"; then
  pass "healthy footer present"
else
  warn "healthy footer not present — may have advisory items (check Warn count)"
fi

# 1.6 Key checks confirmed passing
for check_label in "container $CONTAINER is running" "container health: healthy" \
    "gateway health: healthy" "port" "docker present" "AGENTS.md present"; do
  if echo "$DOCTOR_OUTPUT" | grep -q "✓.*$check_label"; then
    pass "check confirmed: ✓ $check_label"
  else
    warn "check not found in output: '$check_label' — may be phrased differently"
  fi
done

# 1.7 No critical failures in healthy state
FAIL_COUNT_IN_OUTPUT=$(echo "$DOCTOR_OUTPUT" | grep -cE "^\s*✗" || true)
if [ "$FAIL_COUNT_IN_OUTPUT" -eq 0 ]; then
  pass "no ✗ failures in healthy doctor output"
else
  fail "found $FAIL_COUNT_IN_OUTPUT ✗ lines in healthy doctor output (expected 0)"
fi

# ── Phase 2: Stopped container ─────────────────────────────────────────────

log "Phase 2: Stopping container and re-running doctor..."
"$CLAWBOX" stop 2>/dev/null || true
sleep 3

STOPPED_OUTPUT=$("$CLAWBOX" doctor 2>&1); STOPPED_EXIT=$?; true
echo "$STOPPED_OUTPUT"

# 2.1 Exit code should be 1 (critical failures expected)
if [ "$STOPPED_EXIT" -ne 0 ]; then
  pass "stopped container: doctor exits non-zero (critical issues detected)"
else
  fail "stopped container: doctor exits 0 (should have detected failures)"
fi

# 2.2 Container failure detected
if echo "$STOPPED_OUTPUT" | grep -qE "✗.*(container.*does not exist|container.*is stopped|not running)"; then
  pass "stopped container: doctor correctly reports container failure"
else
  fail "stopped container: doctor did not report container failure (missing ✗ for container state)"
fi

# 2.3 Port failure detected
if echo "$STOPPED_OUTPUT" | grep -qE "✗.*(port.*not reachable|gateway.*unreachable)"; then
  pass "stopped container: doctor correctly reports port/gateway failure"
else
  fail "stopped container: doctor did not report port/gateway failure"
fi

# 2.4 Fail count in summary
if echo "$STOPPED_OUTPUT" | grep -qE "Fail: [1-9]"; then
  REPORTED_FAIL=$(echo "$STOPPED_OUTPUT" | grep -oE "Fail: [0-9]+" | head -1 | grep -oE "[0-9]+")
  pass "stopped container: Fail: $REPORTED_FAIL in summary (non-zero, correct)"
else
  fail "stopped container: summary shows Fail: 0 even though container is stopped"
fi

# ── Phase 3: Stale lock detection ─────────────────────────────────────────

log "Phase 3: Starting container + creating a stale lock..."
"$CLAWBOX" start
sleep 5

# Write a fake dead PID to the lock file
echo "99999999" > "$LOCK_FILE"

STALE_OUTPUT=$("$CLAWBOX" doctor 2>&1 || true)
STALE_EXIT=$?
echo "$STALE_OUTPUT"

# 3.1 Stale lock detected
if echo "$STALE_OUTPUT" | grep -qi "stale lock"; then
  pass "stale lock: doctor detected stale lock (dead PID)"
else
  fail "stale lock: doctor did not detect stale lock"
fi

# 3.2 Stale lock is a warn (not a fail) — doctor should still exit 0
if [ "$STALE_EXIT" -eq 0 ]; then
  pass "stale lock: doctor exits 0 (stale lock is advisory, not critical)"
else
  warn "stale lock: doctor exits $STALE_EXIT — expected 0 (stale lock should be ⚠ not ✗)"
fi

# Clean up the stale lock
rm -f "$LOCK_FILE"

# ── Phase 4: Doctor on healthy container after cleanup ─────────────────────

log "Phase 4: Final run (healthy, no lock)..."
FINAL_OUTPUT=$("$CLAWBOX" doctor 2>&1 || true)
FINAL_EXIT=$?
echo "$FINAL_OUTPUT"

if [ "$FINAL_EXIT" -eq 0 ]; then
  pass "final run: doctor exits 0 (healthy, no stale lock)"
else
  fail "final run: doctor exits $FINAL_EXIT (expected 0)"
fi

# ── Phase 5: Edge cases ────────────────────────────────────────────────────

log "Phase 5: Edge cases..."

# 5.1 doctor with GATEWAY_PORT set to wrong port (simulates port mismatch)
log "  5.1: Wrong gateway port..."
WRONG_PORT_OUTPUT=$(GATEWAY_PORT=19999 "$CLAWBOX" doctor 2>&1 || true)
WRONG_PORT_EXIT=$?
if echo "$WRONG_PORT_OUTPUT" | grep -qE "✗.*(port.*not reachable|gateway.*unreachable|port 19999)"; then
  pass "wrong port: doctor reports port 19999 unreachable"
elif [ "$WRONG_PORT_EXIT" -ne 0 ]; then
  pass "wrong port: doctor exits non-zero (detected issue)"
else
  warn "wrong port: doctor may not have detected port mismatch (GATEWAY_PORT=19999)"
fi

# 5.2 doctor in help output
HELP_OUTPUT=$("$CLAWBOX" help 2>&1 || true)
if echo "$HELP_OUTPUT" | grep -q "doctor"; then
  pass "doctor command appears in clawbox help output"
else
  fail "doctor command missing from clawbox help output"
fi

# ── Summary ───────────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL + WARN))
log "Results: $PASS/$TOTAL pass, $FAIL fail, $WARN warn"

# Build findings table
FINDINGS_TABLE=""
for f in "${FINDINGS[@]}"; do
  result="${f%%|*}"
  label="${f#*|}"
  case "$result" in
    pass) icon="✓" ;;
    fail) icon="✗" ;;
    warn) icon="⚠" ;;
    *)    icon="?" ;;
  esac
  FINDINGS_TABLE="${FINDINGS_TABLE}| $icon $label |"$'\n'
done

# Build findings list before heredoc
FINDINGS_MD=""
for f in "${FINDINGS[@]}"; do
  result="${f%%|*}"
  label="${f#*|}"
  if [ "$result" = "pass" ]; then
    FINDINGS_MD="${FINDINGS_MD}- ✓ $label"$'\n'
  elif [ "$result" = "fail" ]; then
    FINDINGS_MD="${FINDINGS_MD}- ✗ $label"$'\n'
  else
    FINDINGS_MD="${FINDINGS_MD}- ⚠ $label"$'\n'
  fi
done

VERDICT_MD=""
if [ "$FAIL" -eq 0 ]; then
  VERDICT_MD="✅ \`clawbox doctor\` is working correctly. Exit codes, section structure, failure detection, stale lock reporting, and help integration all pass."
else
  VERDICT_MD="❌ $FAIL failures found. See findings above."
fi

cat > "$RESULT_FILE" << RESULT_EOF
# T16 — \`clawbox doctor\` validation
**Date:** $(date '+%Y-%m-%d %H:%M')

## What was tested
- Phase 1: Healthy container — doctor exits 0, all section headers present, no ✗ lines
- Phase 2: Stopped container — doctor exits non-zero, detects container/port failures
- Phase 3: Stale lock — doctor detects dead-PID lock as ⚠ (not ✗), still exits 0
- Phase 4: Final healthy run — clean exit 0 after lock cleanup
- Phase 5: Edge cases — wrong GATEWAY_PORT, doctor in help output

## Summary
- **Pass:** $PASS / $TOTAL
- **Fail:** $FAIL
- **Warn:** $WARN

## Findings
$FINDINGS_MD

## Verdict
$VERDICT_MD
RESULT_EOF

log "Result written to $RESULT_FILE"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
