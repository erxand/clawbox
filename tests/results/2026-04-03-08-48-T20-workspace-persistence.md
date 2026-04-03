# T20 — Workspace Persistence Across Container Restarts
**Date:** 2026-04-03 08:49

## Score
- ✓ Pass: 13
- ⚠ Warn: 0
- ✗ Fail: 0
- Total checks: 13

## What was tested
- Files written to workspace volume before container restart
- Container stopped and restarted with `clawbox stop; clawbox start`
- Canary file, nested directory structure, git history all verified after restart
- Container rootfs read-only enforcement
- Agent (via `clawbox run`) can read and write workspace files

## Key Findings
- Canary before: 'T20 persistence test — written at 20260403-084847'
- Canary after:  'T20 persistence test — written at 20260403-084847'
- Git commits: before=1, after=1
- Workspace top-level items after restart: 25
- Container restart time: 14s

## Assessment
✅ All checks pass — workspace persistence fully reliable.
