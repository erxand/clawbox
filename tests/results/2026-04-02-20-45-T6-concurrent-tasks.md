# T6 — Concurrent Task Handling
**Date:** 2026-04-02 20:47
**Total wall time:** 84s

## What was tested
**Part 1:** Two raw `openclaw agent` calls fired simultaneously (2s stagger) at the same gateway endpoint — verify both complete with correct, independent outputs (no interference).
**Part 2:** `clawbox run` lock behavior after ISSUE-30/37 fixes — verify the PID lock correctly blocks concurrent calls, shows actionable messages, releases after completion, and auto-cleans stale locks.

## Part 1: Raw gateway concurrency

| | Task A (math) | Task B (strings) |
|---|---|---|
| Timed out | no | no |
| JS file created | yes | yes |
| Test file created | yes | yes |
| Tests run OK | PASS (PASS) | PASS (PASS) |
| Cross-contamination signal in output | no | no |
| Files from other task in dir | A_in_B: 0 | B_in_A: 0 |

✓ Task A: math.js created
✓ Task A: math.test.js created
✓ Task B: strings.js created
✓ Task B: strings.test.js created
✓ Task A: math tests PASS
✓ Task B: strings tests PASS
✓ No cross-contamination in Task A output
✓ No cross-contamination in Task B output

## Part 2: clawbox run lock behavior

| Check | Result |
|-------|--------|
| clawbox run succeeds with no lock | ✓ yes |
| clawbox run exits 1 when lock held | ✓ yes (exit 1) |
| Blocked message mentions 'already running' or 'cancel' | ✓ yes |
| Blocked message shows actionable commands | ✓ yes |
| Lock released after run completes | ✓ yes |
| Stale lock auto-cleaned | ✓ yes |
| clawbox task also exits 1 when lock held | ✓ yes |

## Blocked message (Part 2b)
```

⏳ Another Clawbox task is already running (PID 23559).
   Wait for it to complete, then retry.

   To check progress:        clawbox task-status
   To tail live output:      clawbox task-logs
   To cancel and run yours:  clawbox cancel && clawbox run "..."
```

## Files created (Part 1)

### Task A (`concurrent-A/`)
```
/home/node/.openclaw/workspace/concurrent-A/math.test.js
/home/node/.openclaw/workspace/concurrent-A/math.js
```

### Task B (`concurrent-B/`)
```
/home/node/.openclaw/workspace/concurrent-B/strings.test.js
/home/node/.openclaw/workspace/concurrent-B/strings.js
```

## Test runs (independent re-run after agent finished)

### math.test.js
```
All tests passed!
```

### strings.test.js
```
All tests passed!
```

## Source: math.js
```javascript
function add(a, b) { return a + b; }
function subtract(a, b) { return a - b; }
function multiply(a, b) { return a * b; }
function divide(a, b) {
  if (b === 0) throw new Error('division by zero');
  return a / b;
}
module.exports = { add, subtract, multiply, divide };
```

## Source: strings.js
```javascript
function capitalize(s) {
  if (!s) return s;
  return s[0].toUpperCase() + s.slice(1);
}

function truncate(s, n) {
  if (s.length <= n) return s;
  return s.slice(0, n) + '...';
}

function slugify(s) {
  return s.toLowerCase().replace(/\s+/g, '-').replace(/[^a-z0-9-]/g, '');
}

module.exports = { capitalize, truncate, slugify };
```

## Agent output: Task A (tail)
```
All tests passed. Both files are in place — `math.js` exports `add`, `subtract`, `multiply`, and `divide` (with the division-by-zero guard), and `math.test.js` covers all four functions including edge cases.
```

## Agent output: Task B (tail)
```
The `\s+` regex collapses multiple spaces into one hyphen. Let me fix the test expectation:
All tests passed. Both files are in place — `strings.js` exports `capitalize`, `truncate`, and `slugify`, and `strings.test.js` covers all three with edge cases.
```

## Summary
- **Pass:** 20 / 20
- **Fail:** 0
- **Warn:** 0

## Findings
- Gateway serializes concurrent raw-agent requests (tasks queue, not interleave) — correct and safe
- Lock mechanism (ISSUE-30/37) prevents concurrent `clawbox run` calls from queuing silently
- Second `clawbox run` while lock held exits 1 with actionable message
- Stale locks (dead PID) are auto-cleaned so a crash doesn't leave clawbox permanently blocked
