# T6 — Concurrent Task Handling
**Date:** 2026-03-29 18:45
**Total wall time:** 124s

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
| Cross-contamination signal in output | no | yes (possible leak) |
| Files from other task in dir | A_in_B: 0
0 | B_in_A: 0
0 |

✓ Task A: math.js created
✓ Task A: math.test.js created
✓ Task B: strings.js created
✓ Task B: strings.test.js created
✓ Task A: math tests PASS
✓ Task B: strings tests PASS
✓ No cross-contamination in Task A output
⚠ Task B output mentions Task A content

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

⏳ Another Clawbox task is already running (PID 24579).
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
✓ divide(9, 3) should return 3
✓ divide(7, 2) should return 3.5
✓ divide(10, 0) should throw "division by zero" error
✓ divide(0, 5) should return 0

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
✓ capitalize("") should return ""
✓ capitalize("a") should return "A"
✓ capitalize("Hello") should return "Hello"
✓ capitalize("hello world") should return "Hello world"
✓ truncate("hello", 10) should return "hello"
✓ truncate("hello world", 5) should return "hello..."
✓ truncate("test", 4) should return "test"
✓ truncate("testing", 4) should return "test..."
✓ truncate("a very long string here", 10) should return "a very lon..."
✓ truncate("", 5) should return ""
✓ truncate("hi", 2) should return "hi"
✓ slugify("Hello World") should return "hello-world"
✓ slugify("Hello World!") should return "hello-world"
✓ slugify("Test@123") should return "test123"
✓ slugify("Multiple   Spaces") should return "multiple-spaces"
✓ slugify("Special!@#$%Characters") should return "specialcharacters"
✓ slugify("foo-bar") should return "foo-bar"
✓ slugify("A B C") should return "a-b-c"
✓ slugify("") should return ""
✓ slugify("123 Numbers 456") should return "123-numbers-456"

==================================================
Total tests: 22
Passed: 22
Failed: 0
==================================================
```

## Source: math.js
```javascript
/**
 * Basic math operations
 */

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
/**
 * String utility functions
 */

function capitalize(s) {
  if (!s || typeof s !== 'string') {
    return s;
  }
  return s.charAt(0).toUpperCase() + s.slice(1);
}

function truncate(s, n) {
  if (!s || typeof s !== 'string') {
    return s;
  }
  if (s.length <= n) {
    return s;
  }
  return s.slice(0, n) + '...';
}

function slugify(s) {
  if (!s || typeof s !== 'string') {
    return s;
  }
  return s
    .toLowerCase()
    .replace(/\s+/g, '-')           // Replace spaces with hyphens
    .replace(/[^a-z0-9-]/g, '');    // Strip non-alphanumeric (except hyphens)
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
Now let's run the tests:
Perfect! Let me create a summary document:
## ✅ All Tests Passed!

I've successfully created the math module and comprehensive test suite:

### Files Created:

1. **`/home/node/.openclaw/workspace/concurrent-A/math.js`**
   - `add(a, b)` - Adds two numbers
   - `subtract(a, b)` - Subtracts b from a
   - `multiply(a, b)` - Multiplies two numbers
   - `divide(a, b)` - Divides a by b, throws `Error('division by zero')` when b=0

2. **`/home/node/.openclaw/workspace/concurrent-A/math.test.js`**
   - 14 comprehensive tests using Node's built-in `assert` module
   - Tests all four functions with various inputs
   - Tests division by zero error handling
   - No external dependencies

### Test Results:
```
Total tests: 14
Passed: 14 ✅
Failed: 0
```

All tests passed successfully! The math module is working correctly, including proper error handling for division by zero.
```

## Agent output: Task B (tail)
```
I'll create the strings module and tests, then run them to verify everything works.
Now let's run the tests:
Excellent! Let me create a summary:
## ✅ All Tests Passed!

I've successfully created the string utilities module and comprehensive test suite:

### Files Created:

1. **`/home/node/.openclaw/workspace/concurrent-B/strings.js`**
   - `capitalize(s)` - Capitalizes the first letter of a string
   - `truncate(s, n)` - Truncates string to n characters, adds '...' if longer
   - `slugify(s)` - Converts to lowercase, replaces spaces with hyphens, strips non-alphanumeric characters

2. **`/home/node/.openclaw/workspace/concurrent-B/strings.test.js`**
   - 22 comprehensive tests using Node's built-in `assert` module
   - Tests all three functions with various edge cases
   - No external dependencies

### Test Results:
```
Total tests: 22
Passed: 22 ✅
Failed: 0
```

**Test Breakdown:**
- **capitalize()**: 6 tests - handles various cases including empty strings, single characters, and already capitalized strings
- **truncate()**: 7 tests - verifies truncation logic, edge cases, and '...' appending
- **slugify()**: 9 tests - validates lowercase conversion, space-to-hyphen replacement, special character removal, and number preservation

All tests passed successfully! The string utilities module is working correctly with proper handling of all edge cases.
```

## Summary
- **Pass:** 17 / 20
- **Fail:** 0
- **Warn:** 3

## Findings
- Gateway serializes concurrent raw-agent requests (tasks queue, not interleave) — correct and safe
- Lock mechanism (ISSUE-30/37) prevents concurrent `clawbox run` calls from queuing silently
- Second `clawbox run` while lock held exits 1 with actionable message
- Stale locks (dead PID) are auto-cleaned so a crash doesn't leave clawbox permanently blocked
