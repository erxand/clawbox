#!/usr/bin/env bash
# T7 — UX / Friction audit
#
# What: Simulates the experience of a new developer going from zero to running a real task.
#       Measures: startup time, help output quality, error message clarity, first-task latency.
# Why:  The "time to value" and friction points are the #1 reason people abandon CLI tools.
# Pass: Each friction item is scored. Report gives concrete actionable improvements.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T7-ux-friction.md"
CONTAINER="clawbox-work"

mkdir -p "$RESULT_DIR"

log() { echo "[T7 $(date +%H:%M:%S)] $*"; }
PASS=0
FAIL=0
WARN=0
FINDINGS=()

check() {
  local label="$1"
  local result="$2"   # pass|fail|warn
  local detail="$3"
  FINDINGS+=("$result|$label|$detail")
  if [ "$result" = "pass" ]; then
    PASS=$((PASS+1))
    echo "  ✓ $label"
  elif [ "$result" = "warn" ]; then
    WARN=$((WARN+1))
    echo "  ⚠ $label — $detail"
  else
    FAIL=$((FAIL+1))
    echo "  ✗ $label — $detail"
  fi
}

# ── Phase 1: Help & Discoverability ──────────────────────────────────────────

log "Phase 1: Help & discoverability..."

HELP_OUTPUT=$("$CLAWBOX" help 2>&1 || true)

# Does help output exist?
if echo "$HELP_OUTPUT" | grep -q "Usage:"; then
  check "help command exits without error" "pass" "clawbox help runs cleanly"
else
  check "help command exits without error" "fail" "clawbox help missing Usage: section"
fi

# Are all common commands listed?
for cmd in start stop restart status logs chat run ask task task-status task-logs cancel shell backup restore upgrade clean; do
  if echo "$HELP_OUTPUT" | grep -q "^  $cmd"; then
    check "help lists '$cmd'" "pass" ""
  else
    check "help lists '$cmd'" "fail" "'$cmd' not in help output"
  fi
done

# Does help mention the CLAWBOX_DIR env var?
if echo "$HELP_OUTPUT" | grep -q "CLAWBOX_DIR"; then
  check "help mentions CLAWBOX_DIR env var" "pass" ""
else
  check "help mentions CLAWBOX_DIR env var" "warn" "CLAWBOX_DIR not mentioned in help — users won't know how to use the installed binary"
fi

# ── Phase 2: Error message quality ────────────────────────────────────────────

log "Phase 2: Error message quality..."

# What happens when you call 'run' with no args?
RUN_NOARG=$("$CLAWBOX" run 2>&1 || true)
if echo "$RUN_NOARG" | grep -qi "usage\|message"; then
  check "run with no args shows usage" "pass" ""
else
  check "run with no args shows usage" "fail" "Output: $(echo "$RUN_NOARG" | head -3)"
fi

# What happens when you call 'task' with no args?
TASK_NOARG=$("$CLAWBOX" task 2>&1 || true)
if echo "$TASK_NOARG" | grep -qi "usage\|description"; then
  check "task with no args shows usage" "pass" ""
else
  check "task with no args shows usage" "fail" "Output: $(echo "$TASK_NOARG" | head -3)"
fi

# What happens when you call 'cp' with missing args?
CP_NOARG=$("$CLAWBOX" cp 2>&1 || true)
if echo "$CP_NOARG" | grep -qi "usage"; then
  check "cp with no args shows usage" "pass" ""
else
  check "cp with no args shows usage" "fail" "Output: $(echo "$CP_NOARG" | head -3)"
fi

# What happens with an unknown command?
UNKNOWN=$("$CLAWBOX" nonexistent_cmd 2>&1 || true)
if echo "$UNKNOWN" | grep -qi "unknown\|help"; then
  check "unknown command shows helpful message" "pass" ""
else
  check "unknown command shows helpful message" "fail" "Output: $(echo "$UNKNOWN" | head -3)"
fi

# What happens when container is not running and you call 'run'?
STOP_OUTPUT=$("$CLAWBOX" stop 2>&1 || true)
sleep 2
RUN_NOSVC=$("$CLAWBOX" run "hello" 2>&1 || true)
if echo "$RUN_NOSVC" | grep -qi "warning\|not running\|start"; then
  check "run with container stopped shows clear warning" "pass" ""
else
  check "run with container stopped shows clear warning" "fail" "Got: $(echo "$RUN_NOSVC" | head -3)"
fi

# What happens when chat is called without container?
CHAT_NOSVC=$("$CLAWBOX" chat 2>&1 || true)
if echo "$CHAT_NOSVC" | grep -qi "warning\|not running\|start"; then
  check "chat with container stopped shows clear warning" "pass" ""
else
  check "chat with container stopped shows clear warning" "fail" "Got: $(echo "$CHAT_NOSVC" | head -3)"
fi

# ── Phase 3: Startup time & first-task latency ───────────────────────────────

log "Phase 3: Startup time..."

# Time from zero to healthy
START_BEGIN=$(date +%s)
"$CLAWBOX" start
START_END=$(date +%s)
START_TIME=$((START_END - START_BEGIN))

if [ $START_TIME -le 15 ]; then
  check "container starts in ≤15s (warm image)" "pass" "${START_TIME}s"
elif [ $START_TIME -le 30 ]; then
  check "container starts in ≤30s" "warn" "${START_TIME}s — slightly slow, may frustrate new users"
else
  check "container starts in ≤30s" "fail" "${START_TIME}s — too slow for first-run impression"
fi

# Wait until healthy
log "Waiting for healthy..."
for i in $(seq 1 30); do
  STATUS=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
  if [ "$STATUS" = "healthy" ]; then break; fi
  sleep 2
done

STATUS=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
if [ "$STATUS" = "healthy" ]; then
  check "container reaches healthy state" "pass" ""
else
  check "container reaches healthy state" "fail" "Status: $STATUS after 60s wait"
fi

# ── Phase 4: First real task latency ─────────────────────────────────────────

log "Phase 4: First task latency..."

# Simplest possible task — what is the agent?
TASK_START=$(date +%s)
FIRST_RESPONSE=$(OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw agent --agent main -m "Reply PING_OK and nothing else." 2>&1 || true)
TASK_END=$(date +%s)
FIRST_TASK_TIME=$((TASK_END - TASK_START))

if echo "$FIRST_RESPONSE" | grep -qi "PING_OK"; then
  check "first task responds correctly" "pass" "Response correct in ${FIRST_TASK_TIME}s"
else
  check "first task responds correctly" "fail" "Expected PING_OK, got: $(echo "$FIRST_RESPONSE" | tail -5)"
fi

if [ $FIRST_TASK_TIME -le 30 ]; then
  check "first task completes in ≤30s" "pass" "${FIRST_TASK_TIME}s"
elif [ $FIRST_TASK_TIME -le 60 ]; then
  check "first task completes in ≤60s" "warn" "${FIRST_TASK_TIME}s — perceptibly slow for new user's first interaction"
else
  check "first task completes in ≤60s" "fail" "${FIRST_TASK_TIME}s — too slow, will frustrate users"
fi

# ── Phase 5: Status command quality ──────────────────────────────────────────

log "Phase 5: Status output quality..."

STATUS_OUTPUT=$("$CLAWBOX" status 2>&1 || true)

if echo "$STATUS_OUTPUT" | grep -qi "running\|healthy\|up"; then
  check "status shows container running state" "pass" ""
else
  check "status shows container running state" "fail" "Status output unclear: $(echo "$STATUS_OUTPUT" | head -5)"
fi

if echo "$STATUS_OUTPUT" | grep -qi "gateway.*healthy\|healthy.*gateway"; then
  check "status shows gateway health" "pass" ""
else
  check "status shows gateway health" "warn" "Gateway health not obvious in status output"
fi

# Does status tell you how to connect?
if echo "$STATUS_OUTPUT" | grep -qi "18790\|localhost\|gateway"; then
  check "status mentions connection endpoint" "pass" ""
else
  check "status mentions connection endpoint" "warn" "Status doesn't show ws:// endpoint — new users won't know how to connect"
fi

# ── Phase 6: README accuracy checks ──────────────────────────────────────────

log "Phase 6: README accuracy spot-checks..."

README="${SCRIPT_DIR}/../README.md"

# Does README mention OPENCLAW_GATEWAY_TOKEN requirement?
if grep -q "OPENCLAW_GATEWAY_TOKEN" "$README"; then
  check "README documents OPENCLAW_GATEWAY_TOKEN" "pass" ""
else
  check "README documents OPENCLAW_GATEWAY_TOKEN" "fail" "New users will hit 'token required' errors with no guidance"
fi

# Does README mention the clawbox CLI?
if grep -q "clawbox run\|clawbox chat\|clawbox start" "$README"; then
  check "README mentions clawbox CLI commands" "pass" ""
else
  check "README mentions clawbox CLI commands" "warn" "README only shows raw openclaw commands, not the clawbox wrapper"
fi

# Is there a troubleshooting section?
if grep -qi "troubleshoot" "$README"; then
  check "README has troubleshooting section" "pass" ""
else
  check "README has troubleshooting section" "warn" "No troubleshooting section — first issues will feel like dead ends"
fi

# Does README explain auth=none / token being irrelevant?
if grep -q "auth=none\|value doesn.t matter\|value is ignored" "$README"; then
  check "README explains why token value doesn't matter" "pass" ""
else
  check "README explains why token value doesn't matter" "warn" "New users may be confused about OPENCLAW_GATEWAY_TOKEN value"
fi

# ── Phase 7: Quality-of-life gaps ──────────────────────────────────────────

log "Phase 7: Quality-of-life gaps..."

# Does 'clawbox status' show the ws:// URL to copy?
if echo "$STATUS_OUTPUT" | grep -q "ws://"; then
  check "status shows ws:// URL for copy-paste" "pass" ""
else
  check "status shows ws:// URL for copy-paste" "warn" "Showing ws://localhost:18790 in status would save users a trip to README"
fi

# Is there a 'version' or similar info command?
VERSION_OUT=$("$CLAWBOX" version 2>&1 || true)
if echo "$VERSION_OUT" | grep -qvi "unknown command"; then
  check "version command exists" "pass" ""
else
  check "version command exists" "warn" "No 'clawbox version' — users can't tell what they're running"
fi

# Does the CLI have a short alias for run (like 'ask')?
if grep -qE "^\s+ask\)" "${SCRIPT_DIR}/../clawbox" || grep -q "cmd_ask" "${SCRIPT_DIR}/../clawbox"; then
  check "short alias 'ask' exists for run" "pass" ""
else
  check "short alias 'ask' exists for run" "warn" "'clawbox run' is verbose; 'clawbox ask' would feel more natural"
fi

# Does clawbox-connect exist for easy env setup?
if [ -f "${SCRIPT_DIR}/../.clawbox-connect" ]; then
  check ".clawbox-connect exists for env setup" "pass" ""
else
  check ".clawbox-connect exists for env setup" "warn" "No .clawbox-connect helper; users must manually set OPENCLAW_GATEWAY_URL"
fi

# ── Write results ──────────────────────────────────────────────────────────

TOTAL=$((PASS+FAIL+WARN))

{
cat << EOF
# T7 — UX Friction Audit
**Date:** $(date '+%Y-%m-%d %H:%M')
**Container start time:** ${START_TIME}s
**First task latency:** ${FIRST_TASK_TIME}s

## Score
- ✓ Pass: ${PASS}
- ⚠ Warn: ${WARN}
- ✗ Fail: ${FAIL}
- Total checks: ${TOTAL}

## Findings

EOF

for item in "${FINDINGS[@]}"; do
  result="${item%%|*}"
  rest="${item#*|}"
  label="${rest%%|*}"
  detail="${rest#*|}"
  if [ "$result" = "pass" ]; then
    echo "- ✓ **${label}**"
  elif [ "$result" = "warn" ]; then
    echo "- ⚠ **${label}** — ${detail}"
  else
    echo "- ✗ **${label}** — ${detail}"
  fi
done

cat << EOF

## Friction Breakdown

### Startup
- Container start time: ${START_TIME}s
- Time to first agent response (after healthy): ${FIRST_TASK_TIME}s

### Help / Discoverability
$(echo "$HELP_OUTPUT" | head -30)

### Status Output
\`\`\`
$(echo "$STATUS_OUTPUT" | head -20)
\`\`\`

## Top UX Recommendations
Based on audit findings, the highest-impact improvements are:
EOF

# Print only warn/fail items as recommendations
for item in "${FINDINGS[@]}"; do
  result="${item%%|*}"
  rest="${item#*|}"
  label="${rest%%|*}"
  detail="${rest#*|}"
  if [ "$result" = "warn" ] || [ "$result" = "fail" ]; then
    echo "- **$label**: $detail"
  fi
done

} > "$RESULT_FILE"

log "Results written to $RESULT_FILE"
log ""
log "Summary: ${PASS} pass, ${WARN} warn, ${FAIL} fail (of ${TOTAL} checks)"
log "Done."
