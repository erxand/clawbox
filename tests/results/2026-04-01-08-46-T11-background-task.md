# T11 — Background task mode
**Date:** 2026-04-01 08:46
**Container status:** healthy

## What was tested
- `clawbox task` returns immediately (non-blocking start)
- ISSUE-43: timestamped log path printed in output
- ISSUE-43: `~/.clawbox-task.log` is a symlink to timestamped file
- Lock file created while task is running
- `clawbox task-status` shows the submitted task
- Task completes and creates output in container workspace
- Log file has content after completion
- Lock file cleaned up after completion
- Second `clawbox task` while one is in-flight shows queue warning

## Results
- **Pass:** 11
- **Fail:** 0
- **Warn:** 1

## Key findings
- Timestamped log path: /Users/arclo/.clawbox-task-20260401-084627.log
- Task completed in ~20s
- ~/.clawbox-task.log is a symlink (ISSUE-43 ✓)

## Assessment
Background task mode is functional. ISSUE-43 timestamped log behavior confirmed.
