# T6 — Concurrent Task Handling
**Date:** 2026-03-31 20:42
**Total wall time:** 103s

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

⏳ Another Clawbox task is already running (PID 25593).
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
✓ add(2, 3) should return 5
✓ add(-1, 1) should return 0
✓ add(0, 0) should return 0
✓ subtract(5, 3) should return 2
✓ subtract(0, 5) should return -5
✓ subtract(10, 10) should return 0
✓ multiply(3, 4) should return 12
✓ multiply(5, 0) should return 0
✓ multiply(-2, 3) should return -6
✓ divide(10, 2) should return 5
✓ divide(7, 2) should return 3.5
✓ divide(-10, 5) should return -2
✓ divide(5, 0) should throw "division by zero" error
✓ divide(0, 0) should throw "division by zero" error

==================================================
Total tests: 14
Passed: 14
Failed: 0
==================================================
```

### strings.test.js
```
✓ capitalize("hello") should return "Hello"
✓ capitalize("world") should return "World"
✓ capitalize("a") should return "A"
✓ capitalize("") should return ""
✓ capitalize("Hello") should return "Hello" (already capitalized)
✓ truncate("hello world", 5) should return "hello..."
✓ truncate("short", 10) should return "short" (no truncation)
✓ truncate("exactly", 7) should return "exactly" (exact length)
✓ truncate("this is a long string", 10) should return "this is a ..."
✓ truncate("", 5) should return ""
✓ truncate("abc", 1) should return "a..."
✓ slugify("Hello World") should return "hello-world"
✓ slugify("JavaScript is Fun!") should return "javascript-is-fun"
✓ slugify("user@example.com") should return "userexamplecom"
✓ slugify("One Two Three") should return "one-two-three"
✓ slugify("Test 123!") should return "test-123"
✓ slugify("a b c") should return "a-b-c"
✓ slugify("Remove   Multiple   Spaces") should return "remove-multiple-spaces"
✓ slugify("Special@#$%Chars") should return "specialchars"

==================================================
Total tests: 19
Passed: 19
Failed: 0
==================================================
```

## Source: math.js
```javascript
// math.js - Basic math operations

function add(a, b) {
  return a + b;
}

function subtract(a, b) {
  return a - b;
}

function multiply(a, b) {
  return a * b;
}

function divide(a, b) {
  if (b === 0) {
    throw new Error('division by zero');
  }
  return a / b;
}

module.exports = {
  add,
  subtract,
  multiply,
  divide
};
```

## Source: strings.js
```javascript
// strings.js - String utility functions

function capitalize(s) {
  if (!s || s.length === 0) {
    return s;
  }
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function truncate(s, n) {
  if (s.length <= n) {
    return s;
  }
  return s.slice(0, n) + '...';
}

function slugify(s) {
  return s
    .toLowerCase()
    .replace(/\s+/g, '-')           // Replace spaces with hyphens
    .replace(/[^a-z0-9-]/g, '');    // Strip non-alphanumeric (keep hyphens)
}

module.exports = {
  capitalize,
  truncate,
  slugify
};
```

## Agent output: Task A (tail)
```
I'll create the math module and tests, then run them to verify everything works.
Now let me run the tests:
Perfect! Let me create a summary:
## ✅ Math Module - All Tests Passed!

I've successfully created the math module and comprehensive tests:

### **Files Created:**

1. **`/home/node/.openclaw/workspace/concurrent-A/math.js`**
   - Four exported functions: `add`, `subtract`, `multiply`, `divide`
   - Division by zero protection (throws `Error('division by zero')`)

2. **`/home/node/.openclaw/workspace/concurrent-A/math.test.js`**
   - 14 comprehensive tests using Node's built-in `assert` module
   - No external dependencies required

### **Test Results:**

```
✅ 14/14 tests passed

Add:      3 tests ✓
Subtract: 3 tests ✓
Multiply: 3 tests ✓
Divide:   5 tests ✓ (including division by zero error handling)

Exit code: 0 (success)
```

All functions work correctly with various inputs including:
- Positive and negative numbers
- Zero handling
- Decimal results
- Proper error throwing for division by zero
```

## Agent output: Task B (tail)
```
I'll create the strings module and tests, then run them to verify everything works.
Now let me run the tests:
Perfect! Let me create a summary:
## ✅ Strings Module - All Tests Passed!

I've successfully created the strings module and comprehensive tests:

### **Files Created:**

1. **`/home/node/.openclaw/workspace/concurrent-B/strings.js`**
   - `capitalize(s)` - First letter uppercase
   - `truncate(s, n)` - Truncate to n chars + '...' if longer
   - `slugify(s)` - Lowercase, spaces→hyphens, strip non-alphanumeric

2. **`/home/node/.openclaw/workspace/concurrent-B/strings.test.js`**
   - 19 comprehensive tests using Node's built-in `assert` module
   - No external dependencies required

### **Test Results:**

```
✅ 19/19 tests passed

Capitalize: 5 tests ✓
Truncate:   6 tests ✓
Slugify:    8 tests ✓

Exit code: 0 (success)
```

All functions work correctly with various inputs including:
- **capitalize**: Empty strings, single chars, already-capitalized
- **truncate**: Short strings (no truncation), exact length, very short limits
- **slugify**: Spaces, special characters, multiple spaces, numbers, punctuation

The slugify function properly converts strings to URL-friendly slugs by converting to lowercase, replacing spaces with hyphens, and removing all non-alphanumeric characters!
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
