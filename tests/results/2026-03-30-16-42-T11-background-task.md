# T11 — Background task mode
**Date:** 2026-03-30 16:42
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
- **Fail:** 1
- **Warn:** 0

## Key findings
- Timestamped log path: /Users/arclo/.clawbox-task-20260330-164211.log
- Task completed in ~0s
- ~/.clawbox-task.log is a symlink (ISSUE-43 ✓)

## Assessment
FAILURES detected — see results above.
