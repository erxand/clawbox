# T14 — Multi-error recovery
**Date:** 2026-03-30 06:43
**Agent time:** 93s

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
| Agent worked systematically | ✓ yes (22 relevant mentions) |
| Agent didn't give up | ✓ yes (62 lines output) |

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

// ERROR 2b: calls subtract() which doesn't exist in utils
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
Perfect! Let me create a summary of all the fixes:
## ✅ All Errors Fixed Successfully!

I systematically debugged and fixed **3 errors** in the multi-error-app project:

### **Errors Found & Fixed:**

1. **Syntax Error in server.js** (Line 10)
   - Missing closing `});` for the `/add` route handler
   - Fixed by adding the closing brace and semicolon

2. **Wrong Import Path in test.js** (Line 5)
   - Tried to require `'./helpers'` which doesn't exist
   - Fixed by changing to `'./utils'`

3. **Missing subtract Function**
   - Test called `subtract()` but function wasn't defined
   - Fixed by:
     - Adding `subtract(a, b)` function to `utils.js`
     - Exporting it from `utils.js`
     - Importing it in `test.js`

### **Final Verification:**

✅ **(a) Server starts without errors:**
```
$ node server.js
Running on 3002
```

✅ **(b) All tests pass with 0 failures:**
```
$ node test.js
PASS: add 2+3 = 5
PASS: multiply 3*4 = 12
PASS: subtract 10-4 = 6
Results: 3 passed, 0 failed
```

The project is now fully functional!
```

## Findings
- Agent time: 93s
- Syntax error fix: yes
- Import path fix: no
- Missing function fix: yes
- All tests clean: yes
