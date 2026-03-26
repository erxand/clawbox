# T4 — Error recovery test
**Date:** 2026-03-26 12:21
**Fix time:** 26s

## What was tested
1. Created an npm project with Express
2. Added a `require('nonexistent-package')` to break it
3. Asked the agent to diagnose and fix

## Initial error
```
node:internal/modules/cjs/loader:1386
  throw err;
  ^

Error: Cannot find module 'nonexistent-package'
Require stack:
- /home/node/.openclaw/workspace/broken-project/index.js
    at Function._resolveFilename (node:internal/modules/cjs/loader:1383:15)
    at defaultResolveImpl (node:internal/modules/cjs/loader:1025:19)
    at resolveForCJSWithHooks (node:internal/modules/cjs/loader:1030:22)
    at Function._load (node:internal/modules/cjs/loader:1192:37)
    at TracingChannel.traceSync (node:diagnostics_channel:328:14)
    at wrapModuleLoad (node:internal/modules/cjs/loader:237:24)
    at Module.require (node:internal/modules/cjs/loader:1463:12)
    at require (node:internal/modules/helpers:147:16)
    at Object.<anonymous> (/home/node/.openclaw/workspace/broken-project/index.js:2:17)
    at Module._compile (node:internal/modules/cjs/loader:1705:14) {
  code: 'MODULE_NOT_FOUND',
  requireStack: [ '/home/node/.openclaw/workspace/broken-project/index.js' ]
}

Node.js v22.22.1
```

## Agent response (summary)
```
The error shows that `index.js` is trying to require a nonexistent package. Let me examine the project files:
**Found the issue!** The `index.js` file is requiring `nonexistent-package` on line 2, but it's not listed in `package.json` dependencies — and it doesn't actually exist. This package is never used in the code either.

**Fix:** Remove the unnecessary require statement:
Now test if it runs:
Perfect! Let me verify the fix:
---

## ✅ Fixed!

**Problem:** `index.js` was requiring a non-existent package:
```javascript
const missing = require('nonexistent-package');  // ❌ Not in package.json, never used
```

**Solution:** Removed the unused require statement.

**Result:** 
- ✅ Node runs without errors
- ✅ Server starts on port 3000
- ✅ GET / endpoint responds with "Hello"

The `nonexistent-package` was dead code that wasn't actually needed anywhere in the application.
```

## Fixed index.js
```javascript
const express = require('express');

const app = express();
app.get('/', (req, res) => res.send('Hello'));
app.listen(3000);
```

## Verification
```
Hello
```

## Assessment
✓ Agent diagnosed and fixed the error
- Time to fix: 26s
- Did it diagnose correctly? Yes
