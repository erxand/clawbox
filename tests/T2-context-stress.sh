#!/usr/bin/env bash
# T2 — Context window stress test
#
# What: Give the agent a real OSS codebase (100+ files) and ask it to
#       understand the structure and make a targeted change.
# Why:  Large codebases push context windows hard. Does the agent navigate
#       intelligently (grepping, targeting) or try to read everything and
#       fail? Does it hallucinate paths that don't exist?
# Good: Agent reads selectively, makes correct targeted change, tests pass.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T2-context-stress.md"
CONTAINER="clawbox-work"
TIMEOUT_SECONDS=600  # 10 minutes
WORKSPACE="/home/node/.openclaw/workspace"

mkdir -p "$RESULT_DIR"

log() { echo "[T2 $(date +%H:%M:%S)] $*"; }

# ── Setup ───────────────────────────────────────────────────────────

log "Checking container is running..."
RUNNING=$(docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null || echo "false")
if [ "$RUNNING" != "true" ]; then
  log "Starting container..."
  "$CLAWBOX" start
  sleep 5
fi

# Clean stale express-oss and onboarding-test directories from prior T2/T5 runs
# (ISSUE-59: agent finds pre-existing stats() code in old dirs and skips writing new code)
log "Cleaning stale workspace artifacts from prior T2 runs..."
docker exec "$CONTAINER" sh -c "
  cd $WORKSPACE
  REMOVED=0
  for d in express-oss express-oss-* onboarding-test; do
    if [ -d \"\$d\" ]; then
      rm -rf \"\$d\"
      echo \"  removed \$d\"
      REMOVED=\$((REMOVED + 1))
    fi
  done
  echo \"Cleaned \$REMOVED stale directories\"
"

# Clone a medium-sized OSS project on the HOST (egress proxy blocks GitHub inside container)
# then copy it into the container workspace
log "Setting up large codebase..."
EXPRESS_DIR="express-oss-${TIMESTAMP//[-:]/-}"
CLONE_TMP="/tmp/t2-${EXPRESS_DIR}"

# Clone on host (has unrestricted internet)
if [ -d "$CLONE_TMP" ]; then rm -rf "$CLONE_TMP"; fi
log "Cloning express on host into $CLONE_TMP..."
git clone --depth=1 https://github.com/expressjs/express "$CLONE_TMP" 2>&1 | tail -5

# Copy into container workspace
log "Copying into container as $EXPRESS_DIR..."
docker cp "$CLONE_TMP" "${CONTAINER}:${WORKSPACE}/${EXPRESS_DIR}"
docker exec -u root "$CONTAINER" sh -c "chown -R node:node $WORKSPACE/$EXPRESS_DIR"
rm -rf "$CLONE_TMP"

docker exec "$CONTAINER" sh -c "
  echo 'Files in $EXPRESS_DIR:'
  find $WORKSPACE/$EXPRESS_DIR -type f -name '*.js' | grep -v node_modules | wc -l
"

FILE_COUNT=$(docker exec "$CONTAINER" sh -c "find $WORKSPACE/$EXPRESS_DIR -type f -name '*.js' 2>/dev/null | grep -v node_modules | wc -l" | tr -d ' ')
log "Codebase has $FILE_COUNT JS files (source only, excluding node_modules)"

# ── Send task ───────────────────────────────────────────────────────

TASK_MSG="I've cloned the Express.js framework source code into ~/$EXPRESS_DIR in your workspace. Work ONLY inside the ~/$EXPRESS_DIR directory — do not use or reference any other express/onboarding directories in the workspace. WITHOUT reading every file, figure out: (1) Where are the core routing files in the Express source (hint: look in lib/, not node_modules/)? (2) What does Express's own Router class look like? (3) Add a NEW \`router.stats()\` method to Express's own Router class (in lib/router/, NOT in node_modules/router/ which is a vendored dependency). The method should return an object with the count of registered routes and middleware. Write a test for it in a new file called test-router-stats.js inside the ~/$EXPRESS_DIR directory, and run that test. Only read files you need — be selective."

log "Sending context-stress task..."
START_TIME=$(date +%s)
OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw agent --agent main -m "$TASK_MSG" > /tmp/t2-output.txt 2>&1 &
AGENT_PID=$!

# Wait for agent to finish or timeout
ELAPSED=0
while kill -0 "$AGENT_PID" 2>/dev/null && [ "$ELAPSED" -lt "$TIMEOUT_SECONDS" ]; do
  sleep 15
  ELAPSED=$(( $(date +%s) - START_TIME ))
  log "Still running... ${ELAPSED}s elapsed"
done

if kill -0 "$AGENT_PID" 2>/dev/null; then
  log "TIMEOUT — killing agent process"
  kill "$AGENT_PID" 2>/dev/null || true
  TIMED_OUT="yes"
else
  TIMED_OUT="no"
fi

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

# ── Verify results ──────────────────────────────────────────────────

log "Checking what was produced..."

# Did agent create the test file?
TEST_FILE_EXISTS=$(docker exec "$CONTAINER" sh -c "test -f $WORKSPACE/test-router-stats.js && echo yes || echo no" 2>/dev/null || echo "no")

# Did it create the file in the express dir?
TEST_FILE_ALT=$(docker exec "$CONTAINER" sh -c "test -f $WORKSPACE/$EXPRESS_DIR/test-router-stats.js && echo yes || echo no" 2>/dev/null || echo "no")

# Find test file anywhere in workspace
TEST_FILE_LOCATION=$(docker exec "$CONTAINER" sh -c "find $WORKSPACE -name 'test-router-stats.js' 2>/dev/null | head -3" 2>/dev/null || echo "")

# KEY CHECK: Was stats() added to the CORRECT file (Express lib/router) or vendored dep (node_modules/router)?
STATS_IN_LIB=$(docker exec "$CONTAINER" sh -c "grep -l 'stats' $WORKSPACE/$EXPRESS_DIR/lib/router/*.js 2>/dev/null || echo ''" 2>/dev/null | tr '\n' ' ')
STATS_IN_NODE_MODULES=$(docker exec "$CONTAINER" sh -c "grep -l 'stats' $WORKSPACE/$EXPRESS_DIR/node_modules/router/*.js 2>/dev/null || echo ''" 2>/dev/null | tr '\n' ' ')
# Also check for .stats method (more precise)
STATS_METHOD_IN_LIB=$(docker exec "$CONTAINER" sh -c "grep -rc '\.stats\s*=\|prototype\.stats' $WORKSPACE/$EXPRESS_DIR/lib/ 2>/dev/null | grep -v ':0' | head -5 || echo ''" 2>/dev/null)
STATS_METHOD_IN_MODULES=$(docker exec "$CONTAINER" sh -c "grep -rc '\.stats\s*=\|prototype\.stats' $WORKSPACE/$EXPRESS_DIR/node_modules/ 2>/dev/null | grep -v ':0' | head -5 || echo ''" 2>/dev/null)

# Did it run the test? (look for test pass/fail in agent output)
AGENT_OUTPUT=$(cat /tmp/t2-output.txt 2>/dev/null | tail -60)
TEST_PASSED=$(echo "$AGENT_OUTPUT" | grep -ci "pass\|✓\|success\|ok" || true)
TEST_FAILED=$(echo "$AGENT_OUTPUT" | grep -ci "fail\|error\|✗" || true)

# How many files did agent read? (rough proxy for selectivity)
# (We can check docker logs or gateway logs for tool calls)
GATEWAY_LOG=$(docker exec "$CONTAINER" sh -c "tail -200 /tmp/openclaw/openclaw-\$(date +%Y-%m-%d).log 2>/dev/null | grep -c 'read_file\|ReadFile' || echo 0" 2>/dev/null || echo "unknown")

# ── Write results ───────────────────────────────────────────────────

cat > "$RESULT_FILE" << RESULT_EOF
# T2 — Context window stress test
**Date:** $(date '+%Y-%m-%d %H:%M')
**Duration:** ${ELAPSED}s (~$((ELAPSED / 60)) min)
**Timed out:** $TIMED_OUT

## What was tested
Agent was given the Express.js source (~$FILE_COUNT JS files) and asked to:
1. Navigate the codebase selectively (not read everything)
2. Understand the Router class
3. Add a \`router.stats()\` method
4. Write and run a test for it

## Results

| Metric | Value |
|--------|-------|
| Duration | ${ELAPSED}s |
| Timed out | $TIMED_OUT |
| test-router-stats.js created (workspace root) | $TEST_FILE_EXISTS |
| test-router-stats.js created ($EXPRESS_DIR/) | $TEST_FILE_ALT |
| test-router-stats.js path(s) | $TEST_FILE_LOCATION |
| stats() added to lib/router/ (CORRECT) | ${STATS_IN_LIB:-none} |
| stats() added to node_modules/router/ (WRONG) | ${STATS_IN_NODE_MODULES:-none} |
| stats method in lib/ (precise check) | ${STATS_METHOD_IN_LIB:-none} |
| stats method in node_modules/ (precise) | ${STATS_METHOD_IN_MODULES:-none} |
| Keyword hits (pass/success) in output | $TEST_PASSED |
| Keyword hits (fail/error) in output | $TEST_FAILED |
| Approx read_file calls (recent log) | $GATEWAY_LOG |

## Assessment
$([ "$TEST_FILE_EXISTS" = "yes" ] || [ "$TEST_FILE_ALT" = "yes" ] || [ -n "$TEST_FILE_LOCATION" ] && echo "✓ Test file created" || echo "✗ Test file NOT created")
$([ -n "$STATS_METHOD_IN_LIB" ] && echo "✓ stats() added to CORRECT file (Express lib/router/)" || echo "⚠ stats() NOT found in Express lib/router/ (check node_modules)")
$([ -n "$STATS_METHOD_IN_MODULES" ] && echo "⚠ stats() found in node_modules/router/ (WRONG FILE — vendored dep, not Express source)" || echo "✓ node_modules/router/ not modified (correct)")
$([ "$TIMED_OUT" = "no" ] && echo "✓ Completed within timeout" || echo "✗ Timed out — agent may have gotten stuck reading too many files")

## Agent output (tail)
\`\`\`
$AGENT_OUTPUT
\`\`\`

## Files created by agent
\`\`\`
$(docker exec "$CONTAINER" sh -c "find $WORKSPACE/$EXPRESS_DIR -newer $WORKSPACE/$EXPRESS_DIR/package.json -type f 2>/dev/null | grep -v '.git' | grep -v node_modules | head -20" 2>/dev/null || echo "(could not list)")
\`\`\`
RESULT_EOF

log "Results written to $RESULT_FILE"
log "Done."
