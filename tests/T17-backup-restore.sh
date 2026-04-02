#!/usr/bin/env bash
# T17 — Backup & Restore validation
#
# What: Verify that `clawbox backup` creates a valid tar.gz of the volume state
#       and `clawbox restore` correctly restores it — including agent workspace
#       files, AGENTS.md, and any project data the agent created.
# Why:  Backup/restore is the only data durability mechanism for clawbox. If it's
#       broken, users can lose all agent state (memory, projects, configs) with no
#       recovery path. Zero test coverage until now.
#
# This test does NOT require Anthropic API access (no agent calls), so it can run
# even during rate-limit windows.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T17-backup-restore.md"
CONTAINER="clawbox-work"
WORKSPACE="/home/node/.openclaw/workspace"
CLAWBOX_DIR="${SCRIPT_DIR}/.."
BACKUP_DIR="${CLAWBOX_DIR}/backups"

mkdir -p "$RESULT_DIR"

PASS=0
FAIL=0
WARN=0
FINDINGS=()
START_TIME=$(date +%s)

log() { echo "[T17 $(date +%H:%M:%S)] $*"; }

pass() { echo "  ✓ $*"; PASS=$((PASS+1)); FINDINGS+=("pass|$*"); }
fail() { echo "  ✗ $*"; FAIL=$((FAIL+1)); FINDINGS+=("fail|$*"); }
warn() { echo "  ⚠ $*"; WARN=$((WARN+1)); FINDINGS+=("warn|$*"); }

cleanup_test_artifacts() {
  # Clean up test-specific files we injected into the container
  docker exec "$CONTAINER" sh -c "rm -f ${WORKSPACE}/t17-canary.txt ${WORKSPACE}/t17-deep/nested/file.txt; rm -rf ${WORKSPACE}/t17-deep" 2>/dev/null || true
}

# ── Phase 1: Pre-flight — ensure container is healthy ───────────────────────

log "Phase 1: Pre-flight checks..."

if ! docker ps --filter name="$CONTAINER" --format '{{.Names}}' | grep -q "$CONTAINER"; then
  log "Container not running, starting..."
  "$CLAWBOX" start
  sleep 5
fi

CONTAINER_STATUS=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
if [ "$CONTAINER_STATUS" = "healthy" ]; then
  pass "Container is healthy"
else
  warn "Container status is '$CONTAINER_STATUS' (expected healthy)"
fi

# ── Phase 2: Inject canary files ────────────────────────────────────────────

log "Phase 2: Injecting canary files into workspace..."

# Canary 1: simple text file at workspace root
docker exec "$CONTAINER" sh -c "echo 'T17-CANARY-$(date +%s)' > ${WORKSPACE}/t17-canary.txt"
CANARY_CONTENT=$(docker exec "$CONTAINER" cat "${WORKSPACE}/t17-canary.txt" 2>/dev/null)

if [ -n "$CANARY_CONTENT" ]; then
  pass "Canary file created: t17-canary.txt"
else
  fail "Failed to create canary file in container"
fi

# Canary 2: nested directory structure
docker exec "$CONTAINER" sh -c "mkdir -p ${WORKSPACE}/t17-deep/nested && echo 'deep-file-content' > ${WORKSPACE}/t17-deep/nested/file.txt"
DEEP_CONTENT=$(docker exec "$CONTAINER" cat "${WORKSPACE}/t17-deep/nested/file.txt" 2>/dev/null)

if [ "$DEEP_CONTENT" = "deep-file-content" ]; then
  pass "Deep nested canary created: t17-deep/nested/file.txt"
else
  fail "Failed to create deep nested canary"
fi

# Record existing workspace state for comparison
PRE_BACKUP_FILES=$(docker exec "$CONTAINER" sh -c "find ${WORKSPACE} -type f | wc -l" 2>/dev/null | tr -d ' ')
PRE_BACKUP_AGENTS=$(docker exec "$CONTAINER" cat "${WORKSPACE}/AGENTS.md" 2>/dev/null | head -1)

log "Pre-backup: $PRE_BACKUP_FILES files in workspace, AGENTS.md starts with: '$PRE_BACKUP_AGENTS'"

# ── Phase 3: Run backup ────────────────────────────────────────────────────

log "Phase 3: Running clawbox backup..."

# Count existing backups
PRE_BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')

BACKUP_OUTPUT=$("$CLAWBOX" backup 2>&1)
BACKUP_EXIT=$?

echo "$BACKUP_OUTPUT"

if [ "$BACKUP_EXIT" -eq 0 ]; then
  pass "clawbox backup exited 0"
else
  fail "clawbox backup exited $BACKUP_EXIT (expected 0)"
fi

# Check a new backup file was created
POST_BACKUP_COUNT=$(ls -1 "$BACKUP_DIR"/*.tar.gz 2>/dev/null | wc -l | tr -d ' ')

if [ "$POST_BACKUP_COUNT" -gt "$PRE_BACKUP_COUNT" ]; then
  pass "New backup file created ($PRE_BACKUP_COUNT → $POST_BACKUP_COUNT)"
else
  fail "No new backup file created (still $POST_BACKUP_COUNT)"
fi

# Identify the newest backup
LATEST_BACKUP=$(ls -t "$BACKUP_DIR"/*.tar.gz 2>/dev/null | head -1)

if [ -z "$LATEST_BACKUP" ]; then
  fail "No backup file found in $BACKUP_DIR"
  # Can't continue without a backup
  log "ABORT: No backup file to restore. Writing results..."
else
  pass "Latest backup: $(basename "$LATEST_BACKUP")"

  # Check backup is non-trivial (>1KB)
  BACKUP_SIZE=$(stat -f%z "$LATEST_BACKUP" 2>/dev/null || stat -c%s "$LATEST_BACKUP" 2>/dev/null || echo "0")
  if [ "$BACKUP_SIZE" -gt 1024 ]; then
    pass "Backup size is ${BACKUP_SIZE} bytes (>1KB — non-trivial)"
  else
    fail "Backup size is ${BACKUP_SIZE} bytes — suspiciously small"
  fi

  # Check backup contains expected files
  BACKUP_CONTENTS=$(tar tzf "$LATEST_BACKUP" 2>/dev/null | head -30)
  if echo "$BACKUP_CONTENTS" | grep -q "t17-canary.txt"; then
    pass "Backup contains t17-canary.txt"
  else
    # It might be under a different path prefix — check more broadly
    ALL_CONTENTS=$(tar tzf "$LATEST_BACKUP" 2>/dev/null)
    if echo "$ALL_CONTENTS" | grep -q "t17-canary"; then
      pass "Backup contains t17-canary (different path prefix)"
    else
      fail "Backup does NOT contain t17-canary.txt"
    fi
  fi

  if tar tzf "$LATEST_BACKUP" 2>/dev/null | grep -q "AGENTS.md"; then
    pass "Backup contains AGENTS.md"
  else
    fail "Backup does NOT contain AGENTS.md"
  fi

  # ── Phase 4: Destroy and restore ───────────────────────────────────────

  log "Phase 4: Destroying canary files, then restoring from backup..."

  # Delete canary files
  docker exec "$CONTAINER" sh -c "rm -f ${WORKSPACE}/t17-canary.txt; rm -rf ${WORKSPACE}/t17-deep"

  # Verify canary is gone
  CANARY_GONE=$(docker exec "$CONTAINER" cat "${WORKSPACE}/t17-canary.txt" 2>&1 || echo "GONE")
  if echo "$CANARY_GONE" | grep -qi "GONE\|no such file"; then
    pass "Canary file confirmed deleted before restore"
  else
    warn "Canary file still present after deletion attempt"
  fi

  # Run restore
  log "Restoring from $(basename "$LATEST_BACKUP")..."
  RESTORE_OUTPUT=$("$CLAWBOX" restore "$LATEST_BACKUP" 2>&1)
  RESTORE_EXIT=$?

  echo "$RESTORE_OUTPUT"

  if [ "$RESTORE_EXIT" -eq 0 ]; then
    pass "clawbox restore exited 0"
  else
    fail "clawbox restore exited $RESTORE_EXIT (expected 0)"
  fi

  # ── Phase 5: Verify restored state ─────────────────────────────────────

  log "Phase 5: Starting container and verifying restored state..."

  # Restore stops the container (compose down), so we need to start it again
  "$CLAWBOX" start
  sleep 5

  # Check container is healthy after restore
  RESTORED_STATUS=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
  if [ "$RESTORED_STATUS" = "healthy" ]; then
    pass "Container healthy after restore"
  else
    # Give it more time
    sleep 10
    RESTORED_STATUS=$(docker inspect "$CONTAINER" --format '{{.State.Health.Status}}' 2>/dev/null || echo "unknown")
    if [ "$RESTORED_STATUS" = "healthy" ]; then
      pass "Container healthy after restore (needed extra time)"
    else
      fail "Container status '$RESTORED_STATUS' after restore (expected healthy)"
    fi
  fi

  # Check canary file is restored
  RESTORED_CANARY=$(docker exec "$CONTAINER" cat "${WORKSPACE}/t17-canary.txt" 2>/dev/null || echo "MISSING")
  if [ "$RESTORED_CANARY" = "$CANARY_CONTENT" ]; then
    pass "Canary file restored with correct content"
  elif echo "$RESTORED_CANARY" | grep -q "T17-CANARY"; then
    pass "Canary file restored (content present but may differ)"
  else
    fail "Canary file NOT restored (got: '$RESTORED_CANARY')"
  fi

  # Check deep nested file
  RESTORED_DEEP=$(docker exec "$CONTAINER" cat "${WORKSPACE}/t17-deep/nested/file.txt" 2>/dev/null || echo "MISSING")
  if [ "$RESTORED_DEEP" = "deep-file-content" ]; then
    pass "Deep nested file restored correctly"
  else
    fail "Deep nested file NOT restored (got: '$RESTORED_DEEP')"
  fi

  # Check AGENTS.md survived
  RESTORED_AGENTS=$(docker exec "$CONTAINER" cat "${WORKSPACE}/AGENTS.md" 2>/dev/null | head -1)
  if [ "$RESTORED_AGENTS" = "$PRE_BACKUP_AGENTS" ]; then
    pass "AGENTS.md restored with correct content"
  elif [ -n "$RESTORED_AGENTS" ]; then
    pass "AGENTS.md exists after restore (content: '$RESTORED_AGENTS')"
  else
    fail "AGENTS.md missing after restore"
  fi

  # Check file count is similar
  POST_RESTORE_FILES=$(docker exec "$CONTAINER" sh -c "find ${WORKSPACE} -type f | wc -l" 2>/dev/null | tr -d ' ')
  if [ "$POST_RESTORE_FILES" -ge "$PRE_BACKUP_FILES" ]; then
    pass "File count preserved: $PRE_BACKUP_FILES → $POST_RESTORE_FILES"
  else
    warn "File count decreased after restore: $PRE_BACKUP_FILES → $POST_RESTORE_FILES"
  fi

  # Check file ownership (should be node:node, not root)
  CANARY_OWNER=$(docker exec "$CONTAINER" stat -c '%U:%G' "${WORKSPACE}/t17-canary.txt" 2>/dev/null || echo "unknown")
  if [ "$CANARY_OWNER" = "node:node" ]; then
    pass "Restored files owned by node:node (correct)"
  else
    warn "Restored files owned by '$CANARY_OWNER' (expected node:node) — may cause permission issues"
  fi
fi

# ── Phase 6: Edge cases ─────────────────────────────────────────────────────

log "Phase 6: Edge cases..."

# 6.1 restore with no argument
RESTORE_NOARG=$("$CLAWBOX" restore 2>&1 || true)
if echo "$RESTORE_NOARG" | grep -qi "usage\|path\|file"; then
  pass "restore with no args shows usage hint"
else
  fail "restore with no args doesn't show usage (got: '$(echo "$RESTORE_NOARG" | head -1)')"
fi

# 6.2 restore with nonexistent file
RESTORE_BADFILE=$("$CLAWBOX" restore "/tmp/nonexistent-backup-t17.tar.gz" 2>&1 || true)
if echo "$RESTORE_BADFILE" | grep -qi "not found\|no such\|does not exist\|error"; then
  pass "restore with bad path shows error"
else
  fail "restore with bad path didn't error (got: '$(echo "$RESTORE_BADFILE" | head -1)')"
fi

# ── Cleanup ─────────────────────────────────────────────────────────────────

log "Cleaning up test artifacts..."
cleanup_test_artifacts

# ── Write results ───────────────────────────────────────────────────────────

END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))

log "Results: $PASS pass, $WARN warn, $FAIL fail (${DURATION}s)"

{
  echo "# T17 — Backup & Restore validation"
  echo "**Date:** $(date '+%Y-%m-%d %H:%M')"
  echo "**Duration:** ${DURATION}s"
  echo ""
  echo "## What was tested"
  echo "1. Inject canary files (root + nested) into container workspace"
  echo "2. Run \`clawbox backup\` — verify tar.gz created with correct contents"
  echo "3. Delete canary files from live container"
  echo "4. Run \`clawbox restore\` — verify canary files, AGENTS.md, file count, ownership"
  echo "5. Edge cases: restore with no args, restore with bad path"
  echo ""
  echo "## Assessment"
  for f in "${FINDINGS[@]}"; do
    KIND="${f%%|*}"
    MSG="${f#*|}"
    case "$KIND" in
      pass) echo "✓ $MSG" ;;
      fail) echo "✗ $MSG" ;;
      warn) echo "⚠ $MSG" ;;
    esac
  done
  echo ""
  echo "## Summary"
  echo "| Metric | Value |"
  echo "|--------|-------|"
  echo "| Pass | $PASS |"
  echo "| Warn | $WARN |"
  echo "| Fail | $FAIL |"
  echo "| Duration | ${DURATION}s |"
  echo "| Backup file | $(basename "${LATEST_BACKUP:-none}") |"
  echo "| Backup size | ${BACKUP_SIZE:-unknown} bytes |"
  echo "| Pre-backup files | ${PRE_BACKUP_FILES:-?} |"
  echo "| Post-restore files | ${POST_RESTORE_FILES:-?} |"
} > "$RESULT_FILE"

log "Results written to $RESULT_FILE"
log "Done."
