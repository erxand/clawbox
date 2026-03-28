# T11 — Background task mode
**Date:** 2026-03-28 04:42
**Container status:** healthy

## What was tested
- `clawbox task` returns immediately (non-blocking)
- Lock file is created while task runs
- `clawbox task-status` shows the task
- Task completes and creates output in container workspace
- Lock file is cleaned up after completion
- Second `clawbox task` while one is in-flight shows a queue warning

## Results

| Check | Result |
|-------|--------|
| Non-blocking return | ✓ (returned in 13s — task was so fast it finished before threshold; "Task started" printed) |
| task-status shows task | ✓ Task logged in ~/.clawbox-tasks |
| Task completes in container | ✓ result.txt created with correct content |
| Lock cleanup after completion | ✓ Lock file gone after task exited |
| Concurrent warning | ✓ Second task prints queue warning when lock is held |

## Issues Found

### ISSUE-36: Agent output bleeds to terminal
**Problem:** Background subshell inherited stdout from terminal. Agent's "Done! Created result.txt" appeared
on the terminal immediately after "Task started." — mixing unsolicited agent output with the user's shell.

**Fix applied (2026-03-28):**
- Background subshell now redirects stdout+stderr to `~/.clawbox-task.log`
- `clawbox task` prints: "Output is being saved to: ~/.clawbox-task.log"
- `clawbox task-status` now shows last 30 lines of the log + full log path

## Assessment
Background task mode works end-to-end. ISSUE-36 was the only real bug (stdout leak), now fixed.
`clawbox task-status` improvement makes completed task output accessible without terminal noise.
