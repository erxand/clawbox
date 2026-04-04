# T31 — task flag completeness + output format validation

**Run:** 2026-04-04 10:57
**Host:** Arclomedarians-Mac-mini.local
**Clawbox:** /Users/arclo/.openclaw/workspace/projects/clawbox

## Phases

- Phase 1: Source audit (--retry, --timeout, --session, --context, --thinking in cmd_task)
- Phase 2: Flag acceptance (each flag accepted without error, non-blocking return)
- Phase 3: Output format (startup messages contain correct fields per flag)
- Phase 4: Error paths (invalid values rejected with usage hints and exit 1)
- Phase 5: Flag parity (task flags match run flags, minus --quiet/--json)
- Phase 6: Help text coverage (all task flags in help output)
- Phase 7: --retry 0 and invalid --retry handling
- Phase 8: Combined flags (multi-flag combos work, non-blocking)

## Results

[10:57:47] Phase 1: Source audit — confirm all flags parsed in cmd_task
  ✓ Phase 1a: --retry flag present in cmd_task source
  ✓ Phase 1b: --timeout flag present in cmd_task source
  ✓ Phase 1c: --session flag present in cmd_task source
  ✓ Phase 1d: --context flag present in cmd_task source
  ✓ Phase 1e: --thinking flag present in cmd_task source
  ✓ Phase 1f: retry_max variable is actually used in logic (not just declared)
[10:57:47] Phase 2: Flag acceptance — each flag accepted (non-blocking, fast return)
[10:57:47] Phase 2a: clawbox task --retry 1 ...
  ✓ Phase 2a: --retry 1 accepted; task started
  ✓ Phase 2b: 'retry' mentioned in startup output when --retry N > 0
[10:57:56] Phase 2c: clawbox task --session ...
  ✓ Phase 2c: --session accepted; task started
  ✓ Phase 2d: session name 't31-session-test' in startup output
[10:58:03] Phase 2e: clawbox task --thinking minimal ...
  ✓ Phase 2e: --thinking minimal accepted; task started
[10:58:10] Phase 3: Output format — startup fields
[10:58:10] Phase 3a: task startup output contains Log: line
  ✓ Phase 3a: Log path shown in startup output (/Users/arclo/.clawbox-task-20260404-105811.log)
  ✓ Phase 3b: ~/.clawbox-task.log symlink exists → /Users/arclo/.clawbox-task-20260404-105811.log
  ✓ Phase 3c: 'task-logs' hint in startup output
  ✓ Phase 3d: 'task-status' hint in startup output
[10:58:19] Phase 4: Error paths — invalid flag values rejected
[10:58:19] Phase 4a: --retry with no value
  ✓ Phase 4a: --retry with no value exits non-zero
  ✓ Phase 4b: usage hint shown for --retry with no value
[10:58:19] Phase 4c: --timeout with non-numeric value
  ✓ Phase 4c: --timeout with non-numeric value exits non-zero
  ✓ Phase 4d: usage hint shown for --timeout with non-numeric value
[10:58:19] Phase 4e: --retry with non-numeric value
  ✓ Phase 4e: --retry with non-numeric value exits non-zero
[10:58:19] Phase 5: Flag parity between run and task
  ✓ Phase 5a: --retry implemented in BOTH cmd_run and cmd_task
  ✓ Phase 5b: --timeout is task-only (correct — run doesn't have it)
  ✓ Phase 5c: --quiet/--json correctly absent from cmd_task (task writes to log, not stdout)
[10:58:19] Phase 6: Help text coverage
  ✓ Phase 6a: --retry documented in help for task
  ✓ Phase 6b: --timeout documented in help for task
  ✓ Phase 6c: --session documented in help for task
  ✓ Phase 6d: --context documented in help for task
[10:58:19] Phase 7: --retry 0 and edge cases
[10:58:19] Phase 7a: --retry 0 accepted
  ✓ Phase 7a: --retry 0 accepted; task started
  ✓ Phase 7b: 'Retry:' correctly omitted for --retry 0
[10:58:27] Phase 8: Combined flags — multiple flags together
[10:58:28] Phase 8a: --session + --retry combined
  ✓ Phase 8a: --session + --retry combined accepted
  ✓ Phase 8b: session name shown in combined-flags output
  ✓ Phase 8c: retry shown in combined-flags output
[10:58:36] Phase 8d: --thinking + --retry + message (3-flag combo)
  ✓ Phase 8d: 3-flag combo (--thinking + --retry + message) accepted without crash

## Summary

| Result | Count |
|--------|-------|
| ✓ Pass | 33 |
| ⚠ Warn | 0 |
| ✗ Fail | 0 |
| Total  | 33 |

**Verdict: PASS — 33/33 checks pass, 0 warn, 0 fail ✅**
