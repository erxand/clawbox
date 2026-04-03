# T5 — Real-world project onboarding
**Date:** 2026-04-02 18:48
**Duration:** 81s (~1 min)
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
| Duration | 81s |
| Timed out | no |
| Middleware file created | yes |
| Rate limit tests created | yes |
| index.js wired middleware | yes |
| Tests passing | yes |
| Tests pass count | 13 |
| Tests fail count | 0 |
| Tests total | 13 |

## Assessment
✓ Rate limiting middleware created
✓ Rate limit tests written
✓ Middleware wired into app
✓ Completed within 900s timeout
✓ All tests passing (13/13)

## Final test suite output
```

> kestrel-api@1.0.0 test
> NODE_ENV=test node --test test/**/*.test.js

TAP version 13
# Subtest: requests below limit pass through
ok 1 - requests below limit pass through
  ---
  duration_ms: 11.793625
  type: 'test'
  ...
# Subtest: requests over limit get 429
ok 2 - requests over limit get 429
  ---
  duration_ms: 3.210291
  type: 'test'
  ...
# Subtest: window resets after windowMs
ok 3 - window resets after windowMs
  ---
  duration_ms: 260.394709
  type: 'test'
  ...
# Subtest: default options work (limit=10, windowMs=60000)
ok 4 - default options work (limit=10, windowMs=60000)
  ---
  duration_ms: 11.429792
  type: 'test'
  ...
# Subtest: GET /health returns ok
ok 5 - GET /health returns ok
  ---
  duration_ms: 10.718667
  type: 'test'
  ...
# Subtest: GET /recipes returns list
ok 6 - GET /recipes returns list
  ---
  duration_ms: 1.147208
  type: 'test'
  ...
# Subtest: GET /recipes/:id returns recipe
ok 7 - GET /recipes/:id returns recipe
  ---
  duration_ms: 0.897792
  type: 'test'
  ...
# Subtest: GET /recipes/:id returns 404 for unknown
ok 8 - GET /recipes/:id returns 404 for unknown
  ---
  duration_ms: 0.790375
  type: 'test'
  ...
# Subtest: POST /recipes creates recipe
ok 9 - POST /recipes creates recipe
  ---
  duration_ms: 3.427083
  type: 'test'
  ...
# Subtest: POST /recipes 400 when missing fields
ok 10 - POST /recipes 400 when missing fields
  ---
  duration_ms: 0.836916
  type: 'test'
  ...
# Subtest: PUT /recipes/:id updates recipe
ok 11 - PUT /recipes/:id updates recipe
  ---
  duration_ms: 0.772083
  type: 'test'
  ...
# Subtest: DELETE /recipes/:id removes recipe
ok 12 - DELETE /recipes/:id removes recipe
  ---
  duration_ms: 2.230792
  type: 'test'
  ...
# Subtest: GET /recipes?category= filters by category
ok 13 - GET /recipes?category= filters by category
  ---
  duration_ms: 1.122667
  type: 'test'
  ...
1..13
# tests 13
# suites 0
# pass 13
# fail 0
# cancelled 0
# skipped 0
# todo 0
# duration_ms 419.515084
```

## Middleware content (src/middleware/rateLimit.js)
```javascript
'use strict';

/**
 * Configurable in-memory rate limiting middleware.
 *
 * @param {object} [options]
 * @param {number} [options.limit=10]      Max requests per window per IP
 * @param {number} [options.windowMs=60000] Window size in milliseconds
 * @returns {Function} Express middleware
 */
function rateLimit(options = {}) {
  const limit = options.limit ?? 10;
  const windowMs = options.windowMs ?? 60_000;

  // Map<ip, { count, resetTime }>
  const clients = new Map();

  // Periodically sweep expired entries to prevent unbounded growth
  const sweep = setInterval(() => {
    const now = Date.now();
    for (const [ip, entry] of clients) {
      if (now >= entry.resetTime) {
        clients.delete(ip);
      }
    }
  }, windowMs);

  // Allow the timer to not keep the process alive
  if (sweep.unref) sweep.unref();

  function middleware(req, res, next) {
    const ip = req.ip || req.socket.remoteAddress || 'unknown';
    const now = Date.now();

    let entry = clients.get(ip);

    // First request or window expired → start fresh window
    if (!entry || now >= entry.resetTime) {
      entry = { count: 1, resetTime: now + windowMs };
      clients.set(ip, entry);
      return next();
    }

    entry.count++;

    if (entry.count > limit) {
      return res.status(429).json({ error: 'Too many requests' });
    }

    next();
  }

  // Expose internals for testing
  middleware._clients = clients;
  middleware._sweep = sweep;

  return middleware;
}

module.exports = rateLimit;
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
**Architecture summary:** This is a lightweight Express 4 REST API with a classic three-layer structure: `src/index.js` sets up the Express app with JSON parsing, health check, and error handlers; `src/routes/recipes.js` defines full CRUD endpoints for recipes; and `src/db.js` provides an in-memory data store with array-backed operations. Tests use Node's built-in `node:test` runner with a raw `http` request helper — no external test dependencies.

Now let me build the rate limiter, wire it in, and write tests.
Now wire it into `src/index.js`. In test mode, set a very high limit so existing tests aren't affected:
Now write the rate limiter tests:
Now run the full test suite:
The existing `recipes.test.js` uses `done` callbacks in `before`/`after` but this Node version's test runner doesn't support that pattern. Let me fix it:
All 13 tests pass — 4 new rate limiter tests + 9 existing recipe tests. Here's the summary:

**Architecture (2-3 sentences):** A classic Express 4 REST API with three layers: `src/index.js` bootstraps the app with JSON parsing, health check, and error handlers; `src/routes/recipes.js` provides full CRUD endpoints for recipes; `src/db.js` is an in-memory array-backed data store with auto-incrementing IDs. Tests use Node's built-in `node:test` runner with a raw `http` request helper — zero test dependencies.

**What I added:**

1. **`src/middleware/rateLimit.js`** — A factory function that returns Express middleware tracking requests per IP. Accepts `{ limit, windowMs }` options (defaults: 10 req/min). Uses a `Map` keyed by IP with per-entry expiry timestamps. Returns `429 { error: 'Too many requests' }` when exceeded. Includes a self-cleaning sweep interval with `unref()` so it doesn't block process exit.

2. **Wired into `src/index.js`** — Applied globally before routes, configured via `RATE_LIMIT` and `RATE_WINDOW_MS` env vars. In test mode (`NODE_ENV=test`, set by `npm test`), the limit is raised to 10,000 so existing tests aren't affected.

3. **`test/rateLimit.test.js`** — 4 tests using isolated Express apps with tight limits:
   - Requests below limit pass through (200)
   - Requests over limit get 429 with correct error message
   - Window resets after `windowMs` (uses 200ms window)
   - Default options enforce limit=10

4. **Fixed existing test compat** — `recipes.test.js` used `done` callbacks in `before`/`after` which Node 22's test runner doesn't support; converted to async/await.
```
