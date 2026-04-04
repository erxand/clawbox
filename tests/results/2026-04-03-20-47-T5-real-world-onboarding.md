# T5 — Real-world project onboarding
**Date:** 2026-04-03 20:50
**Duration:** 161s (~2 min)
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
| Duration | 161s |
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
# Subtest: requests below limit pass through
ok 1 - requests below limit pass through
  ---
  duration_ms: 9.562958
  type: 'test'
  ...
# Subtest: requests over limit get 429
ok 2 - requests over limit get 429
  ---
  duration_ms: 0.716583
  type: 'test'
  ...
# Subtest: window resets after windowMs
ok 3 - window resets after windowMs
  ---
  duration_ms: 259.321875
  type: 'test'
  ...
# Subtest: GET /health returns ok
ok 4 - GET /health returns ok
  ---
  duration_ms: 10.76675
  type: 'test'
  ...
# Subtest: GET /recipes returns list
ok 5 - GET /recipes returns list
  ---
  duration_ms: 1.045791
  type: 'test'
  ...
# Subtest: GET /recipes/:id returns recipe
ok 6 - GET /recipes/:id returns recipe
  ---
  duration_ms: 0.921959
  type: 'test'
  ...
# Subtest: GET /recipes/:id returns 404 for unknown
ok 7 - GET /recipes/:id returns 404 for unknown
  ---
  duration_ms: 0.744208
  type: 'test'
  ...
# Subtest: POST /recipes creates recipe
ok 8 - POST /recipes creates recipe
  ---
  duration_ms: 3.330917
  type: 'test'
  ...
# Subtest: POST /recipes 400 when missing fields
ok 9 - POST /recipes 400 when missing fields
  ---
  duration_ms: 1.014458
  type: 'test'
  ...
# Subtest: PUT /recipes/:id updates recipe
ok 10 - PUT /recipes/:id updates recipe
  ---
  duration_ms: 0.899542
  type: 'test'
  ...
# Subtest: DELETE /recipes/:id removes recipe
ok 11 - DELETE /recipes/:id removes recipe
  ---
  duration_ms: 2.273958
  type: 'test'
  ...
# Subtest: GET /recipes?category= filters by category
ok 12 - GET /recipes?category= filters by category
  ---
  duration_ms: 1.159959
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
# duration_ms 409.913667
```

## Middleware content (src/middleware/rateLimit.js)
```javascript
/**
 * Configurable in-memory rate limiting middleware.
 * @param {Object} options
 * @param {number} options.limit - Max requests per window (default: 10)
 * @param {number} options.windowMs - Window duration in ms (default: 60000)
 */
function rateLimit({ limit = 10, windowMs = 60000 } = {}) {
  const hits = new Map(); // ip -> { count, resetTime }

  return (req, res, next) => {
    const ip = req.ip || req.socket.remoteAddress;
    const now = Date.now();
    let entry = hits.get(ip);

    if (!entry || now >= entry.resetTime) {
      entry = { count: 0, resetTime: now + windowMs };
      hits.set(ip, entry);
    }

    entry.count++;

    if (entry.count > limit) {
      return res.status(429).json({ error: 'Too many requests' });
    }

    next();
  };
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
**Architecture summary**: It's a simple Express.js REST API for recipes with an in-memory database (`src/db.js`) providing CRUD operations. Routes are modular (`src/routes/recipes.js`) and the app exports itself for testing. Tests use Node's built-in `node:test` runner with raw `http` requests.

Now building the rate limiter:
The `before`/`after` hooks in Node 22's test runner don't use `done` callbacks — they need to return promises. Both test files have this issue. Let me fix both:
All **12 tests passing** — 3 new rate limiter tests + 9 existing recipe tests.

### Summary

1. **Architecture**: Express.js REST API with modular routes (`/recipes` CRUD) backed by an in-memory database (`src/db.js`). The app exports itself for test consumption and uses Node's built-in `node:test` runner.

2. **Rate limiter** (`src/middleware/rateLimit.js`): Tracks request counts per IP with configurable `limit` and `windowMs`. Returns `429 {error: 'Too many requests'}` when exceeded. Resets per-IP counters after the window expires.

3. **Wired into `src/index.js`**: Applied globally, reads `RATE_LIMIT` and `RATE_WINDOW_MS` env vars, disabled when `NODE_ENV=test` so existing tests aren't affected.

4. **Tests** (`test/rateLimit.test.js`): Verifies requests below limit pass (200), requests over limit get 429, and the window resets after `windowMs`. Also fixed the `before`/`after` hooks in both test files to use promises (Node 22's test runner doesn't support `done` callbacks).
```
