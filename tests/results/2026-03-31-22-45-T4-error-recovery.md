# T4 — Error recovery test
**Date:** 2026-03-31 22:47
**Fix time:** 59s

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
I'll check what's wrong with the broken-project and fix it.
The error shows that `index.js` is trying to require a package called 'nonexistent-package' that doesn't exist. Let me check the file:
I can see the problem - line 2 has a `require('nonexistent-package')` that doesn't exist. Let me remove that line:
Now let me test if it runs without errors:
Good! The server started successfully (it was terminated by the timeout after 2 seconds, which is expected for a server). Let me verify there are no errors by checking if it starts properly:
Perfect! Let me create a summary:
## ✅ Fixed the Broken Project!

**Problem Found:**
The `index.js` file was trying to require a non-existent package called `'nonexistent-package'` on line 2, which caused a MODULE_NOT_FOUND error.

**Fix Applied:**
Removed the problematic line:
```javascript
const missing = require('nonexistent-package');
```

**Verification:**
- ✅ Syntax check passed
- ✅ Node runs without errors
- ✅ Express server starts successfully

The project is now working correctly!
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
- Time to fix: 59s
- Did it diagnose correctly? Yes
