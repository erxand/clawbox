# T14 — Multi-error recovery
**Date:** 2026-03-28 22:45
**Agent time:** 132s

## Errors introduced
1. **Syntax error:** Missing closing brace in `server.js` app.get handler
2a. **Wrong import path:** `test.js` imports from `./helpers` (doesn't exist; should be `./utils`)
2b. **Nonexistent function:** `test.js` calls `subtract()` which isn't exported from utils
*(No port conflict test in this run — port 3002 used to avoid conflict)*

## Initial error state
### server.js error:
```
/home/node/.openclaw/workspace/multi-error-app/server.js:21



SyntaxError: Unexpected end of input
```

### test.js error:
```
node:internal/modules/cjs/loader:1386
  throw err;
  ^

Error: Cannot find module './helpers'
```

## Results

| Check | Result |
|-------|--------|
| server.js syntax fixed | ✓ yes |
| Wrong import path fixed | ⚠ check manually |
| All tests pass | ✓ yes |
| Server starts clean | ✓ yes |
| Agent worked systematically | ✓ yes (19 relevant mentions) |
| Agent didn't give up | ✓ yes (43 lines output) |

**Pass:** 5 / 6 | **Fail:** 0 | **Warn:** 1

## Final server.js
```javascript
const express = require('express');
const { add, multiply } = require('./utils');

const app = express();

app.get('/add', (req, res) => {
  const a = parseInt(req.query.a) || 0;
  const b = parseInt(req.query.b) || 0;
  res.json({ result: add(a, b) });
});

app.get('/multiply', (req, res) => {
  const a = parseInt(req.query.a) || 0;
  const b = parseInt(req.query.b) || 0;
  res.json({ result: multiply(a, b) });
});

const PORT = process.env.PORT || 3002;
app.listen(PORT, () => console.log('Running on ' + PORT));
module.exports = app;
```

## Final test.js
```javascript
// Simple test runner (no external deps)
const assert = require('assert');

const { add, multiply, subtract } = require('./utils');

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log('PASS:', name);
    passed++;
  } catch(e) {
    console.log('FAIL:', name, '-', e.message);
    failed++;
  }
}

test('add 2+3 = 5', () => assert.strictEqual(add(2, 3), 5));
test('multiply 3*4 = 12', () => assert.strictEqual(multiply(3, 4), 12));
test('subtract 10-4 = 6', () => assert.strictEqual(subtract(10, 4), 6));

console.log('Results:', passed, 'passed,', failed, 'failed');
process.exit(failed > 0 ? 1 : 0);
```

## Test run output
```
PASS: add 2+3 = 5
PASS: multiply 3*4 = 12
PASS: subtract 10-4 = 6
Results: 3 passed, 0 failed
EXIT:0
```

## Agent output (last 40 lines)
```
---

Now let me investigate the broken Node.js project systematically. I'll start by checking what files exist and then run the server and tests to see all the errors.
Let me examine all the files first to understand the structure:
Now let me run the server to see the first error:
Good! I found **Error 1**: Missing closing brace in server.js. Let me fix it:
Now let me test the server again:
Excellent! **Error 1 fixed** - server starts without errors now. Now let me run the tests to find the remaining errors:
Found **Error 2a**: Wrong import path in test.js - it's trying to require `./helpers` but should be `./utils`. Let me fix it:
Now run the tests again:
Found **Error 2b**: The test calls `subtract()` which doesn't exist. I need to either remove the test or add the subtract function to utils.js. Looking at the test comment, it's clear this is an error. Let me check what makes more sense - the test expects subtract to work, so let me add it to utils.js:
Now I need to import subtract in test.js:
Now let me also remove the error comment:
Now let me run the tests again:
Perfect! **Error 2b fixed** - all tests passing now! Let me do final confirmation that both the server starts and all tests pass:
## ✅ All Errors Fixed!

I systematically found and fixed **3 errors** in the multi-error-app:

### **Error 1: Missing closing brace in server.js**
- **Problem:** The first `app.get('/add')` route was missing its closing `});`
- **Fix:** Added the missing closing brace
- **Result:** Server now starts without syntax errors

### **Error 2a: Wrong import path in test.js**
- **Problem:** Test was trying to `require('./helpers')` which doesn't exist
- **Fix:** Changed to `require('./utils')`
- **Result:** Tests can now load the utility functions

### **Error 2b: Missing subtract function**
- **Problem:** Test called `subtract()` but it wasn't defined in utils.js
- **Fix:** Added `subtract(a, b)` function to utils.js and exported it
- **Result:** All tests now pass

### Final Verification:

✅ **(a) `node server.js` starts without errors** - Server runs and listens on port 3002  
✅ **(b) All tests pass with 0 failures** - 3 tests passed, 0 failed

The application is now fully functional!
```

## Findings
- Agent time: 132s
- Syntax error fix: yes
- Import path fix: no
- Missing function fix: yes
- All tests clean: yes
