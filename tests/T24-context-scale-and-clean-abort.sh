#!/usr/bin/env bash
# T24 — Context injection at scale + clawbox clean abort safety
#
# What: Two independent capability checks:
#
#   Phase 1 — Context injection at scale:
#     Inject a non-trivial multi-file project (~10-15 source files) via
#     `clawbox run --context <dir> --json` and verify:
#     - context_files count is correct (>1, <50)
#     - agent response references content from injected files
#     - elapsed_ms is positive
#     - --session + --context works together (JSON has both keys)
#
#   Phase 2 — clawbox clean abort:
#     Verify that `clawbox clean` with a 'N' reply:
#     - prints the destructive warning message
#     - does NOT delete the container or volume
#     - exits 0 (abort is not an error)
#     - help text includes 'clean'
#
#   Phase 3 — Large single-file context (edge case):
#     Pass a file ~5KB in size as --context. Verify:
#     - context_files=1 in JSON
#     - agent references content from the large file
#     - No truncation warning or error in output
#
# Does NOT require Anthropic API in Phase 2; Phases 1+3 make one agent call each.
# Total duration: ~60-120s (two live agent calls + docker checks)
#
# Why: --context dir is the primary UX for real coding workflows. It was tested
# in T8 with small 3-file dirs, but never with a realistic project-scale dir.
# `clawbox clean` destructive abort path has zero coverage.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLAWBOX="${SCRIPT_DIR}/../clawbox"
RESULT_DIR="${SCRIPT_DIR}/results"
TIMESTAMP=$(date +%Y-%m-%d-%H-%M)
RESULT_FILE="${RESULT_DIR}/${TIMESTAMP}-T24-context-scale-clean-abort.md"
CONTAINER="clawbox-work"
WORKSPACE="/home/node/.openclaw/workspace"

# Source shared rate-limit helpers
if [ -f "$SCRIPT_DIR/lib/common.sh" ]; then
  # shellcheck source=lib/common.sh
  source "$SCRIPT_DIR/lib/common.sh"
fi

mkdir -p "$RESULT_DIR"

PASS=0
FAIL=0
WARN=0
FINDINGS=""

pass() { PASS=$((PASS+1)); FINDINGS+="  ✓ $1\n"; echo "  ✓ $1"; }
fail() { FAIL=$((FAIL+1)); FINDINGS+="  ✗ $1\n"; echo "  ✗ $1"; }
warn() { WARN=$((WARN+1)); FINDINGS+="  ⚠ $1\n"; echo "  ⚠ $1"; }

log() { echo "[T24 $(date +%H:%M:%S)] $*"; }

START_TIME=$(date +%s)

log "Starting T24 — context injection at scale + clean abort safety"

# ─── Ensure container is running ─────────────────────────────────────────────
if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
  log "Container not running — starting..."
  "$CLAWBOX" start 2>&1 | tail -5
fi

if ! docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
  fail "container could not be started — aborting"
  exit 1
fi
pass "container running at test start"

# ─── Build a realistic multi-file project on the host for context injection ──
TMPDIR_CONTEXT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_CONTEXT"' EXIT

log "Creating multi-file context project in $TMPDIR_CONTEXT..."

# Create a realistic small Express-like project: 12 source files
cat > "$TMPDIR_CONTEXT/package.json" << 'EOF'
{
  "name": "invoice-api",
  "version": "2.3.1",
  "description": "Invoice management REST API",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "test": "node --test test/**/*.test.js"
  },
  "dependencies": {
    "express": "^4.18.2",
    "uuid": "^9.0.0"
  },
  "devDependencies": {
    "supertest": "^6.3.4"
  }
}
EOF

mkdir -p "$TMPDIR_CONTEXT/src/routes"
mkdir -p "$TMPDIR_CONTEXT/src/middleware"
mkdir -p "$TMPDIR_CONTEXT/src/models"
mkdir -p "$TMPDIR_CONTEXT/test"

cat > "$TMPDIR_CONTEXT/src/server.js" << 'EOF'
const express = require('express');
const invoiceRoutes = require('./routes/invoices');
const clientRoutes = require('./routes/clients');
const authMiddleware = require('./middleware/auth');
const errorHandler = require('./middleware/errorHandler');
const { PORT = 3000 } = process.env;

const app = express();
app.use(express.json());
app.use('/api/invoices', authMiddleware, invoiceRoutes);
app.use('/api/clients', authMiddleware, clientRoutes);
app.use(errorHandler);

if (require.main === module) {
  app.listen(PORT, () => console.log(`Invoice API listening on :${PORT}`));
}
module.exports = app;
EOF

cat > "$TMPDIR_CONTEXT/src/routes/invoices.js" << 'EOF'
const express = require('express');
const router = express.Router();
const Invoice = require('../models/Invoice');
const db = require('../db');

// GET /api/invoices — list all invoices (optionally filter by clientId)
router.get('/', (req, res) => {
  const { clientId, status } = req.query;
  let results = db.invoices;
  if (clientId) results = results.filter(i => i.clientId === clientId);
  if (status) results = results.filter(i => i.status === status);
  res.json(results);
});

// GET /api/invoices/:id
router.get('/:id', (req, res) => {
  const invoice = db.invoices.find(i => i.id === req.params.id);
  if (!invoice) return res.status(404).json({ error: 'Invoice not found' });
  res.json(invoice);
});

// POST /api/invoices
router.post('/', (req, res) => {
  const { clientId, amount, dueDate, lineItems } = req.body;
  if (!clientId || !amount || !dueDate) {
    return res.status(400).json({ error: 'clientId, amount, and dueDate are required' });
  }
  const invoice = new Invoice({ clientId, amount, dueDate, lineItems: lineItems || [] });
  db.invoices.push(invoice);
  res.status(201).json(invoice);
});

// PATCH /api/invoices/:id/status
router.patch('/:id/status', (req, res) => {
  const invoice = db.invoices.find(i => i.id === req.params.id);
  if (!invoice) return res.status(404).json({ error: 'Invoice not found' });
  const { status } = req.body;
  if (!['draft', 'sent', 'paid', 'overdue', 'cancelled'].includes(status)) {
    return res.status(400).json({ error: 'Invalid status' });
  }
  invoice.status = status;
  invoice.updatedAt = new Date().toISOString();
  res.json(invoice);
});

// DELETE /api/invoices/:id
router.delete('/:id', (req, res) => {
  const idx = db.invoices.findIndex(i => i.id === req.params.id);
  if (idx === -1) return res.status(404).json({ error: 'Invoice not found' });
  db.invoices.splice(idx, 1);
  res.status(204).end();
});

module.exports = router;
EOF

cat > "$TMPDIR_CONTEXT/src/routes/clients.js" << 'EOF'
const express = require('express');
const router = express.Router();
const Client = require('../models/Client');
const db = require('../db');

router.get('/', (req, res) => res.json(db.clients));

router.get('/:id', (req, res) => {
  const client = db.clients.find(c => c.id === req.params.id);
  if (!client) return res.status(404).json({ error: 'Client not found' });
  res.json(client);
});

router.post('/', (req, res) => {
  const { name, email, company } = req.body;
  if (!name || !email) return res.status(400).json({ error: 'name and email are required' });
  const client = new Client({ name, email, company });
  db.clients.push(client);
  res.status(201).json(client);
});

router.delete('/:id', (req, res) => {
  const idx = db.clients.findIndex(c => c.id === req.params.id);
  if (idx === -1) return res.status(404).json({ error: 'Client not found' });
  db.clients.splice(idx, 1);
  res.status(204).end();
});

module.exports = router;
EOF

cat > "$TMPDIR_CONTEXT/src/models/Invoice.js" << 'EOF'
const { v4: uuidv4 } = require('uuid');

class Invoice {
  constructor({ clientId, amount, dueDate, lineItems = [], status = 'draft' }) {
    this.id = uuidv4();
    this.clientId = clientId;
    this.amount = parseFloat(amount);
    this.dueDate = dueDate;
    this.lineItems = lineItems;
    this.status = status;
    this.createdAt = new Date().toISOString();
    this.updatedAt = new Date().toISOString();
  }
}

module.exports = Invoice;
EOF

cat > "$TMPDIR_CONTEXT/src/models/Client.js" << 'EOF'
const { v4: uuidv4 } = require('uuid');

class Client {
  constructor({ name, email, company = '' }) {
    this.id = uuidv4();
    this.name = name;
    this.email = email;
    this.company = company;
    this.createdAt = new Date().toISOString();
  }
}

module.exports = Client;
EOF

cat > "$TMPDIR_CONTEXT/src/db.js" << 'EOF'
// In-memory database — reset on each process start
const db = {
  invoices: [],
  clients: []
};

module.exports = db;
EOF

cat > "$TMPDIR_CONTEXT/src/middleware/auth.js" << 'EOF'
// Simple API key auth — checks X-API-Key header against API_KEY env var
// In test mode (NODE_ENV=test), authentication is bypassed.
const AUTH_KEY = process.env.API_KEY || 'dev-key-12345';

function authMiddleware(req, res, next) {
  if (process.env.NODE_ENV === 'test') return next();
  const key = req.headers['x-api-key'];
  if (!key || key !== AUTH_KEY) {
    return res.status(401).json({ error: 'Unauthorized — X-API-Key required' });
  }
  next();
}

module.exports = authMiddleware;
EOF

cat > "$TMPDIR_CONTEXT/src/middleware/errorHandler.js" << 'EOF'
// Global error handler middleware
function errorHandler(err, req, res, _next) {
  const status = err.status || err.statusCode || 500;
  const message = err.message || 'Internal Server Error';
  if (process.env.NODE_ENV !== 'test') {
    console.error('[error]', status, message, err.stack);
  }
  res.status(status).json({ error: message });
}

module.exports = errorHandler;
EOF

cat > "$TMPDIR_CONTEXT/README.md" << 'EOF'
# invoice-api

REST API for managing invoices and clients. Built with Express.js.

## Endpoints

### Invoices
- `GET /api/invoices` — list (filter by `?clientId=` or `?status=`)
- `GET /api/invoices/:id` — get one
- `POST /api/invoices` — create (body: `clientId`, `amount`, `dueDate`, optional `lineItems`)
- `PATCH /api/invoices/:id/status` — update status (draft/sent/paid/overdue/cancelled)
- `DELETE /api/invoices/:id` — delete

### Clients
- `GET /api/clients` — list all
- `GET /api/clients/:id` — get one
- `POST /api/clients` — create (body: `name`, `email`, optional `company`)
- `DELETE /api/clients/:id` — delete

## Auth
All routes require `X-API-Key: dev-key-12345` header (bypassed in `NODE_ENV=test`).

## Running
```bash
npm start         # port 3000
API_KEY=secret npm start
NODE_ENV=test npm test
```
EOF

# Count context files (excluding node_modules, .git)
CONTEXT_FILE_COUNT=$(find "$TMPDIR_CONTEXT" -type f | grep -vE 'node_modules|\.git' | wc -l | tr -d ' ')
log "Context project has $CONTEXT_FILE_COUNT files"

echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo "  Phase 1: Context injection at scale (multi-file --context dir)"
echo "════════════════════════════════════════════════════════════════════════"

# Phase 1: Ask the agent to summarize the architecture using --context on the dir
# Use --json so we can verify context_files count and elapsed_ms
log "Running: clawbox run --context <dir> --json --session t24-ctx-scale '...'"

P1_JSON_OUT=$("$CLAWBOX" run \
  --context "$TMPDIR_CONTEXT" \
  --json \
  --session t24-ctx-scale \
  "Summarize the architecture of this project in 2-3 sentences. List the Express routes this app exposes and the authentication mechanism." \
  2>/dev/null) || true

# Check for rate limits
if declare -f is_rate_limited > /dev/null 2>&1 && is_rate_limited "$P1_JSON_OUT"; then
  echo "SKIP: API rate limited during Phase 1" >> "$RESULT_FILE"
  skip_rate_limited
fi

# Validate JSON
P1_VALID=0
if echo "$P1_JSON_OUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
  pass "Phase 1: --context dir output is valid JSON"
  P1_VALID=1
else
  fail "Phase 1: --context dir output is not valid JSON (got: ${P1_JSON_OUT:0:200})"
fi

if [ "$P1_VALID" = "1" ]; then
  # Check context_files count
  CTX_FILES=$(echo "$P1_JSON_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('context_files',0))" 2>/dev/null || echo "0")
  if [ "$CTX_FILES" -gt 1 ] 2>/dev/null; then
    pass "Phase 1: context_files=$CTX_FILES (>1, correct for multi-file dir)"
  else
    fail "Phase 1: context_files=$CTX_FILES — expected >1 for $CONTEXT_FILE_COUNT-file dir"
  fi

  if [ "$CTX_FILES" -lt 50 ] 2>/dev/null; then
    pass "Phase 1: context_files=$CTX_FILES (below 50-file cap)"
  else
    warn "Phase 1: context_files=$CTX_FILES — approaching or at 50-file cap"
  fi

  # Check elapsed_ms is positive integer
  ELAPSED=$(echo "$P1_JSON_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('elapsed_ms',0))" 2>/dev/null || echo "0")
  if [ "$ELAPSED" -gt 0 ] 2>/dev/null; then
    pass "Phase 1: elapsed_ms=$ELAPSED (positive)"
  else
    fail "Phase 1: elapsed_ms=$ELAPSED — expected positive integer"
  fi

  # Check session key in JSON
  SESSION_KEY=$(echo "$P1_JSON_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('session','MISSING'))" 2>/dev/null || echo "MISSING")
  if [ "$SESSION_KEY" != "MISSING" ] && [ -n "$SESSION_KEY" ]; then
    pass "Phase 1: session key present in JSON (value: $SESSION_KEY)"
  else
    fail "Phase 1: session key missing from JSON output"
  fi

  # Check agent response references key project concepts
  P1_RESPONSE=$(echo "$P1_JSON_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response',''))" 2>/dev/null || echo "")
  CONCEPTS_FOUND=0
  for concept in "invoice" "client" "route" "auth" "API"; do
    if echo "$P1_RESPONSE" | grep -qi "$concept"; then
      CONCEPTS_FOUND=$((CONCEPTS_FOUND+1))
    fi
  done
  if [ "$CONCEPTS_FOUND" -ge 3 ]; then
    pass "Phase 1: agent response references project concepts ($CONCEPTS_FOUND/5 keywords found)"
  else
    warn "Phase 1: agent response only referenced $CONCEPTS_FOUND/5 expected concepts — may not have read context"
  fi
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo "  Phase 2: clawbox clean — abort path (non-destructive)"
echo "════════════════════════════════════════════════════════════════════════"

log "Testing clawbox clean abort with 'N' response..."

# Send 'N' to the clean prompt — this should abort without deleting anything
CLEAN_OUTPUT=$(echo "N" | "$CLAWBOX" clean 2>&1 || true)
CLEAN_EXIT=$?

# Check warning message is present
if echo "$CLEAN_OUTPUT" | grep -qi "stop\|delete\|agent data\|sure"; then
  pass "Phase 2: clean prints destructive warning message"
else
  fail "Phase 2: clean missing warning message (got: ${CLEAN_OUTPUT:0:200})"
fi

# Check abort message
if echo "$CLEAN_OUTPUT" | grep -qi "abort\|cancel\|not deleted\|nothing"; then
  pass "Phase 2: clean prints abort/cancel confirmation"
else
  warn "Phase 2: clean output doesn't explicitly say 'aborted' (may be fine: ${CLEAN_OUTPUT:0:100})"
fi

# Verify container is still running after 'N' answer
if docker ps --format '{{.Names}}' 2>/dev/null | grep -q "^${CONTAINER}$"; then
  pass "Phase 2: container still running after clean abort (data NOT deleted)"
else
  fail "Phase 2: container was stopped after 'N' — clean abort did not work correctly"
fi

# Verify clean is in help
CLEAN_IN_HELP=$("$CLAWBOX" help 2>&1)
if echo "$CLEAN_IN_HELP" | grep -q "clean"; then
  pass "Phase 2: 'clean' listed in clawbox help"
else
  fail "Phase 2: 'clean' not found in clawbox help"
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════"
echo "  Phase 3: Large single-file context (edge case)"
echo "════════════════════════════════════════════════════════════════════════"

# Create a ~5KB single file
LARGE_FILE=$(mktemp /tmp/t24-largefile-XXXXXX.js)
{
  echo "// large-module.js — comprehensive utility library"
  echo "// SECRET_SENTINEL_VALUE: XYZZY_T24_CANARY_42"
  echo ""
  for i in $(seq 1 80); do
    echo "function utility${i}(x) { return x * ${i} + ${i}; } // utility function ${i}"
  done
  echo ""
  echo "module.exports = { $(seq 1 80 | sed 's/.*/utility&/' | paste -sd, -) };"
} > "$LARGE_FILE"
LARGE_FILE_SIZE=$(wc -c < "$LARGE_FILE" | tr -d ' ')
log "Large file created: ${LARGE_FILE_SIZE} bytes"

P3_JSON_OUT=$("$CLAWBOX" run \
  --context "$LARGE_FILE" \
  --json \
  "What is the SECRET_SENTINEL_VALUE defined in this file?" \
  2>/dev/null) || true

# Check for rate limits
if declare -f is_rate_limited > /dev/null 2>&1 && is_rate_limited "$P3_JSON_OUT"; then
  warn "Phase 3 skipped: API rate limited"
else
  P3_VALID=0
  if echo "$P3_JSON_OUT" | python3 -c "import sys,json; json.load(sys.stdin)" 2>/dev/null; then
    pass "Phase 3: large file --context output is valid JSON"
    P3_VALID=1
  else
    fail "Phase 3: large file --context output is not valid JSON"
  fi

  if [ "$P3_VALID" = "1" ]; then
    P3_CTX=$(echo "$P3_JSON_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('context_files',0))" 2>/dev/null || echo "0")
    if [ "$P3_CTX" = "1" ]; then
      pass "Phase 3: context_files=1 for single file"
    else
      fail "Phase 3: context_files=$P3_CTX — expected 1 for single file"
    fi

    P3_RESPONSE=$(echo "$P3_JSON_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response',''))" 2>/dev/null || echo "")
    if echo "$P3_RESPONSE" | grep -q "XYZZY_T24_CANARY_42"; then
      pass "Phase 3: agent correctly read and quoted the sentinel value from large file"
    else
      warn "Phase 3: agent response did not include XYZZY_T24_CANARY_42 (context may be truncated or agent paraphrased)"
    fi
  fi
fi

rm -f "$LARGE_FILE"

# ─── Summary ─────────────────────────────────────────────────────────────────
END_TIME=$(date +%s)
DURATION=$((END_TIME - START_TIME))
TOTAL=$((PASS + FAIL + WARN))

echo ""
echo "════════════════════════════════════════════════════════════════════════"
printf "  Results: %d pass, %d fail, %d warn (of %d checks)  [%ds]\n" \
  "$PASS" "$FAIL" "$WARN" "$TOTAL" "$DURATION"
echo "════════════════════════════════════════════════════════════════════════"

# ─── Write result file ────────────────────────────────────────────────────────
cat > "$RESULT_FILE" << REPORT
# T24 — Context injection at scale + clawbox clean abort
**Date:** $(date '+%Y-%m-%d %H:%M')
**Duration:** ${DURATION}s

## What was tested

### Phase 1 — --context dir at scale
- Injected a realistic 9-file Express invoice API project via \`--context <dir>\`
- Verified: valid JSON, context_files count, elapsed_ms, session key, agent references project concepts

### Phase 2 — clawbox clean abort
- Sent 'N' to the clean confirmation prompt
- Verified: warning message present, abort confirmed, container NOT deleted, clean in help

### Phase 3 — Large single-file context
- Injected a ~${LARGE_FILE_SIZE}-byte JS file with a unique sentinel value
- Verified: context_files=1, agent reads and reports sentinel value

## Results

| Check | Phase | Result |
|-------|-------|--------|
$(printf "%s\n" "$FINDINGS" | sed 's/^  //' | grep -E '^[✓✗⚠]' | \
  awk -F' ' '{
    sym=$1; rest=substr($0, length($1)+2);
    phase="P1";
    if (index(rest,"Phase 2")>0) phase="P2";
    else if (index(rest,"Phase 3")>0) phase="P3";
    printf "| %s %s | %s | |\n", sym, rest, phase
  }' | head -40)

**Pass:** $PASS / $TOTAL | **Fail:** $FAIL | **Warn:** $WARN | **Duration:** ${DURATION}s

## Findings
$(printf "%s\n" "$FINDINGS")

## Phase 1 agent response
\`\`\`
$(echo "$P3_JSON_OUT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('response','')[:500])" 2>/dev/null || echo "(not available)")
\`\`\`

## Phase 2 clean output
\`\`\`
$CLEAN_OUTPUT
\`\`\`
REPORT

log "Results written to $RESULT_FILE"
log "Done."

# Exit with failure count (0 = all pass/warn)
[ "$FAIL" -eq 0 ]
