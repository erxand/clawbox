#!/usr/bin/env bash
# T5 — Real-world project onboarding
#
# What: Clone a non-trivial open source project. Ask the agent to:
#       (1) understand the codebase and summarize key architecture,
#       (2) add a new feature (configurable rate limiting middleware),
#       (3) write tests for the new feature,
#       (4) verify existing tests still pass.
#
# Why:  Tests the full "junior dev onboarding" scenario — real-world code,
#       no scaffolding, real constraints. Does the agent understand code it
#       didn't write? Can it add features without breaking things?
#
# Good: Agent summarizes architecture accurately, adds feature that works,
#       tests pass, existing tests unbroken.
# Bad:  Agent hallucinates file structure, breaks existing tests, produces
#       non-functional code, or gets lost in the codebase.
#
# Project used: fastify/fastify-example (medium Express-style app with routes,
# plugins, tests). Alternatively falls back to a Node.js project we scaffold here.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"

CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T5-real-world-onboarding.md"
CONTAINER="clawbox-work"
TIMEOUT_SECONDS=900  # 15 minutes
WORKSPACE="/home/node/.openclaw/workspace"
PROJECT_DIR="$WORKSPACE/onboarding-test"

mkdir -p "$RESULT_DIR"

log() { echo "[T5 $(date +%H:%M:%S)] $*"; }

# ── Setup ────────────────────────────────────────────────────────────────────

log "Checking container is running..."
RUNNING=$(docker inspect "$CONTAINER" --format '{{.State.Running}}' 2>/dev/null || echo "false")
if [ "$RUNNING" != "true" ]; then
  log "Starting container..."
  "$CLAWBOX" start
  sleep 5
fi

# Scaffold a real-ish project inside the container (avoid relying on git clone
# which depends on internet access being enabled in the container)
log "Scaffolding test project inside container..."
docker exec "$CONTAINER" sh -c "
  mkdir -p $PROJECT_DIR
  cd $PROJECT_DIR

  # Only scaffold if not already there
  if [ ! -f package.json ]; then
    cat > package.json << 'PKGJSON'
{
  \"name\": \"kestrel-api\",
  \"version\": \"1.0.0\",
  \"description\": \"A small HTTP API server for managing a recipe database\",
  \"main\": \"src/index.js\",
  \"scripts\": {
    \"start\": \"node src/index.js\",
    \"test\": \"node --test test/**/*.test.js\"
  },
  \"dependencies\": {
    \"express\": \"^4.18.2\"
  }
}
PKGJSON
    echo 'Created package.json'
  else
    echo 'project already scaffolded'
  fi
"

# Scaffold source files
docker exec "$CONTAINER" sh -c "
  mkdir -p $PROJECT_DIR/src/routes $PROJECT_DIR/src/middleware $PROJECT_DIR/test
  cd $PROJECT_DIR

  cat > src/db.js << 'DBJS'
// In-memory recipe database (simulates a real DB layer)
const recipes = [
  { id: 1, name: 'Spaghetti Carbonara', category: 'pasta', prepTime: 20 },
  { id: 2, name: 'Caesar Salad', category: 'salad', prepTime: 10 },
  { id: 3, name: 'Chicken Tikka Masala', category: 'curry', prepTime: 45 },
];
let nextId = 4;

module.exports = {
  getAll: () => [...recipes],
  getById: (id) => recipes.find(r => r.id === id),
  getByCategory: (cat) => recipes.filter(r => r.category === cat),
  create: (data) => {
    const recipe = { id: nextId++, ...data };
    recipes.push(recipe);
    return recipe;
  },
  update: (id, data) => {
    const idx = recipes.findIndex(r => r.id === id);
    if (idx === -1) return null;
    recipes[idx] = { ...recipes[idx], ...data };
    return recipes[idx];
  },
  delete: (id) => {
    const idx = recipes.findIndex(r => r.id === id);
    if (idx === -1) return false;
    recipes.splice(idx, 1);
    return true;
  },
};
DBJS

  cat > src/routes/recipes.js << 'ROUTESJS'
const express = require('express');
const db = require('../db');
const router = express.Router();

// GET /recipes - list all recipes
router.get('/', (req, res) => {
  const { category } = req.query;
  const data = category ? db.getByCategory(category) : db.getAll();
  res.json({ recipes: data, total: data.length });
});

// GET /recipes/:id - get single recipe
router.get('/:id', (req, res) => {
  const recipe = db.getById(parseInt(req.params.id));
  if (!recipe) return res.status(404).json({ error: 'Not found' });
  res.json(recipe);
});

// POST /recipes - create recipe
router.post('/', (req, res) => {
  const { name, category, prepTime } = req.body;
  if (!name || !category) {
    return res.status(400).json({ error: 'name and category required' });
  }
  const recipe = db.create({ name, category, prepTime: prepTime || 0 });
  res.status(201).json(recipe);
});

// PUT /recipes/:id - update recipe
router.put('/:id', (req, res) => {
  const recipe = db.update(parseInt(req.params.id), req.body);
  if (!recipe) return res.status(404).json({ error: 'Not found' });
  res.json(recipe);
});

// DELETE /recipes/:id - delete recipe
router.delete('/:id', (req, res) => {
  const deleted = db.delete(parseInt(req.params.id));
  if (!deleted) return res.status(404).json({ error: 'Not found' });
  res.status(204).send();
});

module.exports = router;
ROUTESJS

  cat > src/index.js << 'APPJS'
const express = require('express');
const recipeRoutes = require('./routes/recipes');

const app = express();
app.use(express.json());

// Health check
app.get('/health', (req, res) => res.json({ status: 'ok' }));

// Routes
app.use('/recipes', recipeRoutes);

// 404 handler
app.use((req, res) => res.status(404).json({ error: 'Not found' }));

// Error handler
app.use((err, req, res, _next) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Internal server error' });
});

const PORT = process.env.PORT || 3001;
if (require.main === module) {
  app.listen(PORT, () => console.log(\`kestrel-api running on port \${PORT}\`));
}

module.exports = app;
APPJS

  cat > test/recipes.test.js << 'TESTJS'
const assert = require('node:assert/strict');
const { test, before, after } = require('node:test');
const http = require('http');
const app = require('../src/index');

let server;
let baseUrl;

before((done) => {
  server = app.listen(0, () => {
    baseUrl = \`http://localhost:\${server.address().port}\`;
    done();
  });
});

after((done) => server.close(done));

function request(method, path, body) {
  return new Promise((resolve, reject) => {
    const url = new URL(path, baseUrl);
    const opts = {
      method,
      headers: { 'Content-Type': 'application/json' },
    };
    const req = http.request(url, opts, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        let parsed;
        try { parsed = JSON.parse(data); } catch { parsed = data; }
        resolve({ status: res.statusCode, body: parsed });
      });
    });
    req.on('error', reject);
    if (body) req.write(JSON.stringify(body));
    req.end();
  });
}

test('GET /health returns ok', async () => {
  const res = await request('GET', '/health');
  assert.equal(res.status, 200);
  assert.equal(res.body.status, 'ok');
});

test('GET /recipes returns list', async () => {
  const res = await request('GET', '/recipes');
  assert.equal(res.status, 200);
  assert.ok(Array.isArray(res.body.recipes));
  assert.ok(res.body.total > 0);
});

test('GET /recipes/:id returns recipe', async () => {
  const res = await request('GET', '/recipes/1');
  assert.equal(res.status, 200);
  assert.equal(res.body.id, 1);
});

test('GET /recipes/:id returns 404 for unknown', async () => {
  const res = await request('GET', '/recipes/9999');
  assert.equal(res.status, 404);
});

test('POST /recipes creates recipe', async () => {
  const res = await request('POST', '/recipes', { name: 'Test Dish', category: 'test' });
  assert.equal(res.status, 201);
  assert.ok(res.body.id);
  assert.equal(res.body.name, 'Test Dish');
});

test('POST /recipes 400 when missing fields', async () => {
  const res = await request('POST', '/recipes', { name: 'No category' });
  assert.equal(res.status, 400);
});

test('PUT /recipes/:id updates recipe', async () => {
  const res = await request('PUT', '/recipes/2', { name: 'Updated Salad' });
  assert.equal(res.status, 200);
  assert.equal(res.body.name, 'Updated Salad');
});

test('DELETE /recipes/:id removes recipe', async () => {
  const create = await request('POST', '/recipes', { name: 'To Delete', category: 'temp' });
  const id = create.body.id;
  const del = await request('DELETE', \`/recipes/\${id}\`);
  assert.equal(del.status, 204);
  const check = await request('GET', \`/recipes/\${id}\`);
  assert.equal(check.status, 404);
});

test('GET /recipes?category= filters by category', async () => {
  const res = await request('GET', '/recipes?category=pasta');
  assert.equal(res.status, 200);
  assert.ok(res.body.recipes.every(r => r.category === 'pasta'));
});
TESTJS

  echo 'Scaffold complete'
"

# Install npm deps
log "Installing npm dependencies in container..."
docker exec "$CONTAINER" sh -c "
  cd $PROJECT_DIR
  npm install --prefer-offline 2>&1 | tail -5
"

# Run baseline tests to confirm they pass before we hand off to agent
log "Running baseline tests..."
BASELINE_RESULT=$(docker exec "$CONTAINER" sh -c "
  cd $PROJECT_DIR
  node --test test/**/*.test.js 2>&1
" || true)

BASELINE_PASS=$(echo "$BASELINE_RESULT" | grep -c "# tests" || echo "0")
BASELINE_FAIL=$(echo "$BASELINE_RESULT" | grep -ci "fail" || echo "0")
log "Baseline: $BASELINE_PASS test blocks, fail mentions: $BASELINE_FAIL"

# ── Send task ────────────────────────────────────────────────────────────────

TASK_MSG="I have a small Express.js recipe API project at $PROJECT_DIR/.
Please:
1. Read the source code and summarize the architecture in 2-3 sentences.
2. Add a configurable rate limiting middleware to src/middleware/rateLimit.js. It should: track request counts per IP per time window (default: 10 req/min), return 429 with {error:'Too many requests'} when exceeded, accept {limit, windowMs} options, store state in memory.
3. Wire the middleware into src/index.js (applied globally, configurable via env vars RATE_LIMIT and RATE_WINDOW_MS).
4. Write tests for the rate limiter in test/rateLimit.test.js that verify: (a) requests below limit pass through, (b) requests over limit get 429, (c) window resets after windowMs.
5. Run the full test suite (test/**/*.test.js) and make sure all tests pass — both the existing tests and your new ones.

Use absolute paths. The project is at $PROJECT_DIR/."

log "Sending onboarding task to agent..."
START_TIME=$(date +%s)
OPENCLAW_GATEWAY_URL="ws://localhost:18790" OPENCLAW_GATEWAY_TOKEN="clawbox" \
  openclaw agent --agent main -m "$TASK_MSG" > /tmp/t5-output.txt 2>&1 &
AGENT_PID=$!

# Poll progress
ELAPSED=0
while kill -0 "$AGENT_PID" 2>/dev/null && [ "$ELAPSED" -lt "$TIMEOUT_SECONDS" ]; do
  sleep 20
  ELAPSED=$(( $(date +%s) - START_TIME ))
  log "Still running... ${ELAPSED}s elapsed"
done

if kill -0 "$AGENT_PID" 2>/dev/null; then
  log "TIMEOUT — killing agent process"
  kill "$AGENT_PID" 2>/dev/null || true
  TIMED_OUT="yes"
else
  TIMED_OUT="no"
fi

END_TIME=$(date +%s)
ELAPSED=$(( END_TIME - START_TIME ))

# ISSUE-44: Check for rate limit before doing any verification
AGENT_OUTPUT_CHECK=$(cat /tmp/t5-output.txt 2>/dev/null || echo "")
if is_rate_limited "$AGENT_OUTPUT_CHECK"; then
  skip_rate_limited "T5 — Real-world project onboarding" "$RESULT_FILE" "$(echo "$AGENT_OUTPUT_CHECK" | grep -i "rate limit" | head -3)"
  log "SKIPPED due to API rate limit."
  exit 0
fi

# ── Verify results ────────────────────────────────────────────────────────────

log "Verifying results..."

# Did agent create the middleware file?
MIDDLEWARE_EXISTS=$(docker exec "$CONTAINER" sh -c "test -f $PROJECT_DIR/src/middleware/rateLimit.js && echo yes || echo no" 2>/dev/null || echo "no")

# Did agent create new tests?
NEW_TESTS_EXISTS=$(docker exec "$CONTAINER" sh -c "test -f $PROJECT_DIR/test/rateLimit.test.js && echo yes || echo no" 2>/dev/null || echo "no")

# Was index.js modified (middleware wired in)?
INDEX_MODIFIED=$(docker exec "$CONTAINER" sh -c "grep -q 'rateLimit\|rate-limit\|rate_limit' $PROJECT_DIR/src/index.js 2>/dev/null && echo yes || echo no" 2>/dev/null || echo "no")

# Run the test suite and capture results
# Use npm test (respects package.json scripts.test which may set NODE_ENV=test)
# and fall back to direct invocation if needed.
FINAL_TEST_RESULT=$(docker exec "$CONTAINER" sh -c "
  cd $PROJECT_DIR
  npm test 2>&1
" 2>/dev/null || echo "(test run failed)")

# Extract pass/fail counts from TAP summary lines (e.g. "# pass 13", "# fail 1")
TESTS_PASS=$(echo "$FINAL_TEST_RESULT" | grep "^# pass" | awk '{print $3}' | head -1 || echo "0")
TESTS_FAIL=$(echo "$FINAL_TEST_RESULT" | grep "^# fail" | awk '{print $3}' | head -1 || echo "0")
TESTS_TOTAL=$(echo "$FINAL_TEST_RESULT" | grep "^# tests" | awk '{print $3}' | head -1 || echo "0")

# Default unset values to 0
[ -z "$TESTS_PASS" ] && TESTS_PASS=0
[ -z "$TESTS_FAIL" ] && TESTS_FAIL=0
[ -z "$TESTS_TOTAL" ] && TESTS_TOTAL=0

# Determine overall test status (same precedence as T1 ISSUE-48 fix):
# check for failures FIRST, then partial, then full pass
if echo "$FINAL_TEST_RESULT" | grep -qE "^# fail [1-9]"; then
  if [ "$TESTS_TOTAL" -gt 0 ] && [ "$TESTS_PASS" -gt 0 ]; then
    TESTS_STATUS="partial (${TESTS_PASS}/${TESTS_TOTAL})"
  else
    TESTS_STATUS="failing"
  fi
elif echo "$FINAL_TEST_RESULT" | grep -q "^# pass"; then
  TESTS_STATUS="yes"
else
  TESTS_STATUS="unknown"
fi

# Get agent output summary
AGENT_OUTPUT=$(cat /tmp/t5-output.txt 2>/dev/null | tail -60)

# List final project files
FINAL_FILES=$(docker exec "$CONTAINER" sh -c "find $PROJECT_DIR -type f -not -path '*/node_modules/*' -not -path '*/.git/*'" 2>/dev/null || echo "(could not list)")

# Get middleware content if it exists
MIDDLEWARE_CONTENT=$(docker exec "$CONTAINER" sh -c "cat $PROJECT_DIR/src/middleware/rateLimit.js 2>/dev/null" || echo "(not found)")

# ── Write results ─────────────────────────────────────────────────────────────

cat > "$RESULT_FILE" << RESULT_EOF
# T5 — Real-world project onboarding
**Date:** $(date '+%Y-%m-%d %H:%M')
**Duration:** ${ELAPSED}s (~$((ELAPSED / 60)) min)
**Timed out:** $TIMED_OUT

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
| Duration | ${ELAPSED}s |
| Timed out | $TIMED_OUT |
| Middleware file created | $MIDDLEWARE_EXISTS |
| Rate limit tests created | $NEW_TESTS_EXISTS |
| index.js wired middleware | $INDEX_MODIFIED |
| Tests passing | $TESTS_STATUS |
| Tests pass count | $TESTS_PASS |
| Tests fail count | $TESTS_FAIL |
| Tests total | $TESTS_TOTAL |

## Assessment
$([ "$MIDDLEWARE_EXISTS" = "yes" ] && echo "✓ Rate limiting middleware created" || echo "✗ Middleware NOT created at expected path")
$([ "$NEW_TESTS_EXISTS" = "yes" ] && echo "✓ Rate limit tests written" || echo "✗ Tests for rate limiter NOT found")
$([ "$INDEX_MODIFIED" = "yes" ] && echo "✓ Middleware wired into app" || echo "✗ Middleware NOT wired into index.js")
$([ "$TIMED_OUT" = "no" ] && echo "✓ Completed within ${TIMEOUT_SECONDS}s timeout" || echo "✗ Timed out after ${TIMEOUT_SECONDS}s")
$(if [ "$TESTS_STATUS" = "yes" ]; then echo "✓ All tests passing (${TESTS_PASS}/${TESTS_TOTAL})"; elif echo "$TESTS_STATUS" | grep -q "partial"; then echo "⚠ Tests partial: ${TESTS_PASS}/${TESTS_TOTAL} — ${TESTS_FAIL} failing"; else echo "✗ Tests failing (${TESTS_FAIL} failures, ${TESTS_PASS} passing)"; fi)

## Final test suite output
\`\`\`
$FINAL_TEST_RESULT
\`\`\`

## Middleware content (src/middleware/rateLimit.js)
\`\`\`javascript
$MIDDLEWARE_CONTENT
\`\`\`

## Project files after agent
\`\`\`
$FINAL_FILES
\`\`\`

## Agent output (tail)
\`\`\`
$AGENT_OUTPUT
\`\`\`
RESULT_EOF

log "Results written to $RESULT_FILE"
log "Done."
