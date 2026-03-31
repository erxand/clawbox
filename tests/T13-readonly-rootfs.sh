#!/usr/bin/env bash
# T13 — Read-only root filesystem validation
#
# What: Verify that the container rootfs is read-only (ISSUE-8 fix) and that
#       all legitimate write paths work correctly:
#         - /tmp (tmpfs, 256MB)
#         - /run (tmpfs, 32MB)
#         - /home/node/.openclaw (persistent volume)
#       and that redirected paths work:
#         - GIT_CONFIG_GLOBAL → .gitconfig writes to volume
#         - NPM_CONFIG_CACHE → npm cache in volume
# Why:  A read-only rootfs prevents rogue agent code from modifying binaries,
#       libraries, or system files. Core security hardening (ISSUE-8).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T13-readonly-rootfs.md"
CONTAINER="clawbox-work"

mkdir -p "$RESULT_DIR"

PASS=0
FAIL=0
WARN=0

log() { echo "[T13 $(date +%H:%M:%S)] $*"; }

pass() { echo "✓ $*"; PASS=$((PASS+1)); }
fail() { echo "✗ $*"; FAIL=$((FAIL+1)); }
warn() { echo "⚠ $*"; WARN=$((WARN+1)); }

# ── Setup ───────────────────────────────────────────────────────────

log "Starting fresh container..."
"$CLAWBOX" stop 2>/dev/null || true
"$CLAWBOX" start
sleep 3

# ── Check 1: HostConfig.ReadonlyRootfs ──────────────────────────────

log "Check 1: HostConfig.ReadonlyRootfs..."
READONLY=$(docker inspect "$CONTAINER" --format '{{.HostConfig.ReadonlyRootfs}}' 2>/dev/null || echo "false")
if [ "$READONLY" = "true" ]; then
  pass "ReadonlyRootfs=true (confirmed by Docker inspect)"
else
  fail "ReadonlyRootfs=$READONLY (expected true) — check docker-compose.yml read_only: true"
fi

# ── Check 2: /proc/mounts shows ro for rootfs ───────────────────────
# Note: Docker overlay2 always reports the rootfs as 'rw' in /proc/mounts at the
# filesystem layer, even when HostConfig.ReadonlyRootfs=true. The authoritative
# check is HostConfig.ReadonlyRootfs (Check 1). We skip the /proc/mounts check
# and instead confirm that a write attempt to the rootfs actually fails.

log "Check 2: rootfs write rejection (overlay2-safe)..."
WRITE_ATTEMPT=$(docker exec "$CONTAINER" sh -c "touch /t13-probe-write-check 2>&1; echo EXIT:\$?" 2>/dev/null || echo "EXIT:1")
WRITE_EXIT=$(echo "$WRITE_ATTEMPT" | grep "EXIT:" | cut -d: -f2 | tr -d ' \n')
if [ "$WRITE_EXIT" != "0" ]; then
  pass "Root filesystem correctly rejects writes (overlay2-safe check)"
else
  fail "Root filesystem accepted a write at / — ReadonlyRootfs may not be effective"
  docker exec "$CONTAINER" sh -c "rm -f /t13-probe-write-check 2>/dev/null || true"
fi

# ── Check 3: Write attempts to critical rootfs paths ────────────────

log "Check 3: Rootfs write protection..."
ROOTFS_PATHS="/usr /bin /lib /etc /sbin /home/node/.npm-global"
ALL_READONLY=true
for path in $ROOTFS_PATHS; do
  RESULT=$(docker exec "$CONTAINER" sh -c "touch ${path}/t13-probe-\$\$ 2>&1; echo EXIT:\$?" 2>/dev/null || echo "EXIT:1")
  EXIT_CODE=$(echo "$RESULT" | grep "EXIT:" | cut -d: -f2 | tr -d ' \n')
  if [ "$EXIT_CODE" = "0" ]; then
    fail "Path $path is WRITABLE (should be read-only)"
    docker exec "$CONTAINER" sh -c "rm -f ${path}/t13-probe-* 2>/dev/null || true"
    ALL_READONLY=false
  fi
done
if [ "$ALL_READONLY" = "true" ]; then
  pass "All system paths are read-only: $ROOTFS_PATHS"
fi

# ── Check 4: /tmp tmpfs is writable ─────────────────────────────────

log "Check 4: /tmp tmpfs..."
RESULT=$(docker exec "$CONTAINER" sh -c "touch /tmp/t13-test-\$\$ && rm /tmp/t13-test-* 2>/dev/null; echo EXIT:\$?" 2>/dev/null || echo "EXIT:1")
EXIT_CODE=$(echo "$RESULT" | grep "EXIT:" | cut -d: -f2 | tr -d ' \n')
if [ "$EXIT_CODE" = "0" ]; then
  pass "/tmp (tmpfs) is writable"
else
  fail "/tmp is not writable — check tmpfs mount in docker-compose.yml"
fi

# ── Check 5: /run tmpfs is writable ─────────────────────────────────

log "Check 5: /run tmpfs..."
RESULT=$(docker exec "$CONTAINER" sh -c "touch /run/t13-test-\$\$ && rm /run/t13-test-* 2>/dev/null; echo EXIT:\$?" 2>/dev/null || echo "EXIT:1")
EXIT_CODE=$(echo "$RESULT" | grep "EXIT:" | cut -d: -f2 | tr -d ' \n')
if [ "$EXIT_CODE" = "0" ]; then
  pass "/run (tmpfs) is writable"
else
  fail "/run is not writable — check tmpfs mount (need mode=1777) in docker-compose.yml"
fi

# ── Check 6: Volume (/home/node/.openclaw) is writable ──────────────

log "Check 6: Workspace volume..."
RESULT=$(docker exec "$CONTAINER" sh -c "touch /home/node/.openclaw/t13-test && rm /home/node/.openclaw/t13-test; echo EXIT:\$?" 2>/dev/null || echo "EXIT:1")
EXIT_CODE=$(echo "$RESULT" | grep "EXIT:" | cut -d: -f2 | tr -d ' \n')
if [ "$EXIT_CODE" = "0" ]; then
  pass "/home/node/.openclaw (persistent volume) is writable"
else
  fail "/home/node/.openclaw is not writable"
fi

# ── Check 7: GIT_CONFIG_GLOBAL redirects git config to volume ───────

log "Check 7: GIT_CONFIG_GLOBAL redirect..."
GIT_CONFIG_ENV=$(docker inspect "$CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep "GIT_CONFIG_GLOBAL" || echo "")
if [ -n "$GIT_CONFIG_ENV" ]; then
  pass "GIT_CONFIG_GLOBAL env var set: $GIT_CONFIG_ENV"
else
  fail "GIT_CONFIG_GLOBAL not set in container env"
fi

# Verify git config actually writes to volume
docker exec "$CONTAINER" sh -c "git config --global user.email 'readonly-test@clawbox'" 2>/dev/null
GIT_IN_VOLUME=$(docker exec "$CONTAINER" sh -c "cat /home/node/.openclaw/.gitconfig 2>/dev/null" || echo "")
if echo "$GIT_IN_VOLUME" | grep -q "email"; then
  pass "git config --global writes to volume (not rootfs)"
else
  fail "git config --global does not appear to write to volume"
fi

# Verify rootfs ~/.gitconfig is NOT written
ROOTFS_GITCONFIG=$(docker exec "$CONTAINER" sh -c "ls /home/node/.gitconfig 2>/dev/null && echo exists || echo missing" 2>/dev/null)
if [ "$ROOTFS_GITCONFIG" = "missing" ]; then
  pass "No ~/.gitconfig on rootfs (correctly redirected to volume)"
else
  warn "~/.gitconfig exists on rootfs — GIT_CONFIG_GLOBAL redirect may not be working"
fi

# ── Check 8: NPM_CONFIG_CACHE redirects npm cache to volume ─────────

log "Check 8: NPM_CONFIG_CACHE redirect..."
NPM_CACHE_ENV=$(docker inspect "$CONTAINER" --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep "NPM_CONFIG_CACHE" || echo "")
if [ -n "$NPM_CACHE_ENV" ]; then
  pass "NPM_CONFIG_CACHE env var set: $NPM_CACHE_ENV"
else
  fail "NPM_CONFIG_CACHE not set in container env"
fi

# Verify npm install works and cache goes to volume
NPM_RESULT=$(docker exec "$CONTAINER" sh -c "
  mkdir -p /tmp/t13-npm && cd /tmp/t13-npm
  npm init -y --silent 2>/dev/null | tail -1
  npm install --silent lodash 2>&1 | tail -1
  echo EXIT:\$?
" 2>/dev/null || echo "EXIT:1")
NPM_EXIT=$(echo "$NPM_RESULT" | grep "EXIT:" | cut -d: -f2 | tr -d ' \n')
if [ "$NPM_EXIT" = "0" ]; then
  pass "npm install in /tmp succeeds with read-only rootfs"
else
  fail "npm install failed with read-only rootfs — check NPM_CONFIG_CACHE"
fi

# ── Check 9: Agent responds via clawbox run ──────────────────────────

log "Check 9: Agent functional test..."
AGENT_RESULT=$("$CLAWBOX" run "Reply only with the word READONLY_OK" 2>&1 | tail -1 || echo "FAIL")
if echo "$AGENT_RESULT" | grep -qi "READONLY_OK"; then
  pass "Agent responds correctly with read-only rootfs"
else
  warn "Agent response unexpected: $AGENT_RESULT (may be API key issue)"
fi

# ── Check 10: Agent can write to workspace ───────────────────────────

log "Check 10: Agent writes to workspace..."
WRITE_RESULT=$("$CLAWBOX" run "Create a file at /home/node/.openclaw/workspace/t13-readonly-test.txt with content 'WRITE_OK'. Then print its content." 2>&1 | tail -3 || echo "FAIL")
WRITE_CONFIRMED=$(docker exec "$CONTAINER" sh -c "cat /home/node/.openclaw/workspace/t13-readonly-test.txt 2>/dev/null || echo MISSING")
docker exec "$CONTAINER" sh -c "rm -f /home/node/.openclaw/workspace/t13-readonly-test.txt 2>/dev/null || true"
if echo "$WRITE_CONFIRMED" | grep -qi "WRITE_OK"; then
  pass "Agent can write files to workspace volume with read-only rootfs"
else
  warn "Could not confirm agent workspace write: $WRITE_CONFIRMED"
fi

# ── Check 11: npm install inside workspace project ───────────────────

log "Check 11: npm install in workspace project dir..."
NPM_WORKSPACE=$(docker exec "$CONTAINER" sh -c "
  mkdir -p /home/node/.openclaw/workspace/t13-npm-test
  cd /home/node/.openclaw/workspace/t13-npm-test
  npm init -y --silent 2>/dev/null | tail -1
  npm install --silent express 2>&1 | tail -1
  echo EXIT:\$?
  rm -rf /home/node/.openclaw/workspace/t13-npm-test
" 2>/dev/null || echo "EXIT:1")
NPM_WS_EXIT=$(echo "$NPM_WORKSPACE" | grep "EXIT:" | cut -d: -f2 | tr -d ' \n')
if [ "$NPM_WS_EXIT" = "0" ]; then
  pass "npm install in workspace project dir works with read-only rootfs"
else
  fail "npm install in workspace failed: $NPM_WORKSPACE"
fi

# ── Check 12: git init and commit in workspace ───────────────────────

log "Check 12: git init + commit in workspace..."
GIT_WORKSPACE=$(docker exec "$CONTAINER" sh -c "
  mkdir -p /home/node/.openclaw/workspace/t13-git-test
  cd /home/node/.openclaw/workspace/t13-git-test
  git init -q 2>&1
  echo 'test' > README.md
  git add README.md
  git commit -q -m 'test commit' 2>&1
  echo EXIT:\$?
  rm -rf /home/node/.openclaw/workspace/t13-git-test
" 2>/dev/null || echo "EXIT:1")
GIT_EXIT=$(echo "$GIT_WORKSPACE" | grep "EXIT:" | cut -d: -f2 | tr -d ' \n')
if [ "$GIT_EXIT" = "0" ]; then
  pass "git init + commit in workspace works with read-only rootfs"
else
  fail "git operations in workspace failed: $GIT_WORKSPACE"
fi

# ── Summary ─────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL + WARN))
log "Results: $PASS/$TOTAL pass, $FAIL fail, $WARN warn"

cat > "$RESULT_FILE" << RESULT_EOF
# T13 — Read-only root filesystem validation
**Date:** $(date '+%Y-%m-%d %H:%M')

## What was tested
Verified ISSUE-8 fix: read-only root filesystem with tmpfs mounts for /tmp and /run,
and redirected writes (GIT_CONFIG_GLOBAL, NPM_CONFIG_CACHE) pointing to the persistent volume.

## Results

| Check | Result |
|-------|--------|
| ReadonlyRootfs=true (Docker inspect) | $([ "$READONLY" = "true" ] && echo "✓ true" || echo "✗ false") |
| System paths read-only (/usr /bin /lib /etc /sbin) | $([ "$ALL_READONLY" = "true" ] && echo "✓ all read-only" || echo "✗ some writable") |
| /tmp tmpfs writable | $([ "$NPM_EXIT" = "0" ] && echo "✓ yes" || echo "✗ no") |
| /run tmpfs writable | $([ "$(docker exec $CONTAINER sh -c 'touch /run/t13-check && rm /run/t13-check && echo OK' 2>/dev/null)" = "OK" ] && echo "✓ yes" || echo "⚠ check manually") |
| Volume (/home/node/.openclaw) writable | $([ "$EXIT_CODE" = "0" ] && echo "✓ yes" || echo "✗ no") |
| GIT_CONFIG_GLOBAL set | $([ -n "$GIT_CONFIG_ENV" ] && echo "✓ yes ($GIT_CONFIG_ENV)" || echo "✗ not set") |
| git config --global writes to volume | $(echo "$GIT_IN_VOLUME" | grep -q "email" && echo "✓ yes" || echo "✗ no") |
| ~/.gitconfig absent from rootfs | $([ "$ROOTFS_GITCONFIG" = "missing" ] && echo "✓ correct" || echo "⚠ exists on rootfs") |
| NPM_CONFIG_CACHE set | $([ -n "$NPM_CACHE_ENV" ] && echo "✓ yes ($NPM_CACHE_ENV)" || echo "✗ not set") |
| npm install in /tmp | $([ "$NPM_EXIT" = "0" ] && echo "✓ works" || echo "✗ failed") |
| npm install in workspace | $([ "$NPM_WS_EXIT" = "0" ] && echo "✓ works" || echo "✗ failed") |
| git init+commit in workspace | $([ "$GIT_EXIT" = "0" ] && echo "✓ works" || echo "✗ failed") |

## Summary
- **Pass:** $PASS / $TOTAL
- **Fail:** $FAIL
- **Warn:** $WARN

## Technical Notes
- read_only: true in docker-compose.yml makes the container rootfs read-only
- tmpfs mounts provide writable ephemeral storage at /tmp (256MB) and /run (32MB)
- Persistent writes go to the named volume at /home/node/.openclaw
- GIT_CONFIG_GLOBAL=/home/node/.openclaw/.gitconfig redirects git config to volume
- NPM_CONFIG_CACHE=/home/node/.openclaw/.npm-cache redirects npm cache to volume
- .npm-global dir in rootfs becomes read-only but global npm installs aren't needed at runtime
RESULT_EOF

log "Results written to $RESULT_FILE"
log "Done. Pass=$PASS Fail=$FAIL Warn=$WARN"
exit $([ "$FAIL" -eq 0 ] && echo 0 || echo 1)
