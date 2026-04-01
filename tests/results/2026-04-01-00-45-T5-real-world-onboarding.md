# T5 — Real-world project onboarding
**Date:** 2026-04-01 00:55
**Duration:** 604s (~10 min)
**Timed out:** no

## What was tested
Agent was given a scaffolded Express.js recipe API (kestrel-api) with:
- src/index.js (Express app)
- src/db.js (in-memory data layer)
- src/routes/recipes.js (CRUD endpoints)
- test/recipes.test.js (9 existing tests — all passing at baseline)

Agent was asked to:
1. Understand and summarize the architecture
2. Add rate limiting middleware (src/middleware/rateLimit.js)
3. Wire it into the app
4. Write tests for it
5. Run full test suite without breaking existing tests

## Baseline (pre-agent)
- Baseline tests passed: confirmed working before agent intervention

## Results

| Metric | Value |
|--------|-------|
| Duration | 604s |
| Timed out | no |
| Middleware file created | yes |
| Rate limit tests created | yes |
| index.js wired middleware | yes |
| Tests passing | yes |
| Tests pass count | 12 |
| Tests fail count | 0 |
| Tests total | 12 |

## Assessment
✓ Rate limiting middleware created
✓ Rate limit tests written
✓ Middleware wired into app
✓ Completed within 900s timeout
✓ All tests passing (12/12)

## Final test suite output
```

> kestrel-api@1.0.0 test
> NODE_ENV=test node --test test/**/*.test.js

TAP version 13
# Subtest: (a) requests below limit pass through
ok 1 - (a) requests below limit pass through
  ---
  duration_ms: 10.146708
  type: 'test'
  ...
# Subtest: (b) requests over limit get 429
ok 2 - (b) requests over limit get 429
  ---
  duration_ms: 1.942167
  type: 'test'
  ...
# Subtest: (c) window resets after windowMs
ok 3 - (c) window resets after windowMs
  ---
  duration_ms: 1111.571833
  type: 'test'
  ...
# Subtest: GET /health returns ok
ok 4 - GET /health returns ok
  ---
  duration_ms: 10.866958
  type: 'test'
  ...
# Subtest: GET /recipes returns list
ok 5 - GET /recipes returns list
  ---
  duration_ms: 1.137916
  type: 'test'
  ...
# Subtest: GET /recipes/:id returns recipe
ok 6 - GET /recipes/:id returns recipe
  ---
  duration_ms: 0.9165
  type: 'test'
  ...
# Subtest: GET /recipes/:id returns 404 for unknown
ok 7 - GET /recipes/:id returns 404 for unknown
  ---
  duration_ms: 0.807083
  type: 'test'
  ...
# Subtest: POST /recipes creates recipe
ok 8 - POST /recipes creates recipe
  ---
  duration_ms: 3.518042
  type: 'test'
  ...
# Subtest: POST /recipes 400 when missing fields
ok 9 - POST /recipes 400 when missing fields
  ---
  duration_ms: 1.028208
  type: 'test'
  ...
# Subtest: PUT /recipes/:id updates recipe
ok 10 - PUT /recipes/:id updates recipe
  ---
  duration_ms: 0.928375
  type: 'test'
  ...
# Subtest: DELETE /recipes/:id removes recipe
ok 11 - DELETE /recipes/:id removes recipe
  ---
  duration_ms: 2.431375
  type: 'test'
  ...
# Subtest: GET /recipes?category= filters by category
ok 12 - GET /recipes?category= filters by category
  ---
  duration_ms: 1.08325
  type: 'test'
  ...
1..12
# tests 12
# suites 0
# pass 12
# fail 0
# cancelled 0
# skipped 0
# todo 0
# duration_ms 1281.328542
```

## Middleware content (src/middleware/rateLimit.js)
```javascript
// Rate limiting middleware - tracks requests per IP per time window

function createRateLimiter(options = {}) {
  const limit = options.limit || 10;
  const windowMs = options.windowMs || 60000; // default: 1 minute
  
  // Store: Map of IP -> { count, resetTime }
  const store = new Map();
  
  // Cleanup expired entries periodically
  // Use unref() so this doesn't keep the process alive
  const cleanupInterval = setInterval(() => {
    const now = Date.now();
    for (const [ip, data] of store.entries()) {
      if (now >= data.resetTime) {
        store.delete(ip);
      }
    }
  }, windowMs);
  cleanupInterval.unref();
  
  return function rateLimitMiddleware(req, res, next) {
    const ip = req.ip || req.connection.remoteAddress;
    const now = Date.now();
    
    let record = store.get(ip);
    
    // Initialize or reset if window expired
    if (!record || now >= record.resetTime) {
      record = {
        count: 0,
        resetTime: now + windowMs
      };
      store.set(ip, record);
    }
    
    // Increment request count
    record.count++;
    
    // Check if limit exceeded
    if (record.count > limit) {
      return res.status(429).json({ error: 'Too many requests' });
    }
    
    // Allow request to proceed
    next();
  };
}

module.exports = createRateLimiter;
```

## Project files after agent
```
/home/node/.openclaw/workspace/onboarding-test/package-lock.json
/home/node/.openclaw/workspace/onboarding-test/test/recipes.test.js
/home/node/.openclaw/workspace/onboarding-test/test/rateLimit.test.js
/home/node/.openclaw/workspace/onboarding-test/package.json
/home/node/.openclaw/workspace/onboarding-test/src/db.js
/home/node/.openclaw/workspace/onboarding-test/src/middleware/rateLimit.js
/home/node/.openclaw/workspace/onboarding-test/src/index.js
/home/node/.openclaw/workspace/onboarding-test/src/routes/recipes.js
```

## Agent output (tail)
```
I'll work through this systematically. Let me start by exploring the project structure and reading the source code.
Let me read the main source files:
Good! Now I understand the architecture. Let me proceed with the tasks:

## 1. Architecture Summary

**Architecture Summary:** This is a three-layer Express.js recipe API with: (1) `index.js` for server setup and middleware, (2) `routes/recipes.js` for RESTful endpoints (GET/POST/PUT/DELETE), and (3) `db.js` as an in-memory data layer with CRUD operations. The app uses Express Router for modular routing and includes global error handling.

Now let me create the rate limiting middleware:
Now let me wire the middleware into src/index.js:
Now let me create comprehensive tests for the rate limiter:
Now let me run the full test suite:
The tests are taking a while. Let me check the full output:
Let me wait a bit more and then check:
It seems the tests are hanging. Let me check if there's an issue with the async/await in the test setup. Let me kill this process and fix the tests:
The issue is likely with the before/after hooks. Let me fix them:
Now let me run the tests again:
It seems the Node.js test runner hooks work differently. Let me check the recipes.test.js to understand the correct pattern and fix both files:
Let me also check the recipes test to see if it needs fixing:
Now let me run the tests again:
Good progress - the rate limit tests are passing. Let me wait for the full output:
The tests are hanging after the rate limit tests. It seems like it's not moving to the recipes tests. Let me wait a bit longer:
Let me kill this and check if there's a problem with the cleanup interval in the rate limiter:
The issue is the `setInterval` in the rate limiter - it keeps the process alive. Let me fix this by using `unref()`:
Now let me run the tests again:
Perfect! All 12 tests are passing. Let me create a comprehensive summary:
```
