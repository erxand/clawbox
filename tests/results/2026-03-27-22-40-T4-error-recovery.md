# T4 — Error recovery test
**Date:** 2026-03-27 22:41
**Fix time:** 29s

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
Let me check what's in that directory and run it to see the error.
The error shows that `index.js` is trying to require a module called `nonexistent-package` that doesn't exist. Let me check the file:
The issue is clear: the code is trying to require `nonexistent-package` which doesn't exist. Let me remove that unnecessary require statement:
Now let's test it:
Perfect! Fixed. The issue was an unnecessary `require('nonexistent-package')` statement on line 2. I removed it and the server now runs without errors. The Express app starts successfully on port 3000.
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
- Time to fix: 29s
- Did it diagnose correctly? Yes
