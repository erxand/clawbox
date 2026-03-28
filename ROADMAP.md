# Clawbox Roadmap

## Test Results

### T2 — Context window stress (2026-03-26)
- ✓ Agent navigated 141-file Express.js codebase selectively (no context overload)
- ✓ Added `router.stats()` method and wrote 7 passing tests — all green
- ✓ Completed in 196s (~3 min), no timeout
- ⚠️ Agent modified `node_modules/router/index.js` instead of Express's own `lib/router/index.js` — found the vendored dependency, not the actual source file. Task succeeded but in a slightly wrong location.
- ⚠️ `ROUTER_STATS_SUMMARY.md` auto-created but not explicitly asked for — agent gold-plates a bit
- **Verdict:** Strong performance overall. The wrong-file issue is worth noting as a codebase navigation quirk — agent doesn't always distinguish source from vendored deps.

### T3 — Multi-session continuity (2026-03-26, re-run 2026-03-27, re-run 2026-03-27 #2)
- ✓ Agent completed the task both sessions (bookstore API with all endpoints working)
- ✓ GET /books, GET /books/1, POST /books, DELETE /books/1 all return correct responses
- ✓ Session 2 agent reconstructed the full API in a fresh container start (state persisted via volume)
- ✗ Agent creates TASK.md inside the project subdirectory (e.g. `bookstore-api-new/TASK.md`) instead of `/home/node/workspace/TASK.md` — test now searches recursively for TASK.md anywhere in workspace
- ✗ Session 2 agent said "workspace was reset, let me recreate" instead of reading existing TASK.md — it rebuilt from scratch rather than truly continuing
- **Root cause:** Agent doesn't proactively look for TASK.md before starting; it assumes a fresh state. seed/AGENTS.md could be more explicit about checking for existing project state on session start.
- **Fix applied (2026-03-27):** T3 script now searches workspace recursively for TASK.md, curl checks run inside container (ports not mapped to host by default), node_modules filtered from file listings
- **Fix applied (2026-03-27 #2, ISSUE-32):** Updated seed/AGENTS.md — (1) task journal now required for ALL project tasks (not just >5min ones); (2) added explicit "stop early / handoff" section with instructions to update TASK.md before stopping; (3) clarified TASK.md should go inside the project dir. Also updated T3 `wait_for_agent` to search recursively for TASK.md. Re-run results:
  - ✓ Session 1 created TASK.md with proper plan (project startup + handoff section)
  - ✓ Session 2 continued correctly — TASK.md shows session 2 work layered on session 1
  - ⚠️ Session 2 still says "workspace was reset" but this is misleading — agent actually DID read TASK.md and continued properly (GET /books shown as done, new endpoints added correctly)
  - **Verdict:** Continuity now working. "Workspace was reset" phrasing is benign/cosmetic — agent behavior is correct. ISSUE-32 closed.

### T4 — Error recovery (2026-03-26)
- ✓ Agent correctly diagnosed `MODULE_NOT_FOUND` error in 26s
- ✓ Identified dead `require('nonexistent-package')` and removed it
- ✓ Verified server starts and GET / returns 200
- No issues observed — agent performs well on straightforward error recovery

### T1 — Long-running task (2026-03-27 runs)
**Run 1 (2026-03-27 08:41):** Agent built full-stack task manager app. TASK.md created, 5 commits made.
- Result file reported "Frontend not reachable (HTTP 404)" and "API not reachable (HTTP 000)" → **FALSE NEGATIVES**
- Root cause: test checked only `localhost:3000/` (root), which returns 404 for API servers. Frontend was at 8080, not checked.

**Run 2 (2026-03-27 10:54):** Same task, same app. 41/41 tests passing, both servers running, 5 commits.
- Result file showed same false negatives. Post-hoc manual check confirmed the app was fully working.

**Fix (2026-03-27 — ISSUE-35):** T1 endpoint detection overhauled:
- New `check_port_smart` function probes multiple paths per port (`/tasks`, `/api/tasks`, `/api`, `/health`, `/login`, etc.)
- Any non-000 response = server is alive (401 = auth working, 302 = redirect, 200 = success)
- Explicit `npm test` run inside container for definitive pass/fail — most reliable signal
- `SERVER_ALIVE` flag now set correctly when any port has a responding server

**Verified against live container:** port 3000 → 401 at `/api/tasks` (auth gating works), port 8080 → 200 (frontend), 41/41 tests passing. ✅ ISSUE-35 Fixed 2026-03-27

---

### ISSUE-24: Conflicting instances — configurable gateway port (2026-03-27) ✅ Fixed
- `docker-compose.yml` now uses `${GATEWAY_PORT:-18790}` for the host port mapping
- `setup.sh` pre-flight check detects port conflicts before starting; prints clear error + how to use alternative port
- `clawbox` CLI reads `GATEWAY_PORT` env var throughout (start/stop/status/run/chat/task/logs/upgrade/clean)
- Help text documents `GATEWAY_PORT` with usage examples
- Multiple instances can run simultaneously: `GATEWAY_PORT=18791 clawbox start`

### ISSUE-25: Silent fallback warning (2026-03-26)
**Problem:** When the clawbox container is stopped or port 18790 is unreachable, `clawbox run/chat/task` silently falls back to the embedded host agent. User gets a response, but from the wrong agent — work in the container is not used, and work done goes nowhere useful.
**Fix:** Added `assert_container_running` helper to the clawbox CLI. Called before `cmd_run`, `cmd_chat`, `cmd_task`. Prints a clear warning and exits 1 if the container is not running or port 18790 is closed. ✅ Fixed 2026-03-26.

### ISSUE-30: Concurrent requests silently queue ✅ Fixed 2026-03-27
**Problem:** When two `clawbox run` commands fire simultaneously, the gateway serializes them — task B waits for task A to finish before starting. There's no warning, no queued-task indicator, and no ETA. Users expecting parallelism get silent delay.
**Fix:** Implemented a PID-based lock file (`~/.clawbox-lock`). When a second `run`/`chat`/`task` is called while one is in-flight, the CLI prints:
```
⏳ Another Clawbox task is already running (PID 12345).
   Your request will be queued and start when the current task completes.

   To check what's running:  clawbox task-status
   To cancel and run yours:  kill 12345 && clawbox run "..."
```
The lock is acquired before calling the gateway and released on exit, interrupt, or termination. Stale locks from crashed processes are auto-cleaned (checks `kill -0 <pid>` liveness).

### ISSUE-32: T3 session 2 rebuilds from scratch instead of resuming from TASK.md ✅ Fixed 2026-03-27
**Problem:** When asked to "continue the bookstore API from where you left off. Check TASK.md for context," the agent says "the workspace was reset, let me recreate the project" and rebuilds from scratch — ignoring the TASK.md it created in session 1. This defeats the purpose of the continuity test.
**Root cause:** Two issues: (1) AGENTS.md only required task journals for tasks >5min, so short session-1 tasks never created TASK.md; (2) the TASK.md that DID get created was in a subdirectory, not the root.
**Fix applied:** Updated `seed/AGENTS.md`: task journal is now required for ALL project tasks regardless of duration. Added explicit "stop early / handoff" instructions. Updated T3 test to search recursively for TASK.md. Applied fix directly to running container via volume update.
**Result:** TASK.md now created reliably. Session 2 correctly layers work on session 1 state. Agent says "workspace was reset" but behavior is correct — phrase is cosmetic. ✅

### ISSUE-33: Test scripts used host curl for endpoints that are container-internal (2026-03-27)
**Problem:** T1, T3 test scripts used `curl http://localhost:3000/...` from the host, but ports 3000/3001 are commented out in docker-compose.yml by default. All endpoint checks returned FAIL even when the server was running fine inside the container.
**Fix applied:** T1 and T3 now use `docker exec "$CONTAINER" sh -c "curl ..."` to check endpoints from inside the container. ✅

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

### ISSUE-28: File ownership mismatch (docker exec cp) ✅ Fixed
**Problem:** Files copied via `docker cp` from macOS (UID 501) are unreadable by the container agent (UID 1000).
**Fix:** `clawbox cp <src> <dest>` command wraps `docker cp` + auto-runs `chown node:node` inside the container. Already implemented.

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
- **Context injection:** `clawbox run --context ./src/ "refactor the auth module"` — auto-attaches files as context ✅ **Implemented (2026-03-27)** — `--context <file|dir>` prepends file contents to the message (skips node_modules, .git, binaries, files >10KB; caps at 50 files / 64KB). Also added `--thinking <level>` flag to `run`/`ask`.
- **Session naming:** `clawbox chat --session myproject` — named sessions so you can have separate conversation threads per project
- **Output modes:** `--json` for scripting, `--quiet` for just the final answer, `--verbose` for full tool trace ✅ **Implemented (2026-03-27)** — `--quiet`/`-q` sends banners to stderr, response-only on stdout; `--json`/`-j` emits `{response, elapsed_ms, timestamp, context_files}` as valid JSON. Both work with `--context`. T9 test: 18/18 pass.

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

### T6 — Concurrent task handling ✅ 2026-03-26
Run two separate `clawbox run` commands simultaneously pointing at different workspaces. Do they interfere? Are sessions properly isolated?

**Results (2026-03-26):**
- ✓ Both tasks completed — no timeouts (A: 63s, B: 114s total wall time)
- ✓ Task A: math.js + 18 tests, all passing
- ✓ Task B: strings.js + 29 tests, all passing
- ✓ Zero cross-contamination — each task wrote only to its own directory
- ⚠️ Tasks ran **sequentially, not truly in parallel** — Task B took an extra ~50s beyond A's completion, suggesting the gateway serializes concurrent requests into a queue
- ⚠️ The 2-second stagger between requests means task B waited for task A to complete before starting — this is the main finding
- **Verdict:** Isolation is clean. But clawbox does NOT handle true parallelism — concurrent requests queue, not interleave. For users expecting background parallelism (e.g. running two builds at once), this is a documentation gap. The behavior is actually safe, but should be explicitly documented.
- **Next step:** ISSUE-30 below — document the sequential-session behavior and add a warning to the CLI if a second request arrives while one is in-flight.

### T7 — UX / friction audit ✅ 2026-03-26
Time how long it takes a hypothetical new dev to go from zero to running a task. Where do they get confused? What's the first thing that breaks? What docs are missing?

**Results (2026-03-26):**
- ✓ 34 pass, 3 warn, 0 fail across 37 checks
- ✓ Container starts in **9s** (warm image), first task response in **6s** — excellent latency
- ✓ All core CLI commands present in help output, CLAWBOX_DIR env var documented
- ✓ All error paths (run/task/cp with no args, unknown command) show helpful messages
- ✓ assert_container_running warnings work correctly for run and chat
- ✓ README has troubleshooting section, token-is-irrelevant note is present
- ⚠ README Quick Start showed raw `openclaw` commands instead of `clawbox run` — **fixed**
- ⚠ `clawbox status` didn't print the `ws://` URL for copy-paste — **fixed** (now shows connect hint)
- ⚠ T7 test had a false-negative on `ask` alias detection (grep pattern wrong) — **fixed**
- **Verdict:** Very strong UX baseline. No friction failures. The two fixes above (README + status) remove the last rough edges for new users.
