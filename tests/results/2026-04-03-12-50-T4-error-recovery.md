# T4 — Error recovery test
**Date:** 2026-04-03 12:51
**Fix time:** 56s

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
The issue: `index.js` requires `nonexistent-package` which doesn't exist and is never actually used. Also, `express` may not be installed either.
Express is installed. The only problem is the `require('nonexistent-package')` line — it's imported but never used. Removing it:
Server starts cleanly — no errors. The fix was simply removing the unused `require('nonexistent-package')` line. The app is now running on port 3000.
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
- Time to fix: 56s
- Did it diagnose correctly? Yes
