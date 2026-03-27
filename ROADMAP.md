# Clawbox Roadmap

## Test Results

### T2 — Context window stress (2026-03-26)
- ✓ Agent navigated 141-file Express.js codebase selectively (no context overload)
- ✓ Added `router.stats()` method and wrote 7 passing tests — all green
- ✓ Completed in 196s (~3 min), no timeout
- ⚠️ Agent modified `node_modules/router/index.js` instead of Express's own `lib/router/index.js` — found the vendored dependency, not the actual source file. Task succeeded but in a slightly wrong location.
- ⚠️ `ROUTER_STATS_SUMMARY.md` auto-created but not explicitly asked for — agent gold-plates a bit
- **Verdict:** Strong performance overall. The wrong-file issue is worth noting as a codebase navigation quirk — agent doesn't always distinguish source from vendored deps.

### T3 — Multi-session continuity (2026-03-26)
- ✓ Agent completed the task (bookstore API with all endpoints working)
- ✗ Agent never created TASK.md — continuity tracking mechanism not used
- ✗ Tests were checking wrong workspace path (`/home/node/workspace` instead of `/home/node/.openclaw/workspace`)
- **Note:** T3 result was partially misleading due to path bug — files were actually created in the right place

### T4 — Error recovery (2026-03-26)
- ✓ Agent correctly diagnosed `MODULE_NOT_FOUND` error in 26s
- ✓ Identified dead `require('nonexistent-package')` and removed it
- ✓ Verified server starts and GET / returns 200
- No issues observed — agent performs well on straightforward error recovery

---

### ISSUE-25: Silent fallback warning (2026-03-26)
**Problem:** When the clawbox container is stopped or port 18790 is unreachable, `clawbox run/chat/task` silently falls back to the embedded host agent. User gets a response, but from the wrong agent — work in the container is not used, and work done goes nowhere useful.
**Fix:** Added `assert_container_running` helper to the clawbox CLI. Called before `cmd_run`, `cmd_chat`, `cmd_task`. Prints a clear warning and exits 1 if the container is not running or port 18790 is closed. ✅ Fixed 2026-03-26.

---

## Bug Fixes Found During Testing

### ISSUE-29: Wrong workspace path in test scripts
**Problem:** All test scripts (T1, T3, T4) reference `/home/node/workspace` but the actual container workspace is `/home/node/.openclaw/workspace`. This caused T3's TASK.md and file existence checks to always fail even when files were present.
**Fix:** Updated all three test scripts to use the correct path. ✅ Fixed 2026-03-26.

---

## Phase 1 — Bug Fixes (immediate)

### ISSUE-25: Container OOM on heavy builds
**Problem:** 512MB is too tight for Prisma + React + Vite + npm install simultaneously. Container silently exits, CLI falls back to embedded agent with zero warning.
**Fix:** Bump memory limit to 1GB in docker-compose.yml. Add OOM detection to `clawbox start` — if container exits within 60s of start, check if OOM was the cause and print a clear error.

### ISSUE-27: Port conflict on start
**Problem:** If ports 18790 or 3000 are already bound (e.g. previous container still running), `docker compose up` silently succeeds but with no port bindings. CLI connects to wrong instance.
**Fix:** Pre-flight check in `clawbox start` and `setup.sh` — detect if ports are in use, print which process is holding them, refuse to start until clear.

### ISSUE-28: File ownership mismatch (docker exec cp)
**Problem:** Files copied via `docker cp` from macOS (UID 501) are unreadable by the container agent (UID 1000).
**Fix:** Add `clawbox cp <src> <dest>` command that wraps `docker cp` + auto-runs `chown node:node` inside the container.

---

## Phase 2 — Long-running task improvements

The agent currently has no good way to handle tasks that take >5 minutes. Problems:
- No progress visibility (you just wait)
- Context window fills up on very long coding tasks
- Agent can get "stuck" with no way to self-recover
- No way to resume an interrupted task

### Ideas to explore:
- **Task journal:** Agent writes a structured `TASK.md` at the start of every long task (goal, steps, current status). Persists in the workspace. Can be read on resume.
- **Checkpoint pattern:** For multi-step tasks, agent commits after each major step. If something goes wrong, git log shows exactly where it got to.
- **Progress streaming:** Can we expose gateway events to the host so long-running tasks show progress without needing to poll?
- **Self-recovery prompts:** If the agent gets a tool error, does it retry intelligently? Test and document the failure modes.
- **Task timeout + handoff:** If a task runs >10 min, agent summarizes what it did and what's left. Human can then restart with context.

---

## Phase 3 — Interaction improvements

Current interaction: `clawbox run "message"` or `clawbox chat` (TUI). Both are fine but rough around the edges.

### Ideas to explore:
- **`clawbox ask`** — shorter alias, maybe with `-f file` to pass a file as context
- **Persistent task mode:** `clawbox task "build X"` — agent works on it in the background, you can check status with `clawbox status`, get a summary when done
- **Context injection:** `clawbox run --context ./src/ "refactor the auth module"` — auto-attaches files as context
- **Session naming:** `clawbox chat --session myproject` — named sessions so you can have separate conversation threads per project
- **Output modes:** `--json` for scripting, `--quiet` for just the final answer, `--verbose` for full tool trace

---

## Phase 4 — New test categories

Replace the stale A-F rotation with tests that actually probe open questions:

### T1 — Long-running task handling
Give the agent a task that takes 10-15 minutes (build a full React app with auth, multiple pages, real routing). Measure: does it make progress checkpoints? Does it get stuck? Can it recover from an error mid-way? What happens when context window fills?

### T2 — Context window stress
Feed the agent a large codebase (clone a real OSS project with 100+ files). Ask it to make a specific change. Does it navigate the codebase intelligently or get lost?

### T3 — Multi-session continuity
Start a task, stop mid-way (`clawbox stop`), restart, and ask the agent to continue. Does it pick up from where it left off? What context does it retain?

### T4 — Error recovery
Deliberately introduce errors during a task (kill a dependency, corrupt a file, break the test suite). Does the agent notice, diagnose, and recover? Or does it spiral?

### T5 — Real-world project onboarding ✅ 2026-03-26
Clone a non-trivial open source project (e.g. a medium-sized Express app). Ask the agent to: (1) understand the codebase, (2) add a new feature, (3) write tests, (4) make sure existing tests pass. Measure quality and completeness.

**Results (2026-03-26):**
- ✓ Agent correctly summarized architecture in a few sentences
- ✓ Created production-quality rate limiter middleware (zero external dependencies, IP-based, configurable)
- ✓ Wired middleware into app with env-var configuration (RATE_LIMIT, RATE_WINDOW_MS)
- ✓ Wrote 9 comprehensive rate limiter tests covering happy path, error path, headers, window reset, custom options
- ✓ 18/18 tests passing — 9 new + all 9 existing (zero regression)
- ✓ Completed in 222s (~3.5 min) — well within timeout
- ⚠️ Test scaffold had a missing directory creation step (mkdir -p src/routes) — fixed in T5 script
- ⚠️ Agent also auto-created IMPLEMENTATION_SUMMARY.md — slight gold-plating but harmless
- **Verdict:** Strong end-to-end performance. Agent reads code selectively, produces working features, doesn't break existing tests. Ready for harder tasks (ISSUE-5 from Phase 3: real project from GitHub).

### T6 — Concurrent task handling
Run two separate `clawbox run` commands simultaneously pointing at different workspaces. Do they interfere? Are sessions properly isolated?

### T7 — UX / friction audit
Time how long it takes a hypothetical new dev to go from zero to running a task. Where do they get confused? What's the first thing that breaks? What docs are missing?
