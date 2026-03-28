# T4 — Error recovery test
**Date:** 2026-03-28 14:40
**Fix time:** 31s

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
I'll check what's wrong with the broken project and fix it.
The error shows that `index.js` is trying to require a module called `nonexistent-package` that doesn't exist. Let me check the file:
I can see the issue - there's a `require('nonexistent-package')` on line 2 that's trying to load a package that doesn't exist. Let me remove this unnecessary line:
Now let's test if it runs without errors:
Perfect! ✅ **Fixed!**

## What Was Wrong

The file had a line trying to require a non-existent package:
```javascript
const missing = require('nonexistent-package');
```

## What I Fixed

Removed the problematic `require('nonexistent-package')` statement. The Express server now runs successfully without errors.

The server starts up correctly and listens on port 3000. The code is now working! 🎉
```

## Fixed index.js
```javascript
const express = require('express');

const app = express();
app.get('/', (req, res) => res.send('Hello'));
app.listen(3000, () => console.log('Server running on http://localhost:3000'));
```

## Verification
```
Server running on http://localhost:3000
Hello
```

## Assessment
✓ Agent diagnosed and fixed the error
- Time to fix: 31s
- Did it diagnose correctly? Yes
