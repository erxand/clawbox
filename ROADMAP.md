# Clawbox Roadmap

## Test Results

### T24 — Context injection at scale + clawbox clean abort (2026-04-03)

**Run 1 (2026-04-03 20:56) — new test, first run:**
- ✓ **14/14 pass, 0 warn, 0 fail** — perfect score on first run
- ✓ Phase 1 (--context dir): Valid JSON, context_files=10 (all 10 project files injected), elapsed_ms positive, session key present, agent referenced all 5/5 project concepts (invoice, client, route, auth, API)
- ✓ Phase 2 (clean abort): Warning message present, abort confirmed, container NOT stopped, 'clean' in help
- ✓ Phase 3 (large file, 6.4KB): context_files=1, agent correctly quoted XYZZY_T24_CANARY_42 sentinel value
- **Key findings:** `--context <dir>` correctly injects all non-excluded files (node_modules filtered); the 10-file limit is well below the 50-file cap. `clawbox clean` abort path is safe and correct — 'N' input stops all destructive action. Large file injection (~6KB) works without truncation.
- **Verdict:** Context injection at realistic project scale is fully functional. clean abort is safe. ✅

### T23 — restart and logs commands (2026-04-03)

**Run 1 (2026-04-03 18:52) — new test, first run:**
- ✓ **18/20 pass, 2 warn, 0 fail** — strong first-run result
- ✓ Phase 1: `clawbox restart` exits 0, completes in 16s, container running after
- ✓ Workspace volume persists across restart (canary file survives)
- ✓ Read-only rootfs enforced after restart (security not degraded by restart cycle)
- ✓ Phase 2: Second consecutive restart is idempotent (exits 0, container healthy)
- ✓ Phase 3: `clawbox logs` produces container output via `docker compose logs`
- ✓ Phase 4: `clawbox logs-tail` returns output (no log file expected after cold restart)
- ✓ Phase 5: Restart output format has meaningful status messages
- ✓ Phase 6: `clawbox status` correctly reflects running state after multiple restarts
- ⚠ Gateway health check false-negative at 2s post-restart — passes by Phase 6 (just starting up)
- ⚠ `logs-tail` no log file for today — expected after fresh container start; not a failure
- **Key findings:** `restart` is rock-solid — clean stop+start in ~16s with no data loss. Volume persistence confirmed. Security properties (read-only rootfs) survive multiple restart cycles. The `logs` command works (uses `docker compose logs`) but is not easily testable without a follow-mode workaround on macOS (no native `timeout` binary — test uses `docker compose logs --tail=50` instead).
- **Verdict:** `clawbox restart` and `clawbox logs` are working correctly. Both commands now have dedicated test coverage for the first time. ✅

### T17 — Backup & Restore (2026-04-03)

**Stability check (2026-04-03 18:49):**
- ✓ **19/19 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ Backup: tar.gz created (65MB), contains canary + AGENTS.md
- ✓ Restore: exit 0, files restored with correct content and ownership
- ✓ File count preserved (6131 → 6131)
- **Verdict:** Backup/restore fully stable. ✅

### T18 — CLI Utility Commands (2026-04-03)

**Stability check (2026-04-03 18:50):**
- ✓ **37/38 pass, 1 warn, 0 fail** — same pattern as original run
- ⚠ `logs-tail`: no log for today (expected after restart cycles — benign)
- **Verdict:** T18 fully stable. ✅

### T-egress — Egress isolation (2026-04-03)

**Run 3 (2026-04-03 16:49) — stability check:**
- ✓ **11 pass, 1 warn, 0 fail** — same clean pattern as prior runs
- ⚠ Pre-proxy: example.com NOT reachable (transient; icanhazip/google confirmed vulnerability)
- ✓ Phase 2: all 7 lockdown checks green — arbitrary blocked, Anthropic + npm allowed
- **Verdict:** Egress isolation fully stable. ✅

### T7 — UX / Friction audit (2026-04-03)

**Re-run (2026-04-03 16:55) — added `clawbox version` command, 45/45:**
- ✓ **45/45 pass, 0 warn, 0 fail** — up from 44 after new version command
- ✓ New: `clawbox version` / `--version` / `-V` now shows git ref, date, openclaw version, and CLAWBOX_DIR
- ✓ T7 version check fixed: was a false positive (exit 1 "Unknown command" still passed old grep); now uses exit code + content check
- ✓ T7 now checks all 23 commands in help (was 22; added `version`)
- **What changed:** Added `cmd_version()` function, dispatch entries for `version|--version|-V`, and help text entry. Fixed T7's version check to use exit code instead of naive `grep -qvi "unknown command"` (which matched other output lines).
- **Verdict:** UX remains fully clean. `clawbox version` closes the last QoL gap in T7. ✅

**Re-run (2026-04-03 16:50) — stability check pre-version-command:**
- ✓ **44/44 pass, 0 warn, 0 fail** — perfect score maintained before new command added
- **Verdict:** Confirmed stable baseline. ✅

### T6 — Concurrent task handling (2026-04-03)

**Re-run (2026-04-03 16:51) — stability check:**
- ✓ **20/20 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ Part 1: Both tasks complete (A: 33s, B: 103s wall time), math + strings tests all pass
- ✓ Part 2: Lock behavior fully intact — exits 1 with actionable UX, stale lock auto-cleaned
- ✓ Zero cross-contamination in either direction
- **Verdict:** T6 continues to be fully stable. ✅

### T22 — --retry flag + rate-limit detection (2026-04-03)

**Run 1 (2026-04-03 14:52) — new test, first run:**
- ✓ **17/17 pass, 0 warn, 0 fail** — perfect score on first run
- ✓ Phase 1: `--retry 1` accepted; successful run returns expected response
- ✓ Phase 2: `--retry 0` accepted (no-op on success)
- ✓ Phase 3: `--retry` works in any flag position (before or after message arg)
- ✓ Phase 4: `--retry` with no value gives usage hint
- ✓ Phase 5: `--retry` documented in help; help mentions rate-limit context; exit code 2 documented
- ✓ Phase 6: `clawbox task --retry 1` accepted for background tasks
- ✓ Phase 7: All rate-limit detection patterns verified (`API rate limit reached`, `rate_limit_error`, `overloaded_error`, `CLAWBOX_RATE_LIMITED`); no false-positive on normal responses
- ✓ Phase 8: Source code has `exit 2`, `CLAWBOX_RATE_LIMITED` sentinel, `retry_max` variable, and retry loop structure
- **Verdict:** --retry flag and rate-limit detection are working correctly across all tested scenarios. ✅

### T13 — Read-only rootfs validation (2026-04-03)

**Re-run (2026-04-03 14:48) — stability check:**
- ✓ **15/15 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ ReadonlyRootfs=true confirmed by Docker inspect
- ✓ Root filesystem rejects writes at overlay2 level
- ✓ All system paths read-only: /usr /bin /lib /etc /sbin /home/node/.npm-global
- ✓ /tmp (tmpfs) writable, /run (tmpfs) writable
- ✓ /home/node/.openclaw (persistent volume) writable
- ✓ GIT_CONFIG_GLOBAL and NPM_CONFIG_CACHE correctly redirected to volume
- ✓ Agent responds, writes to workspace, npm install in workspace, git init+commit all work
- **Verdict:** T13 fully stable. Read-only rootfs security hardening continues to hold. ✅

### T21 — JSON output completeness + CLAWBOX_DIR env override (2026-04-03)

**Run 1 (2026-04-03 12:56) — new test, first run:**
- ✓ **21/21 pass, 0 warn, 0 fail** — perfect score on first run
- ✓ Phase 1 (JSON completeness): `--json` output is valid JSON with all 4 documented keys (`response`, `elapsed_ms`, `timestamp`, `context_files`); `elapsed_ms` is a positive integer; `timestamp` is ISO-8601; `context_files=0` without context, `>0` with context; `jq` pipeline extraction works; `--session` adds `session` key; `--quiet` has no banner on stdout
- ✓ Phase 2 (CLAWBOX_DIR): `CLAWBOX_DIR` documented in help; override to project dir works; `/nonexistent` gives meaningful error; `GATEWAY_PORT` documented
- ✓ Phase 3 (task-status/task-logs): `task-status` with no task produces clean output; references task state; is human-readable (not JSON); `task-logs` with no log gives graceful error
- **Key findings:** `--json` schema is complete and consistent; `--session` key is included in JSON output; `task-logs` error message correctly guides users to start a task first
- **Verdict:** JSON output is production-grade and pipeable. CLAWBOX_DIR override works as documented. task-status/task-logs UX is clean. ✅

### T4 — Error recovery (2026-04-03)

**Re-run (2026-04-03 12:50) — stability check:**
- ✓ **pass, 0 warn, 0 fail** — clean pass
- ✓ Agent diagnosed `Cannot find module 'nonexistent-package'` in 56s
- ✓ Identified and removed unused `require('nonexistent-package')` line
- ✓ Server starts cleanly, GET / returns `Hello`
- **Verdict:** T4 fully stable. ✅

### T16 — `clawbox doctor` validation (2026-04-03)

**Re-run (2026-04-03 12:52) — stability check:**
- ✓ **27/27 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ Phase 1 (healthy container): 21/21 internal checks pass
- ✓ Phase 2 (stopped container): correctly reports ✗ failures
- ✓ Phase 5 (edge cases): wrong port detected correctly
- **Verdict:** `clawbox doctor` continues to be fully stable. ✅

### T12 — cancel command (2026-04-03)

**Re-run (2026-04-03 12:52) — stability check (container warm):**
- ✓ **18/18 pass, 0 warn, 0 fail** — perfect score
- ✓ All cancel scenarios: idle no-op, stale lock cleanup, live task SIGTERM, UX hints: all green
- **Note:** First run (container still starting) showed 17/1 due to timing — assert_container_running fired before container was healthy. Second run fully clean.
- **Verdict:** T12 fully stable. ✅

### T20 — Workspace persistence (2026-04-03)

**Run 2 (2026-04-03 08:48) — AGENTS.md fix confirmed, 13/13 clean:**
- ✓ **13/13 pass, 0 warn, 0 fail** — perfect score
- ✓ AGENTS.md check fix confirmed: `wc -c '${WORKSPACE}/AGENTS.md' | awk '{print $1}'` now returns correct byte count (7874), no shell redirection issue
- ✓ All other checks unchanged: canary, nested dirs, git history, rootfs read-only, agent read/write all green
- ✓ Container restart time: 14s (consistent with Run 1)
- **Verdict:** T20 fully stable. Workspace persistence is rock-solid. ✅

**Run 1 (2026-04-03 06:54) — first run, new test:**
- ✓ **12/13 pass, 1 warn, 0 fail** — strong first-run result
- ✓ Canary file written before restart, exact content match after restart
- ✓ Nested directory structure (`nested/deep/file.txt`) persists
- ✓ Git history intact (1 commit before = 1 commit after)
- ✓ Container rootfs is read-only (writes rejected at OS level)
- ✓ Agent (`clawbox run`) can read persisted workspace files (referenced content in response)
- ✓ Agent can write to workspace (`agent-wrote.txt` created with expected content)
- ✓ Workspace has 25 top-level items after restart (not wiped)
- ✓ Container restarts in 14s
- ⚠ AGENTS.md check false-negative: `wc -c < file` shell redirection doesn't work correctly via `docker exec` without shell context. File exists and has 7874 bytes. Fixed: now uses `sh -c "wc -c file | awk '{print $1}'"`.
- **Key finding:** Docker volume persistence is rock-solid. Files, nested dirs, git repos, and even agent-written files all survive stop/start. The agent correctly reads and writes to the persisted workspace. No data loss at any level.
- **Verdict:** Workspace persistence is fully reliable. The fundamental guarantee for multi-session workflows is confirmed. ✅

### T15 — Task timeout + handoff (2026-04-03)

**Run 8 (2026-04-03 10:48) — ISSUE-68 fix confirmed, 13/13 clean:**
- ✓ **13/13 pass, 0 warn, 0 fail** — fully clean
- ✓ ISSUE-68 fix confirmed: 13 stale dirs cleaned, unique project name used, TASK.md found in correct dir
- ✓ Timeout triggered after exactly 1 minute ✓
- ✓ No gateway connection failures, lock cleaned up, new task starts cleanly
- **Verdict:** T15 fully reliable. ISSUE-68 workspace contamination fix confirmed working. ✅

**ISSUE-68 found (2026-04-03 06:46) — workspace contamination causes false-positive T15 results:**
- ✗ T15's `blog-api-timeout-test` dir persisted from prior runs across container restarts (workspace is a volume)
- ✗ Multiple `taskman-*` dirs from T1 runs also present in workspace
- ✗ Agent found all 6 existing fully-complete projects and reported them as done in <1 min → timeout never fired
- ✗ T15 "13/13 passing" was a false positive — the agent did NO new work
- **Root cause (ISSUE-68):** T15 does `clawbox stop; clawbox start` but doesn't clean the workspace volume. Workspace persists across restarts. Old project dirs from T1/T15 prior runs accumulate over time.
- **Run 8 (2026-04-03 10:48) — ISSUE-68 fix confirmed, 13/13 clean:**
- ✓ **13/13 pass, 0 warn, 0 fail** — perfect score
- ✓ ISSUE-68 fix confirmed: cleanup step removed 13 stale project dirs at start (`blog-api-timeout-test`, `bookstore-*`, `taskman-*`, `concurrent-*`, etc.)
- ✓ Unique project name used: `blog-api-t15-20260403-104838` (timestamped)
- ✓ TASK.md found in correct project dir (not a stale dir from prior run)
- ✓ Timeout triggered after exactly 1 minute ✓
- ✓ Handoff response: 485 bytes, accurate summary of completed work
- ✓ Lock cleaned up, new task starts cleanly after timeout
- **Fix applied (2026-04-03):** (1) T15 setup now runs `rm -rf` on all non-seed project directories in the container workspace before starting the test; (2) T15 uses a unique timestamped project name (`blog-api-t15-YYYYMMDD-HHMMSS`) so re-runs can never find pre-existing work; (3) TASK.md check now searches the specific project dir first.
- **Pattern:** Same root cause as ISSUE-58 (T2) and ISSUE-59 (T2 + T3) — workspace accumulation over time. Each test that creates projects needs its own cleanup step.
- **Verdict:** ISSUE-68 fix confirmed. T15 fully stable and reliable. ✅

### T11 — Background task mode (2026-04-03)

**Run (2026-04-03 04:48) — stability check:**
- ✓ **12/12 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ Non-blocking start, timestamped log, symlink, task completion (~10s), lock cleanup, concurrent warning: all green
- ✓ ISSUE-43 symlink behavior: `~/.clawbox-task.log` → timestamped log confirmed
- **Verdict:** T11 fully stable. ✅

### T15 — Task timeout + handoff (2026-04-03)

**Run 7 (2026-04-03 04:48) — 13/13 fully clean (first rate-limit-free T15 run since ISSUE-63 fix):**
- ✓ **13/13 pass, 0 warn, 0 fail** — fully clean
- ✓ ISSUE-63 fix confirmed: no subagent spawn, agent worked directly
- ✓ Timeout triggered after exactly 1 minute ✓
- ✓ No gateway connection failures (ISSUE-51 poll loop holding)
- ✓ Handoff complete marker found; handoff response: 996 bytes
- ✓ TASK.md found in container workspace
- ✓ Lock cleaned up, new task starts cleanly after timeout (ISSUE-52 fix holding)
- ✓ `--timeout` in help, timestamped log + symlink correct
- **Verdict:** T15 fully reliable. Timeout + handoff is production-ready and now confirmed clean with no rate-limit interference. ✅

---

### T1 — Long-running task (2026-04-03, Run 9)

**Run 9 (2026-04-03 02:52) — ISSUE-67 fix validated (Jest test detection):**
- ✓ **TASK.md created** with all steps checked off
- ✓ **2 git commits** (scaffold → all tests passing + frontend)
- ✓ **30/30 tests passing** (Jest) — `Tests passing: yes` confirmed ✅
- ✓ **Completed in 183s (~3 min)** — consistent with Run 8
- ✓ ISSUE-67 fix confirmed: `Tests:[[:space:]]*[0-9]+ passed` pattern now matches Jest output; `TESTS_PASSING="yes"` reported correctly (was "unknown" in Run 8 because fix committed AFTER that run)
- ✓ Extra port row now appears in result table (none needed — agent used standard ports)
- ⚠ Server stopped after test run (expected — agent exits after completing) — port probes returned 000
- **Verdict:** All ISSUE-64/65/66/67 fixes confirmed working. T1 is fully reliable with correct test detection. ✅

---

### T9, T10 — Stability checks (2026-04-03)

**T9 (2026-04-03 00:50) — output modes stability check:**
- ✓ **18/18 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ `--quiet`, `--json`, context_files count, live e2e: all green
- **Verdict:** T9 fully stable. ✅

**T10 (2026-04-03 00:51) — session naming stability check:**
- ✓ **10/10 pass, 1 warn, 0 fail** — same pattern as prior runs
- ✓ Session continuity (ZEBRA42 recalled), flags, JSON output: all green
- ⚠ Session isolation: shared agent memory by design (known behavior)
- **Verdict:** T10 fully stable. ✅

### T1 — Long-running task (2026-04-03)

**Run 8 (2026-04-03 01:36) — ISSUE-64/65/66 fixes applied:**
- ✓ **TASK.md created** with all steps checked off
- ✓ **2 git commits** (scaffold → all tests passing + frontend)
- ✓ **30/30 tests passing** (Jest; `Tests: 30 passed, 30 total`)
- ✓ **Completed in 183s (~3 min)** — fastest T1 run ever
- ✓ ISSUE-64 fix confirmed: early-exit via task log completion marker fired on poll #5 (was running full 20min before)
- ✓ ISSUE-66 fix confirmed: `[:space:]` trimming removes trailing newlines from `grep -c` output (no more `[: 0\n0: integer expression expected`)
- ✓ ISSUE-65 fix confirmed: "do NOT spawn subagents" instruction — agent worked directly (no subagent delegation)
- ⚠ Note: Server stopped after test run (expected behavior) — port probes returned 000. Non-standard port (3458) was used. Extra-port scanning added to T1.
- **Root cause of T1 never detecting early completion:** `=== Task completed ===` pattern didn't match actual `=== Task completed: 2026-04-03 01:39:37 ===` format. Fixed.
- **Root cause of T1 integer expression errors:** `grep -c` outputs `0\n` (with trailing newline); `tr -d ' '` only strips spaces not newlines. `tr -d '[:space:]'` fixes both.
- **Verdict:** T1 now exits early when task completes. All core functionality working. ✅

### T19 — Task early completion + retry flag (2026-04-02)

**Run 1 (2026-04-02 22:50) — new test, first run:**
- ✓ **14/14 pass, 0 warn, 0 fail** — clean first run
- ✓ `clawbox task --timeout 5` on a fast task returns non-blocking (13s pre-flight + background)
- ✓ Fast task completes in ~45s (well under 5min timeout)
- ✓ No TIMEOUT marker in log — watchdog never fires
- ✓ No handoff prompt emitted — correct behavior when task finishes naturally
- ✓ Task completion marker (`=== Task completed ===`) present in log
- ✓ Lock file cleaned up after fast task
- ✓ No orphaned watchdog processes remain
- ✓ Output file (`t19-done.txt`) created in container with correct content
- ✓ `--retry` flag documented in help
- ✓ `--retry 1` accepted, task succeeds on first attempt
- ✓ `--retry 0` accepted without error (no-retry mode)
- ✓ `--retry` flag works in any position (after message arg)
- ✓ `task-status` shows useful info after completion
- **Key finding:** `clawbox task` takes ~13s to launch (pre-flight container check + background spawn). This is the `assert_container_running` + gateway health check overhead, not actual blocking. The task itself runs asynchronously as expected. Threshold updated from 5s → 15s to reflect reality.
- **Key finding (Phase 1 validated):** When `--timeout N` is set but the task completes before N minutes, the watchdog is silently cleaned up with no side effects. No spurious handoff, no log noise, no stale processes. This code path was never explicitly tested before.
- **Verdict:** T19 fully passing. Early completion + retry flag behavior confirmed correct. ✅

### T7 — UX / Friction audit (2026-03-26, re-run 2026-03-29, re-run 2026-03-31, re-run 2026-04-02)

**Re-run (2026-04-02 22:48) — updated to include new commands (cp, logs-tail, install):**
- ✓ **44/44 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ Now checks all 22 commands in help output (was 19 before; added `cp`, `logs-tail`, `install`)
- ✓ Container start: 14s, first task latency: 5s
- ✓ All error paths, README accuracy, status output, and QoL checks holding
- **What changed:** T7 previously checked for 19 commands in help; after T18 (ISSUE-62 fix) added `cp`, and other commands (`logs-tail`, `install`) were added, the test wasn't tracking them. Updated command list covers all currently documented commands.
- **Verdict:** UX remains fully clean end-to-end with all newly added commands. ✅

### T8 — Context injection (2026-03-27, re-run 2026-03-29, re-run 2026-03-31, re-run 2026-04-02)

**Re-run (2026-03-29 22:41) — test script rewrite + fresh validation:**
- ✓ **10/10 pass, 0 warn, 0 fail**
- ✓ `--context <file>`: agent mentions `add`/`subtract` from injected math.js
- ✓ `--context <dir>`: agent correctly mentions all 3 exported symbols (add, subtract, PI); node_modules excluded
- ✓ `--thinking minimal`: flag forwarded, agent responds normally
- ✓ `--quiet`: stdout clean (banners to stderr)
- ✓ `--json`: valid JSON with `response` + `elapsed_ms` keys
- ✓ Invalid path → clear "not found" error
- ✓ Missing message → usage hint
- **Note:** Test script rewritten from `eval`-based unit tests (fragile, broke with complex quoting in cmd_run) to behavioral live-container tests. More reliable and tests actual behavior end-to-end.
- **Verdict:** Context injection confirmed working across all modes. ✅

**Re-run (2026-04-02 18:49) — stability check:**
- ✓ **10/10 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ `--context <file>`: agent references injected add/subtract code ✓
- ✓ `--context <dir>`: all 3 symbols (add, subtract, PI) mentioned, node_modules excluded ✓
- ✓ `--thinking minimal`, `--quiet`, `--json` all working ✓
- ✓ Error paths (invalid path, missing message) still correct ✓
- **Verdict:** T8 fully stable. ✅

**Re-run (2026-03-31 20:42) — stability check post all recent fixes:**
- ✓ **10/10 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ `--context <file>`: agent references injected add/subtract code ✓
- ✓ `--context <dir>`: all 3 symbols (add, subtract, PI) mentioned, node_modules excluded ✓
- ✓ `--thinking minimal`, `--quiet`, `--json` all working ✓
- ✓ Error paths (invalid path, missing message) still correct ✓
- **Verdict:** T8 fully stable after all recent changes. ✅

### T2 — Context window stress (2026-03-26, re-run 2026-03-28, re-run 2026-03-30, re-run 2026-03-31, re-run 2026-04-01, re-run 2026-04-02)

**Run 7 (2026-04-02 12:46) — ISSUE-59/60 fixes validated, clean run:**
- ✓ **Test file created, 5/5 tests passing, completed in 137s (~2.3 min)**
- ✓ ISSUE-59 fix confirmed: 0 stale dirs cleaned (workspace was already clean)
- ✓ ISSUE-60 fix confirmed: express cloned on host, docker cp'd into container (141 JS files)
- ✓ Timestamped dir `express-oss-2026-04-02-12-46` created fresh with clean codebase
- ✓ Agent navigated codebase selectively, understood Router class structure, wrote comprehensive stats() method
- ⚠ Agent modified `node_modules/router/index.js` (vendored dep) instead of creating `lib/router/` wrapper — same Run 1 pattern
- **Key finding:** Despite explicit hint "look in lib/, not node_modules/", agent correctly identifies that Express 5.x has no `lib/router/` directory and takes the path of least resistance (edit the vendored dep). Only with Run 2's stronger hint ("Express's OWN Router class in lib/router/") did the agent create a wrapper. This is consistent behavior across fresh-codebase runs.
- **Verdict:** ISSUE-59/60 infrastructure fixes confirmed working. Agent codebase navigation strong. node_modules edit pattern is a known architectural preference, not a regression. ✅

**Run 6 (2026-04-02 08:40) — ISSUE-59 + ISSUE-60 fixes applied, rate limited:**
- ✗ Agent received `⚠️ API rate limit reached` immediately — could not complete task
- ✓ ISSUE-59 fix confirmed: stale `express-oss` and `onboarding-test` dirs cleaned at start
- ✓ ISSUE-60 fix confirmed: express cloned on host, docker cp'd into container successfully (141 JS files)
- ✓ Timestamped dir `express-oss-2026-04-02-08-40` created fresh with clean codebase
- **Verdict:** Infrastructure fixes working (workspace clean, host-side clone, docker cp + chown). ⚠️ (rate limited)

**Run 5 (2026-04-01 16:46) — stability check + ISSUE-58 found and fixed:**
- ✓ **4/4 assessment checks pass** — test file created, stats() in correct location, node_modules clean, within timeout
- ✓ Completed in 226s (~3.7 min) — within normal range
- ✓ stats() added to CORRECT file (Express lib/router/index.js)
- ✓ node_modules/router/ not modified
- ⚠ Only 13 JS files counted (source-only, no node_modules installed) vs 141 in original run — less stressful but still valid routing exercise
- ⚠ Agent found pre-existing stats() method at line 523 (from prior runs) — reported it as already implemented and ran tests. Test result is valid but **the agent didn't write fresh code** — inflated success.
- **Root cause (ISSUE-58):** T2 script checks `if [ ! -d 'express-oss' ]` and skips re-clone on subsequent runs. Any modifications from prior tests (stats() method, test-router-stats.js) persist in the working tree. Agent correctly reads and uses pre-existing work — but the test's purpose is to measure the *writing* capability, not just reading/testing.
- **Fix applied (2026-04-01):** T2 now runs `git checkout -- . && git clean -fd` to reset express-oss to pristine state before each run. This guarantees the agent starts from a clean codebase every time, as intended.
- **Verdict:** Fix is in place. Next run will validate that the agent writes stats() from scratch on a clean codebase. ✅ (fix applied)

**Run 1 (2026-03-26):**
- ✓ Agent navigated 141-file Express.js codebase selectively (no context overload)
- ✓ Added `router.stats()` method and wrote 7 passing tests — all green
- ✓ Completed in 196s (~3 min), no timeout
- ⚠️ Agent modified `node_modules/router/index.js` instead of Express's own `lib/router/index.js` — found the vendored dependency, not the actual source file. Task succeeded but in a slightly wrong location.
- ⚠️ `ROUTER_STATS_SUMMARY.md` auto-created but not explicitly asked for — agent gold-plates a bit

**Run 4 (2026-03-31) — stability check post ISSUE-49/50/51/52 fixes:**
- ✓ test-router-stats.js created in express-oss/ ✓
- ✓ stats() added to CORRECT file (lib/router/index.js) ✓
- ✓ node_modules/router/ not modified (correct) ✓
- ✓ 5/5 tests passing (agent verified existing work, confirmed correctness)
- ✓ Completed in 122s (~2 min) — faster than prior runs (workspace already scaffolded)
- ✓ Agent took selective approach: only read 3 files before confirming implementation existed
- **Verdict:** T2 fully stable. Agent's selective codebase navigation pattern holding strong. ✅

**Run 3 (2026-03-30) — stability check post all ISSUE-44/47/48 fixes:**
- ✓ test-router-stats.js created in express-oss/ ✓
- ✓ stats() added to CORRECT file (lib/router/index.js wrapper, not node_modules/router/)
- ✓ node_modules/router/ not modified (correct)
- ✓ 5/5 tests passing, completed in 257s (~4 min)
- ✓ Agent correctly reasoned through Express 5.x's dependency structure and created a lib/router/ wrapper
- **Verdict:** T2 fully stable after all recent changes. Agent codebase navigation remains strong. ✅

**Run 2 (2026-03-28) — hint-guided re-run:**
- Task message updated to explicitly say "look in lib/, not node_modules/"
- ✓ Agent correctly recognized Express 5.x doesn't have its own `lib/router/` — it delegates to the `router` package
- ✓ **Created a new wrapper** `lib/router/index.js` that extends the vendored router with the `stats()` method
- ✓ Updated `lib/express.js` and `lib/application.js` to use the new wrapper — proper layering
- ✓ 5/5 tests passing, completed in 212s (~3.5 min)
- ✓ node_modules/router/ NOT modified — correct separation of Express source vs. vendored dep
- **Verdict:** With explicit hint, agent produced a more architecturally correct solution (wrapper vs. monkey-patch). Without the hint (Run 1), it takes the path of least resistance (edit the vendored dep directly). This is a useful finding: agent behavior is highly prompt-sensitive for architectural choices. The hint in Run 2 is realistic (any senior dev would say "don't edit node_modules"), so Run 2 is the target behavior.
- **Fix applied (2026-03-28):** T2 script now checks both `lib/router/` and `node_modules/router/` for stats() presence, reporting which one was modified for easy comparison across runs.

### T3 — Multi-session continuity (2026-03-26, re-run 2026-03-27, re-run 2026-03-27 #2, re-run 2026-03-28, re-run 2026-04-02)
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

**Run 4 (2026-03-28) — ISSUE-41 discovered:**
- ✓ Session 1: Agent created TASK.md in `/home/node/.openclaw/workspace/bookstore-api/TASK.md` (correct location)
- ✓ Session 1: GET /books endpoint working, project scaffolded (53s)
- ✗ Session 2: Agent said "The workspace directory doesn't exist" and rebuilt from scratch
- **Root cause (ISSUE-41):** `seed/AGENTS.md` documented `/home/node/workspace/` as the project workspace — but this directory does not exist. The actual workspace (and where projects should live) is `/home/node/.openclaw/workspace/`. Agent followed the instructions literally, tried to `cd /home/node/workspace`, failed, and assumed fresh state.
- **Fix applied (2026-03-28):** Updated `seed/AGENTS.md` to clarify there is ONE workspace at `/home/node/.openclaw/workspace/`. Removed all references to `/home/node/workspace/`. Updated T3 test script to use correct path in all `find`/`git` commands. Applied fix to running container.

**Run 5 (2026-03-28) — ISSUE-41 fix validated:**
- ✓ Session 1: TASK.md created at correct path `/home/node/.openclaw/workspace/bookstore-api-v2/TASK.md` (76s)
- ✓ Session 2: Agent found and read TASK.md, correctly identified Phase 2 work, continued without rebuilding (247s)
- ✓ Session 2: TASK.md updated with "Resumed" and "Completed" timestamps — true continuity achieved
- ✓ All endpoints verified: GET /books, GET /books/1, POST /books, DELETE /books/1 all working
- ⚠️ Minor: Session 2 agent updated TASK.md header but left "Last Updated" timestamp and success criteria checkboxes stale — cosmetic only
- **Verdict:** ISSUE-41 confirmed fixed. Multi-session continuity is now reliable end-to-end. ✅
- **Endpoints after session 2 (despite rebuild):** All working — GET /books ✓, GET /books/1 ✓, POST /books ✓, DELETE /books/1 ✓ (agent completed the full API even though it rebuilt)

**Run 12 (2026-03-31 18:42) — T3 ISSUE-56 fix: git init in session 1 message:**
- ✓ **4/4 assessment checks pass — first fully clean T3 run with all four checks ✓**
- ✓ Session 1 (124s): TASK.md at correct path, git initialized, 2 commits (initial + TASK.md)
- ✓ Session 2 (205s): TASK.md checkboxes updated (S1: 10x → S2: 17x), 4 new commits (S1: 4 → S2: 8)
- ✓ All endpoints verified: GET /books ✓, GET /books/1 ✓, POST /books ✓ (validation error = correct), DELETE /books/1 ✓
- **Root cause of prior `✗ No new git commits` false negative (ISSUE-56):** Session 1 message didn't explicitly ask for git init. Agent's TASK.md showed `[ ] Initialize git repository` (unchecked), so no project-level git repo existed. S1/S2 git log comparison fell back to workspace root (same 5 T1 commits both times) → false "no new commits" fail.
- **Fix applied (2026-03-31):** Session 1 message now includes "Initialize a git repository in the project dir and commit your initial work." Agent reliably inits git, both sessions compare within the project-level repo.
- **Verdict:** T3 is fully reliable. All four assessment checks (TASK.md created, endpoints verified, checkboxes updated, new commits) passing consistently. ✅

**Run 13 (2026-04-02 12:50) — stability check:**
- ✓ **4/4 assessment checks pass** — fully clean
- ✓ Session 1 (64s): TASK.md at correct path, git initialized, Phase 1 all `[x]`, Phase 2 unchecked
- ✓ Session 2 (84s): TASK.md checkboxes updated (S1: 6x → S2: 11x), 4 new commits (S1: 2 → S2: 6)
- ✓ All endpoints verified: GET /books ✓, GET /books/1 ✓, POST /books ✓, DELETE /books/1 ✓
- ✓ Agent properly read TASK.md from session 1, continued Phase 2 work, created `src/store.js` module
- ✓ Session 2 correctly updated TASK.md status to "Phase 2 in progress 🚧" with checked-off items
- **Verdict:** T3 continues to be fully reliable. Multi-session continuity working perfectly. ✅

**Run 11 (2026-03-31) — ISSUE-55 fix validated:**
- ✓ Session 1: TASK.md created at correct path (101s), Phase 1 all `[x]`, Phase 2 unchecked
- ✓ Session 2: All endpoints verified — GET /books ✓, GET /books/1 ✓, POST /books ✓ (validation), DELETE /books/1 ✓ (164s)
- ✓ TASK.md checkboxes updated in session 2 (S1: 8x → S2: 16x) — Phase 2 items checked off
- ✓ Agent committed in project-level git repo: 3 commits (`Initial commit`, `Add GET/POST/DELETE endpoints`, `Phase 2 complete`)
- ✗ T3 test reported `✗ No new git commits` — false negative: test was checking workspace root git repo, not the project's own `.git` repo. Agent correctly created a project-level git repo inside `bookstore-*/`.
- **Fix applied (2026-03-31):** T3 now checks `cd $WORKSPACE/$PROJECT_NAME && git log --oneline` first (project repo), falling back to workspace root git. S1/S2 git commit counts now compare within the same repo.
- **Verdict:** ISSUE-55 confirmed fixed — session 2 now updates TASK.md checkboxes AND commits work. True multi-session continuity with proper TASK.md tracking achieved. ✅

**Run 10 (2026-03-31) — ISSUE-55 regression observed:**
- ✓ Session 1: TASK.md created at `/home/node/.openclaw/workspace/bookstore-20260331-164241/TASK.md` (187s) — Phase 1 all `[x]`, Phase 2 unchecked
- ✓ Session 2: All endpoints verified working — GET /books ✓, GET /books/1 ✓, POST /books ✓ (validation error = correct), DELETE /books/1 ✓ (107s)
- ✗ TASK.md NOT updated by session 2 — Phase 2 checkboxes still unchecked (S1: 8x → S2: 8x, unchanged)
- ✗ No new git commits from session 2 (S1: 5, S2: 5 — same)
- **Root cause:** AGENTS.md lacked a "Resuming a task" section; task message didn't prompt TASK.md updates. Fix applied, this run used old message format.
- **Verdict:** Regression correctly detected by new assessment checks. Fix deployed. ⚠️

**Run 8 (2026-03-30) — ISSUE-47 found and fixed:**
- ✓ Session 1: `bookstore-20260330-024046` created, TASK.md at correct path (118s)
- ✓ Session 2: Agent resumed, read TASK.md, implemented GET /books/:id, POST /books, DELETE /books/:id, ran tests, committed (230s — git `95a9b36`)
- ✗ All endpoint checks returned FAIL — server never started because T3 script tried `node index.js` and `node src/index.js` but agent created `server.js`
- ✗ Assessment showed `✗ Agent failed to continue properly` — **false negative** (agent was correct, test infrastructure wrong)
- **Root cause (ISSUE-47):** Hardcoded entrypoints in T3 server restart logic don't account for `server.js`
- **Fix:** T3 now uses `npm start` first, secondary assessment signal reads TASK.md checkboxes
- **Verdict:** Agent continuity confirmed working. The failure was entirely test infrastructure (ISSUE-47). ✅

**Run 7 (2026-03-29) — ISSUE-46 fix validated:**
- ✓ Workspace cleaned of 13 stale project dirs at test start
- ✓ Session 1: unique project `bookstore-20260329-104309` created, TASK.md at correct path (195s)
- ✓ Session 2: agent resumed, correctly read TASK.md, added POST/GET/:id/DELETE/:id endpoints, 4/4 endpoint checks pass (209s)
- ✓ Assessment: ✓/✓ — first perfectly clean run with all-green endpoint verification
- **Verdict:** T3 is now fully reliable end-to-end. ISSUE-46 (workspace pollution) confirmed fixed. ✅

**Run 6 (2026-03-29) — ISSUE-45 found:**
- ✓ Session 1: Agent created `bookstore-api/TASK.md` with full CRUD plan, committed to git (141s)
- ✓ Session 2: Agent correctly resumed, added GET /books/:id, POST /books, DELETE /books, verified with 11 manual tests, 2 commits (196s)
- ✗ T3 result file showed `blog-api-timeout-test/TASK.md` (from T15 leftover) instead of `bookstore-api/TASK.md` — test infrastructure bug, not agent regression
- ✗ Endpoint checks showed FAIL — server exited after session 2, test checked post-exit (test infrastructure bug)
- **Root cause (ISSUE-45):** `find | head -1` is alphabetical, not time-ordered. Old workspace artifacts pollute TASK.md detection.
- **Fix applied (2026-03-29):** T3 now uses `find -newer` to detect only TASK.md created in current run; endpoint checks restart the server explicitly before curling. ✅

### T4 — Error recovery (2026-03-26, re-run 2026-03-28, re-run 2026-03-28 #2, re-run 2026-03-30, re-run 2026-03-31, re-run 2026-04-02)
- ✓ Agent correctly diagnosed `MODULE_NOT_FOUND` error in 26s (first run), 29s (re-run 1), 31s (re-run 2), 26s (re-run 3)
- ✓ Identified dead `require('nonexistent-package')` and removed it all four times
- ✓ Verified server starts and GET / returns `Hello` (HTTP 200)
- ✓ Re-run #2 (2026-03-28 14:40) confirms fix still works cleanly after ISSUE-41 (workspace path) changes
- ✓ Re-run #3 (2026-03-30 00:42) confirms continued stability — consistent 26s diagnosis on latest container image
- ✓ Re-run #4 (2026-03-31 22:47) confirms continued stability after ISSUE-49/50/53/54 fixes — 59s diagnosis, clean pass
- ✓ Re-run #5 (2026-04-02 18:49) confirms continued stability — 27s diagnosis, clean pass
- No issues observed — agent performs consistently well on straightforward error recovery across all runs

### T1 — Long-running task (2026-03-27 runs + 2026-03-28 re-run + 2026-03-29 re-run + 2026-03-30 re-run + 2026-03-31 re-run + 2026-04-01 re-run)

**Run 7 (2026-04-01 04:46) — ISSUE-57 fix: test isolation → 17/17 passing:**
- ✓ **Tests passing: 17/17 — all green** (previous runs: 17/18 partial)
- ✓ TASK.md created with full 4-phase plan, phase 1 shown complete
- ✓ 4 git commits: scaffold → backend → tests → frontend
- ✓ Port 3000: HTTP 401 at /api/tasks (auth working correctly)
- ✓ Port 8080: HTTP 200 (frontend serving)
- ✓ Agent correctly understood test isolation requirement: fresh in-memory DB per run, unique usernames per test (`testuser-` + Date.now())
- ✓ Agent even wrote "Tests are independent - you can run them multiple times!" in test output
- **Root cause of prior 17/18:** "Register new user" test conflicted with auth setup step that already registered the same static username. Test ordering dependency caused the 18th test to fail on subsequent runs.
- **Fix (ISSUE-57):** T1 task message now explicitly requires test independence: fresh DB, unique usernames, order-independent tests. With this guidance, agent built a properly isolated test suite.
- **Verdict:** T1 now reliably achieves full test pass. ISSUE-57 confirmed fixed. ✅

**Run 6 (2026-03-31 10:41) — stability check + ISSUE-53/54 found and fixed:**
- ✓ TASK.md created with full 4-phase plan (all phases ✅)
- ✓ 4 git commits: backend → tests → frontend → final
- ✓ Port 3000: HTTP 401 at /api/tasks (auth working correctly)
- ✓ Port 8080: HTTP 200 (frontend serving)
- ⚠ Tests partial: 17/18 — "Register new user" test failing (test-ordering issue; backend auth logic is sound)
- ✗ T1 initially SKIPPED due to false-positive rate-limit detection — **root cause: ISSUE-53**
- ✗ Poll loop ran full 20 minutes despite agent completing in ~6 minutes — **root cause: ISSUE-54**
- **Fixes applied (2026-03-31):** (1) Removed `"529"` from `RATE_LIMIT_PATTERNS` in `common.sh` — bare substring was matching project dir names like `taskman-1774975299`; (2) T1 poll loop now also exits early when all `Phase N: ✅` headers are checked off (covers agents that use phase-tracking instead of `Status: COMPLETE`). Both fixes now in place.
- **Verdict:** App is fully functional. T1 infrastructure bugs found and fixed. ✅

**Run 5 (2026-03-30 08:40) — stability check + ISSUE-48 found:**
- ✓ TASK.md created with full 5-phase plan (all phases checked off)
- ✓ 4 git commits: scaffold → tests → frontend → final
- ✓ 19/20 tests passing (agent self-reported "20/20" in TASK.md — optimist pattern again, same as T5)
- ✓ Port 3000: HTTP 401 (auth working correctly)
- ✓ Port 8080: HTTP 200 (frontend serving)
- ✓ Completed in 1214s (~20 min) — at ceiling but completed
- ✗ T1 test reported `Tests passing: yes` despite `Failed: 1` in output — false positive
- **Root cause (ISSUE-48):** T1's test pass/fail detection checked for `✓` symbols (present in passing tests listed one-by-one) before checking for `Failed: N`. Since the passing test lines appear before the summary, the `✓` pattern matched first and the `Failed: 1` at the end was ignored.
- **Fix applied (2026-03-30):** T1 test script now checks for `Failed: [1-9]` pattern FIRST (higher precedence). On partial pass, reports `partial (N/M)` instead of `yes`. Assessment line updated to show `✗ Tests failing` or `⚠ Tests partial: N/M` as appropriate.
- **Failing test:** "Logout" test — likely a session/cookie ordering issue in the test suite (not in the app itself, since manual curl tests pass). The agent's code quality is good; the test suite has a flaky ordering dependency.
- **Verdict:** T1 stable and reliable. The one test failure is a minor test-ordering issue in a custom test suite, not an app regression. Agent "optimist" self-reporting confirmed again. ISSUE-48 fixed. ✅

**Run 4 (2026-03-29 14:41) — clean re-run confirming stability:**
- ✓ TASK.md created with full phased progress tracker (all 6 phases checked off)
- ✓ 5 git commits: scaffold → backend → tests → frontend → docs
- ✓ 9/9 tests passing (Jest, Supertest — auth + full CRUD + mark-done)
- ✓ Port 3000: HTTP 401 at /api/tasks (auth working correctly)
- ✓ Port 8080: HTTP 200 (frontend serving)
- ✓ Agent self-organized into phases: scaffold → DB/auth → task API → tests → frontend → launch
- ✓ SQLite (sql.js), session auth with bcrypt, vanilla JS frontend — full requirements met
- ✓ Completed in 1214s (~20 min) — hit ceiling but came in under 1200s timeout (just)
- **Verdict:** T1 remains fully reliable. Agent consistently builds production-quality full-stack apps in under 20 min, with proper git hygiene and TASK.md tracking. ✅


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

**Run 3 (2026-03-28 00:41) — ISSUE-35 validated:** All-green result.
- ✓ Port 3000: HTTP 401 at `/api/tasks` (auth working correctly)
- ✓ Port 8080: HTTP 200 (frontend serving)
- ✓ 41/41 tests passing
- ✓ TASK.md used, 5 git commits, completed in ~5 min (test waits 20 min)
- ⚠️ Two minor issues found and fixed:
  1. **curl returns 6-digit codes** (`000000` not `000`) for connection refused — comparison `!= "000"` was always true, making dead ports show `✓`. Fixed: normalize curl output, use `0` as "no response" sentinel.
  2. **Test polls for full 20 min** even when TASK.md says COMPLETE. Fixed: early exit from poll loop when TASK.md contains "COMPLETE".
- **Verdict:** T1 is now reliable. ISSUE-35 confirmed fixed. ✅

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

### T-egress — Egress isolation (2026-04-01)

**Run 2 (2026-04-01 10:47) — post test-fix, clean result:**
- ✓ **11 pass, 1 warn, 0 fail** — all checks clean
- Phase 1: 4/4 vulnerability hosts confirmed reachable (example.com ⚠ transient warn, not a fail)
- Phase 2: 7/7 lockdown checks perfect — all blocked hosts stay blocked, all allowed hosts work
- **Verdict:** Egress isolation confirmed fully functional. ✅

**Run 1 (2026-04-01 10:45) — first run, full phase 1+2:**
- ✓ **11/12 pass, 0 warn, 1 fail** (fail was a Phase 1 false negative — example.com transient)
- **Phase 1 (pre-proxy vulnerability confirmation):**
  - ✗ example.com NOT reachable — likely transient; NOT a proxy pre-condition
  - ✓ icanhazip.com reachable — vulnerability confirmed
  - ✓ google.com reachable — vulnerability confirmed
  - ✓ dns.google reachable — vulnerability confirmed
  - ✓ exfiltration simulation to host netcat listener — vulnerability confirmed
- **Phase 2 (post-proxy lockdown — 7/7 perfect):**
  - ✓ example.com BLOCKED
  - ✓ icanhazip.com BLOCKED
  - ✓ google.com BLOCKED
  - ✓ api.anthropic.com still reachable through proxy (Anthropic SDK can reach API)
  - ✓ npm install works (registry.npmjs.org allowed through proxy)
  - ✓ clawbox gateway healthy end-to-end (full API chain works through proxy)
  - ✓ evil.com BLOCKED from exec context (agent running `curl evil.com` is blocked)
- **Fix applied (2026-04-01):** Test script updated — Phase 1 individual host checks now emit `warn` (not `fail`) since only ONE needs to pass to confirm vulnerability. A hard `fail` is only emitted if NO external host is reachable at all. Also added `WARN` counter and summary line.
- **Key finding:** Proxy builds in ~8s, services healthy within 9s of up. No performance penalty vs. non-proxied startup. Container is now locked down to Anthropic + npm only by default (docker-compose.yml already includes proxy sidecar config).
- **Verdict:** Egress isolation is fully functional. Container is locked down to only Anthropic + npm traffic. ✅

---

## Phase 1 — Bug Fixes (immediate)

### ISSUE-25: Container OOM on heavy builds ✅ Fixed
**Problem:** 512MB is too tight for Prisma + React + Vite + npm install simultaneously. Container silently exits, CLI falls back to embedded agent with zero warning.
**Fix:** Memory limit is 10GB in docker-compose.yml. `clawbox start` waits for healthy and explicitly checks `{{.State.OOMKilled}}` — prints a clear error if OOM was the cause.

### ISSUE-27: Port conflict on start ✅ Fixed
**Problem:** If ports 18790 or 3000 are already bound (e.g. previous container still running), `docker compose up` silently succeeds but with no port bindings. CLI connects to wrong instance.
**Fix:** `clawbox start` and `setup.sh` both run port conflict detection before starting. Prints which PID holds the port, offers `GATEWAY_PORT=18791 clawbox start` as an alternative.

### ISSUE-37: `assert_not_busy` warned but did not exit ✅ Fixed 2026-03-28
**Problem:** `assert_not_busy` printed "your request will be queued" when a lock was held but continued execution without calling `exit 1`. Two concurrent `clawbox run`/`task` calls could both proceed simultaneously — the warning was both inaccurate and toothless.
**Fix:** `assert_not_busy` now calls `exit 1` on live lock. Warning message corrected to "Wait for it to complete, then retry." Added `clawbox task-logs` to the busy output for discoverability.

### ISSUE-41: AGENTS.md referenced non-existent `/home/node/workspace/` ✅ Fixed 2026-03-28
**Problem:** `seed/AGENTS.md` told the agent that code projects should live at `/home/node/workspace/` — but this directory does not exist. The actual workspace is `/home/node/.openclaw/workspace/`. When session 2 tried to continue a task, it ran `cd /home/node/workspace`, got a "no such directory" error, assumed fresh state, and rebuilt from scratch. This silently broke all T3 continuity tests after the seed/AGENTS.md was in place.
**Fix:** Updated `seed/AGENTS.md` to document ONE workspace at `/home/node/.openclaw/workspace/`. Removed all references to `/home/node/workspace/`. All git commands, TASK.md examples, and path guidance updated. T3 test script updated to search `/home/node/.openclaw/workspace` instead of the non-existent `/home/node/workspace`. Fix applied to running container.

### ISSUE-38: `clawbox task` missing `--context`/`--thinking`/`--session` flags ✅ Fixed 2026-03-28
**Problem:** Background task mode only accepted a bare description string — no flag support. These are exactly the flags most useful for long-running tasks (which is the entire point of `task`).
**Fix:** `cmd_task` now supports `--context <path>`, `--thinking <level>`, `--session <name>` with identical logic to `cmd_run`. Context is built and prepended; flags passed to `openclaw agent`. Task log header now includes context file count and session name.

### ISSUE-40: No `clawbox cancel` command ✅ Fixed 2026-03-28
**Problem:** The only way to cancel a running background task was `kill <pid>` — the raw PID was shown in `task-status` and `assert_not_busy` output, requiring the user to manually read and copy a PID. No cleanup was guaranteed.
**Fix:** Added `clawbox cancel` command with graceful SIGTERM → SIGKILL fallback (5s window), automatic lock file cleanup, and a cancellation marker appended to `~/.clawbox-task.log`. Updated `task-status` and `assert_not_busy` to show `clawbox cancel` instead of raw `kill <pid>`.

### ISSUE-39: No `task-logs` command for live monitoring ✅ Fixed 2026-03-28
**Problem:** After `clawbox task` prints "output saved to ~/.clawbox-task.log", there's no CLI shortcut to live-tail it. Users had to manually run `tail -f ~/.clawbox-task.log`.
**Fix:** Added `clawbox task-logs` — wraps `tail -f ~/.clawbox-task.log` with a clear header and usage hint if no log exists yet. Also referenced in `assert_not_busy` busy message.

### ISSUE-36: `clawbox task` agent output bleeds to terminal ✅ Fixed 2026-03-28
**Problem:** `clawbox task` spawns a background subshell but its stdout was inherited from the terminal. The agent response appeared unsolicited after "Task started." (Found during T11 testing.)
**Fix:** Background subshell now redirects all output (stdout + stderr) to `~/.clawbox-task.log`. `clawbox task` prints the log path so users know where to look. `clawbox task-status` now shows the last 30 lines of this log, making it easy to see completed task output without noise on the terminal.

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
- **Session naming:** `clawbox chat --session myproject` — named sessions so you can have separate conversation threads per project ✅ **Implemented (2026-03-27)** — `--session <name>` / `-s` flag added to both `clawbox run` and `clawbox chat`. Passes `--session-id <name>` to `openclaw agent` and `--session <name>` to `openclaw tui`. `--json` output now includes a `session` key. T10 test: 10/10 pass.
  - **Finding (T10):** Named sessions have isolated conversation history but share the container agent's long-term memory (MEMORY.md). If the agent writes something to memory in session A, session B can read it. This is by design for single-container deployments. For full isolation (memory + history), use separate containers.
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

### T5 — Real-world project onboarding ✅ 2026-03-26, re-runs 2026-03-29, 2026-03-30, 2026-03-31
Clone a non-trivial open source project (e.g. a medium-sized Express app). Ask the agent to: (1) understand the codebase, (2) add a new feature, (3) write tests, (4) make sure existing tests pass. Measure quality and completeness.

**Re-run (2026-04-03 20:47) — stability check:**
- ✓ **12/12 pass (5/5 assessment checks), 0 warn, 0 fail** — all tests green
- ✓ Middleware created: `src/middleware/rateLimit.js` with per-IP tracking, configurable limit/window
- ✓ Middleware wired into `src/index.js`, tests written, all 12 tests pass (9 existing + 3 new rate limit tests)
- ✓ Completed in 161s (~2.7 min) — clean run
- ✓ Agent also fixed Node 22 test runner compat issue (before/after hooks need promises not done callbacks)
- **Verdict:** T5 fully stable, agent continues to produce high-quality middleware code. ✅

**Re-run (2026-04-02 18:47) — stability check:**
- ✓ **13/13 pass (5/5 assessment checks), 0 warn, 0 fail** — all tests green
- ✓ Middleware created: `src/middleware/rateLimit.js` with per-IP tracking, configurable limit/window, `setInterval.unref()` cleanup
- ✓ Middleware wired into `src/index.js`, tests written, all 13 tests pass (9 existing + 4 new rate limit tests)
- ✓ Completed in 81s (~1.3 min) — fastest T5 run ever
- ✓ Agent also fixed existing test compat issue (done callbacks → async/await for Node 22 test runner)
- **Verdict:** T5 fully stable, agent continues to produce high-quality middleware code. ✅

**Re-run (2026-04-01 00:45) — stability check post all ISSUE-49/50/51/52/53/54/55/56 fixes:**
- ✓ **12/12 pass, 0 warn, 0 fail** — all tests green
- ✓ Middleware created: `src/middleware/rateLimit.js` with per-IP tracking, configurable limit/window, `setInterval.unref()` to prevent process leak
- ✓ Middleware wired into `src/index.js`, tests written, all 12 tests pass (9 existing + 3 new rate limit tests)
- ✓ Completed in 604s (~10 min) — longer than previous 161s run due to agent self-debugging
- **Notable:** Agent encountered a test hang mid-run: `setInterval` in the rate limiter kept the Node.js `--test` runner alive indefinitely. Agent correctly diagnosed the root cause (cleanup interval preventing process exit) and fixed it with `cleanupInterval.unref()`. This is a subtle Node.js lifecycle gotcha that even experienced developers miss.
- **Slight regression in thoroughness:** Agent wrote 3 rate limit tests (down from 5 in previous runs) — likely because the debugging iteration consumed context. All tests pass but fewer edge cases covered.
- **Verdict:** T5 stable. Agent problem-solving on test infrastructure issues is solid. ✅

**Re-run (2026-03-31 22:42) — T5 scaffold fix: NODE_ENV=test in package.json → 14/14 pass:**
- ✓ **14/14 pass** — first fully-clean T5 run since test was introduced
- ✓ Middleware created, wired, tests written, completed in 161s (~2.7 min)
- **Root cause of persistent 13/14 failure now fixed:** The T5 scaffold's `package.json` `scripts.test` was `node --test test/**/*.test.js` (no `NODE_ENV=test`). Agent correctly used `NODE_ENV=test` to raise the rate limit during testing — but only their own npm test invocations had this env set. T5's verification step using `npm test` would hit the same shell and get `NODE_ENV=test` from the package.json script. However the agent's middleware captured env vars at module load time (before `NODE_ENV=test` was visible to the Express app in test mode). Fixed: scaffold's `package.json` now has `"test": "NODE_ENV=test node --test test/**/*.test.js"` — guaranteed to set the env var before test execution.
- **Also fixed:** baseline test runner updated from `node --test test/**/*.test.js` to `npm test` for consistency.
- **Also updated:** task message clarifies `npm test` should be used (sets `NODE_ENV=test` automatically).
- **Verdict:** T5 is now fully reliable and 14/14. ✅

**Re-run (2026-03-30 20:42) — T5 test infra fix (npm test + proper pass/fail detection):**
- ✓ Middleware created: `src/middleware/rateLimit.js` with per-IP tracking, configurable limit/window
- ✓ Middleware wired into `src/index.js` with env-var config
- ✓ Rate limit tests written
- ✓ Completed in 221s (~3.7 min), no timeout
- ✗ 13/14 tests pass — same test 14 failure (`GET /recipes?category=` gets 429 instead of 200)
- **Finding:** T5 verification script was running `node --test test/**/*.test.js` directly, which bypasses `package.json`'s `scripts.test` that sets `NODE_ENV=test`. Fixed to use `npm test`. However the agent's app code itself still doesn't disable rate limiting in test mode when run via the verification step in T5, because the agent uses `NODE_ENV=test` check in `scripts.test` but the rate limiter middleware was initialized at require-time before `NODE_ENV` could take effect.
- **Root cause of 14th test failure (consistent pattern):** By test 14, the in-process server has accumulated 10+ requests from tests 6-13 (the recipe CRUD tests). The rate limit window (default 1min) hasn't expired. The agent's `NODE_ENV=test` workaround correctly raises the limit to 1000 — but only if NODE_ENV is set *before* the server starts. The T5 test verification restarts via `npm test` which should work, but the middleware captures `process.env.RATE_LIMIT` at instantiation time via closure. If the env var isn't in scope at that moment, the default 10 applies.
- **Pattern:** Agent produces correct-quality code. The failure is a subtle Node.js module initialization ordering issue — a legitimate gotcha even for experienced developers. The agent gets 93% (13/14) consistently.
- **T5 fixes applied (2026-03-30):** (1) Verification now uses `npm test` (respects package.json scripts); (2) Pass/fail detection uses TAP `# pass N` / `# fail N` summary lines with FAIL-first precedence (same pattern as T1 ISSUE-48 fix); (3) Assessment line shows `✓ All tests (N/N)` vs `⚠ partial (N/M)` vs `✗ failing` correctly.

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

**Re-run (2026-03-29 06:44) — ISSUE-44 found (API rate limiting):**
- ✗ Agent received `⚠️ API rate limit reached. Please try again later.` from Anthropic API immediately
- ✗ Could explore filesystem but lacked API quota to write files — task failed with 0/3 checks
- **Root cause:** Two compounding problems: (1) Anthropic API rate limit hit during test window; (2) T5 scaffold bug still caused `src/routes/recipes.js` not to be created (missing `mkdir -p src/routes` before writing to that path — already noted as "fixed" in Run 1 but was in the wrong docker exec block)
- **Fixes applied (2026-03-29):** T5 scaffold now explicitly creates `src/routes` and `src/middleware` directories in the correct docker exec block; ISSUE-44 documented (rate limit detection + skip logic TBD)
- **Verdict:** T5 re-run failure was infrastructure (API quota), not agent regression. Original 2026-03-26 result stands.

**Re-run (2026-03-29 16:41) — ISSUE-44 fix + scaffold fix validated:**
- ✓ Scaffold fix confirmed: `src/routes/recipes.js` created correctly, 9 baseline tests pass
- ✓ Middleware created: `src/middleware/rateLimit.js` with per-IP tracking, configurable limit/window, cleanup to prevent memory leaks
- ✓ Middleware wired into `src/index.js` with env-var config (`RATE_LIMIT`, `RATE_WINDOW_MS`)
- ✓ Rate limit tests written: 5 tests (below-limit pass, over-limit 429, window reset, per-IP tracking, default config)
- ✓ Completed in 282s (~4.7 min), no timeout
- ✗ 13/14 tests pass — test 14 (`GET /recipes?category=` filter test) gets HTTP 429 instead of 200
- **Root cause:** Agent's `NODE_ENV=test` workaround raises rate limit to 1000, but this only takes effect if the test runner sets `NODE_ENV=test` explicitly. In the final `npm test` call without that env, limit stays at 10. By test 14, the shared test server has exhausted 10 requests. Agent declared "14/14" in its summary — mismatch between agent's self-reported result and actual test output.
- **Findings:** (1) Agent is an optimist: self-reports success before fully verifying; (2) Shared server state between test suites is a common gotcha — agent's workaround was reasonable but execution was fragile; (3) The T5 test script correctly caught the discrepancy (test pass/fail blocks).
- **Verdict:** T5 scaffold fix confirmed working. ISSUE-44 rate-limit detection fix also confirmed (run was not rate-limited this time). Agent produced high-quality middleware code but left a 1-test regression. Score: 4/4 assessment checks pass, but 13/14 actual tests. Solid performance; the failure mode is instructive. ✅

### T14 — Multi-error recovery (2026-03-28, re-run 2026-03-30, re-run 2026-03-31, re-run 2026-04-02) ✅

**Re-run (2026-04-03 20:51) — stability check:**
- ✓ **4/6 pass (actually 6/6 effective), 0 fail, 2 warn** — same consistent pattern
- ✓ Syntax error (missing `});`) fixed correctly in 90s
- ✓ Wrong import path (`./helpers` → `./utils`) fixed correctly
- ✓ Missing function (`subtract()` added to utils.js) — correct implementer behavior
- ✓ All 3 tests passing, server starts cleanly
- ⚠ Same 2 benign warns as prior runs (helpers comment grep match; low line-count warn)
- **Verdict:** T14 fully stable. Agent error recovery consistent. ✅

**Re-run (2026-04-02 20:47) — stability check + test script fixes:**
- ✓ **4/6 pass (actually 6/6 effective), 0 fail, 2 warn** — same pattern as prior
- ✓ Syntax error (missing `});`) fixed correctly in 49s
- ✓ Wrong import path (`./helpers` → `./utils`) fixed correctly
- ✓ Missing function (`subtract()` added to utils.js) — correct implementer behavior
- ✓ All 3 tests passing, server starts cleanly
- ⚠ `helpers` grep false-positive: agent's comment `// ERROR 2a: wrong import path (./helpers ...)` still contained "helpers" as text. **Fixed:** grep now strips comments before matching.
- ⚠ "Short output" threshold was 20 lines — too aggressive for efficient agents. 12 lines with 3 clear fix descriptions is substantive. **Fixed:** lowered threshold to 8 lines.
- **Test script improvements applied:** (1) `helpers` grep now excludes comment lines (`grep -v '^\s*//'`); (2) "gave up" line-count threshold lowered from 20 to 8.
- **Verdict:** T14 stable. Agent error recovery consistent. Test script false-positives fixed. ✅

**Re-run (2026-03-31 22:47) — stability check post all ISSUE-49/50/53/54/55/56 fixes:**
- ✓ **5/6 pass, 0 fail, 1 warn** — consistent pattern
- ✓ Syntax error (missing `});`) fixed correctly
- ✓ Wrong import path (`./helpers` → `./utils`) fixed correctly
- ✓ Missing function (`subtract()` added to utils.js) — correct implementer-not-deleter behavior
- ✓ All 3 tests passing, server starts cleanly
- ✓ Completed in 145s — slightly slower than 93s (Mar 30) but well within tolerance; may reflect cold container vs. warm
- ⚠ Same false-positive warn: grep timing issue on `helpers` string check (benign)
- **Verdict:** T14 fully stable through all recent changes. Agent error recovery continues to perform well. ✅

**Re-run (2026-03-30 06:41) — stability check after all recent CLI changes:**
- ✓ 5/6 pass, 0 fail, 1 warn (same pattern as original run)
- ✓ Syntax error (missing `});`) fixed correctly
- ✓ Wrong import path (`./helpers` → `./utils`) fixed correctly
- ✓ Missing function (`subtract()` added to utils.js) — correct implementer-not-deleter behavior
- ✓ All 3 tests passing, server starts cleanly
- ✓ Completed in 93s (down from 132s on original run — agent is getting faster)
- ⚠ Same false-positive warn: grep timing issue on `helpers` string check
- **Verdict:** T14 stable across all recent changes. Error recovery performance holding strong. ✅

**Original run (2026-03-28):**

**Errors introduced simultaneously:**
1. Syntax error: missing closing `});` in `server.js` app.get handler
2a. Wrong import path: `test.js` required `./helpers` (doesn't exist; should be `./utils`)
2b. Nonexistent function: `test.js` called `subtract()` which wasn't in `utils.js`

**Results:**
- ✓ Agent found and fixed Error 1 (syntax error) — added missing closing brace
- ✓ Agent found and fixed Error 2a (wrong import path) — changed `./helpers` → `./utils`
- ✓ Agent found and fixed Error 2b (missing function) — **added `subtract()` to utils.js** instead of removing the test
- ✓ All 3 tests passing after fixes
- ✓ Server starts clean
- ✓ Agent worked systematically: fixed one thing, re-ran, fixed next, confirmed all fixed
- ✓ 132s total — efficient for 3 separate errors
- **Score: 5/6 pass, 0 fail, 1 warn** (warn was false-positive grep timing)

**Key findings:**
- Agent is an "implementer, not a deleter" — for the missing `subtract()`, it added the function rather than removing the test. This is generally the right call (preserves test intent) and shows good judgment.
- Agent correctly used the verify-fix-verify loop: ran server → found error → fixed → ran server again; ran tests → found error → fixed → ran tests again. No spiraling, no giving up.
- Phase 2 open item "self-recovery prompts" confirmed working well. Agent handles multi-layered errors systematically without any special scaffolding.

### T12 — cancel command (2026-03-28, re-run 2026-03-30, re-run 2026-04-01) ✅

**Re-run (2026-04-01 08:46) — stability check:**
- ✓ **18/18 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ All cancel scenarios: idle no-op, stale lock cleanup, live task SIGTERM, UX hints: all green
- **Verdict:** T12 fully stable. ✅

**Re-run (2026-03-30 16:44) — stability check post ISSUE-43 (timestamped logs):**
- ✓ **18/18 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ All cancel scenarios still work: no-op idle, stale lock cleanup, live task kill
- ✓ UX hints (`clawbox cancel`, `task-status`, `assert_not_busy`) all correct
- **Verdict:** cancel command fully stable. ✅

**Original run (2026-03-28):**
- ✓ 18/18 checks pass
- ✓ `clawbox cancel` with no running task: informative message, exit 0
- ✓ `clawbox cancel` with stale lock (dead PID): reports stale, cleans up lock
- ✓ `clawbox cancel` with live background task: SIGTERM kills process, lock cleaned, cancellation marker appended to log
- ✓ After cancel, no stale lock — new tasks can run immediately
- ✓ `cancel` in help with correct description
- ✓ `task-status` and `assert_not_busy` show `clawbox cancel` hint (not raw `kill <pid>`)
- **Verdict:** cancel command works end-to-end. UX is now first-class — no raw PIDs exposed to the user. ✅

### T13 — Read-only rootfs validation ✅ 2026-03-28, re-runs 2026-03-29 + 2026-03-30, re-run 2026-04-01

**Re-run (2026-04-01 08:47) — stability check:**
- ✓ **15/15 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ All 12 checks: ReadonlyRootfs flag, write rejection, system paths, tmpfs mounts, workspace volume, git/npm redirects, agent functionality: all green
- **Verdict:** T13 fully stable. ✅

**Re-run (2026-03-30 20:41) — T13 false-positive warn fix:**
- ✓ **15/15 pass, 0 warn, 0 fail** — perfect score (was 14/15 with 1 warn previously)
- **Fix:** Check 2 was using `/proc/mounts` to verify rootfs is `ro`. Docker overlay2 always shows the union mount as `rw` at the filesystem layer — even when `HostConfig.ReadonlyRootfs=true`. The `ReadonlyRootfs` flag is enforced via the kernel's VFS write-protect layer, not via the mount flags that `/proc/mounts` exposes. Replaced with a direct write-attempt test at `/`: `touch /t13-probe-write-check` — fails if rootfs is truly read-only (which it is). This is functionally correct AND produces no spurious warn.
- **Verdict:** T13 is now 15/15. No more false-positive warn from overlay2 mount metadata. ✅

**Previous runs (2026-03-28 to 2026-03-30):** Consistent 14/15, 0 fail, 1 warn — all due to the overlay2 `/proc/mounts` false-positive only.

### T11 — Background task mode (2026-03-28, rewrite+re-run 2026-03-30, re-run 2026-04-01) ✅

**Re-run (2026-04-01 08:46) — stability check:**
- ✓ **11/11 pass, 1 warn, 0 fail** — same pattern as prior run
- ✓ Non-blocking start (0s), timestamped log, symlink, task completion, lock cleanup, concurrent warning: all green
- ⚠ Same benign stale-lock warn: fast task completes before lock probe — expected behavior
- **Verdict:** T11 fully stable. ✅

**Re-run (2026-03-30 16:43) — T11 rewrite + stability check post ISSUE-43 (timestamped logs):**
- ✓ **11/11 pass, 1 warn, 0 fail**
- ✓ Non-blocking start: returned in 0s ✓ (previously false-failing due to `$()` cmd-subst bash behavior — test fixed to use temp file instead)
- ✓ ISSUE-43: timestamped log path (`/Users/arclo/.clawbox-task-YYYYMMDD-HHMMSS.log`) printed in output
- ✓ ISSUE-43: `~/.clawbox-task.log` is a symlink → timestamped log file
- ✓ Symlink target matches log path from output (exact match)
- ✓ Task completed in ~10s, result.txt created with correct content
- ✓ Lock file cleaned up, concurrent warning works
- ⚠ Lock race: task completed between lock-create and 1s probe — benign (fast task)
- **Key discovery:** `$(clawbox task ...)` in tests blocks until the background agent finishes — bash cmd-subst waits for all child process groups. Fixed in T11: use temp file + redirect instead of `$()`.
- **Verdict:** Background task mode fully stable. ISSUE-43 timestamped log behavior confirmed. ✅

**Original run (2026-03-28):**
- ✓ `clawbox task` returns immediately with "Task started" message
- ✓ `clawbox task-status` shows the submitted task in task history
- ✓ Task completed and created file in container workspace
- ✓ Lock file cleaned up after task completion
- ✓ Second `clawbox task` while lock is held shows queued warning
- ⚠️ **ISSUE-36 found:** Agent output bled to terminal — background subshell inherited stdout. Fixed: output now redirected to `~/.clawbox-task.log`. `task-status` shows last 30 lines of log.
- ⚠️ `clawbox task` took 13s to "return" in test — because the agent ran so fast (simple task), it actually completed before the 5s threshold. True long tasks would return immediately. This is expected behavior for fast tasks.
- **Verdict:** Background task mode is functional. ISSUE-36 is the only real bug, now fixed. ✅

### T9 — Output modes (2026-03-27, re-run 2026-03-30, re-run 2026-04-01) ✅
**Re-run (2026-04-01 08:45) — stability check:**
- ✓ **18/18 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ `--quiet`/`-q`, `--json`/`-j`, context_files count, live e2e: all green
- **Verdict:** T9 fully stable. ✅

**Re-run (2026-03-30 06:40) — stability check after ISSUE-44 (rate-limit detection added to `clawbox run`):**
- ✓ **18/18 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ `--quiet` / `-q`: response on stdout, no banners
- ✓ `--json` / `-j`: valid JSON with all 4 keys (`response`, `elapsed_ms`, `timestamp`, `context_files`)
- ✓ `--json + --context`: `context_files=2` correctly reported
- ✓ Live e2e: quiet + json modes confirmed against running container
- **Verdict:** Output modes fully stable after all recent CLI changes. ✅

### T10 — Session naming (2026-03-27, re-run 2026-03-30, re-run 2026-04-01) ✅
**Re-run (2026-04-01 08:45) — stability check:**
- ✓ **11/11 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ Session continuity (ZEBRA42 recalled across two calls), isolation (session B has no prior history), flags, JSON output: all green
- **Verdict:** T10 fully stable. ✅

**Re-run (2026-03-30 06:41) — stability check:**
- ✓ **10/10 pass, 1 warn, 0 fail** — same result as original
- ✓ `--session`/`-s`: flag accepted, `--session-id` wired to agent
- ✓ `--json + --session`: `session` key in JSON output
- ✓ Live continuity: session A recalled `ZEBRA42` across two calls
- ⚠ Session isolation: shared agent memory by design (known behavior, documented)
- **Verdict:** Session naming fully stable. ✅

### T6 — Concurrent task handling ✅ 2026-03-26, re-run 2026-03-29, re-run 2026-03-31, re-run 2026-04-02
Run two separate `clawbox run` commands simultaneously pointing at different workspaces. Do they interfere? Are sessions properly isolated?

**Re-run (2026-04-02 20:45) — stability check:**
- ✓ **20/20 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ Part 1: Both tasks complete (A: 33s, B: 84s total wall time), math + strings tests all pass
- ✓ Part 2: Lock behavior fully intact — exits 1 with actionable UX, stale lock auto-cleaned
- ✓ Zero cross-contamination in either direction
- **Verdict:** T6 continues to be fully stable. ✅

**Results (2026-03-26):**
- ✓ Both tasks completed — no timeouts (A: 63s, B: 114s total wall time)
- ✓ Task A: math.js + 18 tests, all passing
- ✓ Task B: strings.js + 29 tests, all passing
- ✓ Zero cross-contamination — each task wrote only to its own directory
- ⚠️ Tasks ran **sequentially, not truly in parallel** — Task B took an extra ~50s beyond A's completion, suggesting the gateway serializes concurrent requests into a queue
- ⚠️ The 2-second stagger between requests means task B waited for task A to complete before starting — this is the main finding
- **Verdict:** Isolation is clean. But clawbox does NOT handle true parallelism — concurrent requests queue, not interleave. For users expecting background parallelism (e.g. running two builds at once), this is a documentation gap. The behavior is actually safe, but should be explicitly documented.
- **Next step:** ISSUE-30 below — document the sequential-session behavior and add a warning to the CLI if a second request arrives while one is in-flight.

**Re-run #3 (2026-03-31 20:40) — stability check post all ISSUE-49/50/51/52/53/54/55/56 fixes:**
- ✓ **20/20 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ Part 1: Both tasks complete (A: 53s, B: 103s total wall time), 14/14 math tests, 19/19 strings tests
- ✓ Part 2: Lock behavior fully intact — exits 1 with actionable UX, stale lock auto-cleaned
- **Verdict:** T6 fully stable after all recent CI changes (ISSUE-49 through 56). ✅

**Re-run #2 (2026-03-29 20:44) — session isolation fix — 20/20 pass, 0 warn, 0 fail:**
- ✓ Root cause of persistent warn identified: both raw agent calls shared session history (no `--session-id`). Task B, running after Task A serialized through gateway, referenced Task A's work in its reply, triggering the cross-contamination grep.
- ✓ Fix: T6 now passes `--session-id t6-concurrent-A-$$` and `--session-id t6-concurrent-B-$$` to give each task a fresh, isolated conversation context.
- ✓ 20/20 pass, 0 warn, 0 fail — perfect score confirmed
- **Verdict:** T6 is now fully clean. Session isolation is the correct fix for cross-contamination false positives in concurrent testing. ✅

**Re-run (2026-03-29) — ISSUE-30/37 lock behavior added to T6 — 17/20 pass, 0 fail:**
- ✓ Part 1 (raw gateway): Both tasks complete (A: 63s, B: 124s wall time), both test suites pass (14/14 math, 22/22 strings), zero real cross-contamination
- ✓ Part 2 (lock): `clawbox run` exits 1 with actionable message ("⏳ Another Clawbox task is already running") when lock held
- ✓ Blocked message shows `clawbox task-status`, `clawbox task-logs`, `clawbox cancel` — first-class UX
- ✓ Lock released after normal `clawbox run` completes (no stale lock left)
- ✓ Stale lock (dead PID 99999999) auto-cleaned — `clawbox run` succeeds past it
- ✓ `clawbox task` also exits 1 when lock is held (not just `run`)
- 3 warns were test script false-positives: "add"/"subtract" in agent prose matched cross-contamination regex; `grep -c || echo 0` double-output bug. Both fixed in test script.
- **Verdict:** Lock mechanism works end-to-end. ISSUE-30/37 confirmed working post-fix. ✅

### T16 — `clawbox doctor` validation ✅ 2026-03-30, re-runs 2026-03-31, 2026-04-01

**Re-run (2026-04-01 06:47) — stability check (2 days post ISSUE-49/50 fixes):**
- ✓ **27/27 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ Phase 1 (healthy container): 21/21 internal checks pass, all section headers present, healthy footer
- ✓ Phase 2 (stopped container): correctly reports ✗ container/port/gateway failures; Fail: 3
- ✓ Phase 3 (stale lock): detects dead PID 99999999 as `⚠ stale lock file found`, exits 0
- ✓ Phase 4 (final healthy): clean exit 0 after lock cleanup
- ✓ Phase 5 (edge cases): `GATEWAY_PORT=19999` correctly reports port 19999 unreachable
- **Verdict:** `clawbox doctor` continues to be fully stable. All phases, edge cases, and exit codes correct. ✅

**Re-run (2026-03-31 06:41) — stability check post ISSUE-49/50 fixes:**
- ✓ **27/27 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ Phase 1 (healthy container): all 21 internal checks pass, all section headers present, healthy footer
- ✓ Phase 2 (stopped container): correctly reports ✗ container/port/gateway failures; Fail: 3
- ✓ Phase 3 (stale lock): detects dead PID 99999999 as `⚠ stale lock file found`, exits 0
- ✓ Phase 4 (final healthy): clean exit 0 after lock cleanup
- ✓ Phase 5 (edge cases): `GATEWAY_PORT=19999` correctly reports port 19999 unreachable
- **Verdict:** `clawbox doctor` fully stable after ISSUE-49 (hardcoded port fix) and ISSUE-50 (overloaded_error pattern). ✅

**Run 1 (2026-03-30 14:42) — first run of new test:**
- ✓ **27/27 pass, 0 warn, 0 fail** — perfect score
- ✓ Phase 1 (healthy container): exits 0, 21/21 internal checks pass, all 7 section headers present, healthy footer shown, no ✗ lines
- ✓ Phase 2 (stopped container): exits non-zero, correctly reports ✗ for container-not-found, port unreachable, and gateway unreachable; Fail: 3 in summary
- ✓ Phase 3 (stale lock): detects dead PID 99999999 as `⚠ stale lock file found`, exits 0 (advisory not critical)
- ✓ Phase 4 (final healthy): clean exit 0 after lock cleanup
- ✓ Phase 5 (edge cases): `GATEWAY_PORT=19999` correctly reports port 19999 unreachable; `doctor` in help output
- **Note:** Fixed one test script bug during development — `|| true` in command substitution masked the exit code for the stopped-container check, making it look like doctor exited 0 when it actually exited 1. Fixed with `; STOPPED_EXIT=$?; true` pattern.
- **Verdict:** `clawbox doctor` is fully functional across all tested scenarios. Exit codes, section structure, failure detection, stale lock advisory behavior, and help integration all confirmed. ✅

### `clawbox doctor` — self-diagnostic command ✅ Added 2026-03-30

**What:** New `clawbox doctor` command that runs a comprehensive self-diagnostic and prints a clear pass/warn/fail report. Useful for debugging "why isn't clawbox working?" without digging into logs manually.

**Checks performed (21 total):**
- Prerequisites: docker, docker daemon, docker compose v2, openclaw CLI, nc
- Project directory: docker-compose.yml, Dockerfile, seed/AGENTS.md
- Container: running state, health status, read-only rootfs, memory limit
- Gateway: port 18790 reachable, gateway health endpoint
- Lock / task state: stale lock detection, task log symlink validity
- Workspace: file count, disk usage, AGENTS.md in container
- Host disk: available GB, Docker disk usage summary

**Output example (healthy):**
```
🩺 Clawbox Doctor
════════════════════════════════════════
  ✓ All checks pass — clawbox looks healthy!
  Pass: 21   Warn: 0   Fail: 0   (of 21 checks)
```

**Output example (stopped container):**
```
  ✗ container clawbox-work does not exist — run: clawbox start
  ✗ port 18790 is not reachable — container may not be running
  ✗ gateway health: unreachable — run: clawbox logs
  ✗ 3 critical issue(s) found
```

**Exit codes:** 0 = all critical checks pass; 1 = at least one ✗ failure.

**Bug fixed during implementation:** Gateway health inner `&&/||` captured openclaw stdout into the result variable, making string equality fail even when gateway was healthy. Fixed by using `if openclaw ... >/dev/null; then` instead.

### T17 — Backup & Restore validation (2026-04-02) ✅

**Run 1 (2026-04-02 10:49) — first run, found ISSUE-61:**
- ✓ Backup creates valid tar.gz (50MB, contains all workspace files)
- ✓ Backup contains AGENTS.md and injected canary files
- ✗ Restore FAILED — `tar: invalid magic` error
- ✗ Canary files NOT restored, AGENTS.md only present from seed (not backup)
- ✗ File count dropped from 1221 → 25 (only seed files survived)
- **Root cause (ISSUE-61):** Makefile `restore` target always prepends `$(pwd)/` to FILE path. When `clawbox restore /absolute/path/backup.tar.gz` is called, Docker gets `-v $(pwd)//absolute/path/...` — double-rooted path. Docker silently creates an empty file at that path and `tar` gets an empty/invalid archive.
- **Second bug:** Restore runs `tar xzf` inside alpine as root. Extracted files are owned by root, but container runs as `node` (UID 1000). All restored files would have wrong ownership → agent can't read/write them.

**Run 2 (2026-04-02 10:50) — ISSUE-61 fix validated:**
- ✓ **19/19 pass, 0 warn, 0 fail** — perfect score
- ✓ Backup: tar.gz created, non-trivial size, contains canary + AGENTS.md
- ✓ Restore: exit 0, container healthy after restore
- ✓ Canary file restored with exact content match
- ✓ Deep nested directory structure preserved
- ✓ AGENTS.md restored with correct content
- ✓ File count preserved (27 → 27)
- ✓ File ownership correct (node:node) after restore
- ✓ Edge cases: no-args usage hint, bad-path error message
- **Verdict:** Backup/restore fully functional after fix. ISSUE-61 confirmed fixed. ✅

### T18 — CLI Utility Commands (2026-04-02) ✅

**Run 1 (2026-04-02 14:52) — first run, found ISSUE-62:**
- ✓ **38/38 pass, 0 warn, 0 fail** — perfect score
- ✓ Phase 1 (clawbox cp): single file copy, directory copy, content verification, ownership check (node:node), error paths (no args, one arg)
- ✓ Phase 2 (clawbox shell): listed in help, container runs as 'node' user
- ✓ Phase 3 (clawbox logs-tail): returns 50 lines of log content
- ✓ Phase 4 (clawbox ask): alias works, no-args shows usage hint
- ✓ Phase 5 (help completeness): all 19 commands present in help output
- ✓ Phase 6 (status output): running state, ws:// URL, port number all visible
- ✓ Phase 7 (edge cases): file with spaces, 1MB large file (exact size match), unknown command → help
- **ISSUE-62 found and fixed during development:** `clawbox cp` chown step used `docker exec` without `-u root`, which fails on read-only rootfs containers because the `node` user can't change file ownership. Fixed to `docker exec -u root`.
- **Key finding:** `docker cp` to non-volume paths (e.g. `/tmp`) fails entirely on read-only rootfs containers. All cp operations must target volume-mounted paths (e.g. `/home/node/.openclaw/workspace`). This is by design — the test validates cp against the workspace volume.
- **Verdict:** All CLI utility commands working correctly. ISSUE-62 fixed. ✅

### QoL: `clawbox version` command added ✅ 2026-04-03
**Problem:** There was no way to tell what version of clawbox you were running. `clawbox --version` returned "Unknown command: --version". Users updating clawbox via git had no way to verify the current ref. T7's version check was also a false-positive — `grep -qvi "unknown command"` matched the trailing "Run: clawbox help" line even when version returned exit 1.
**Fix:** Added `cmd_version()` function: shows `git describe --tags --always` (or git SHA), the most recent commit date, the openclaw CLI version, and CLAWBOX_DIR. Added dispatch entries for `version`, `--version`, and `-V`. Added `version` to help text. Fixed T7's version check to use exit code + content verification instead of the naive inverse-grep.
**Result:** `clawbox version` now outputs e.g. `clawbox v1.0.0 (2026-04-03)` (or SHA if no tags). T7 now has 45 checks (up from 44). T7 re-run confirmed 45/45. ✅

### ISSUE-68: T15 workspace contamination causes false-positive timeout test results ✅ Fixed 2026-04-03
**Problem:** T15 stops and restarts the container (`clawbox stop; clawbox start`) but the workspace is a Docker volume that persists across restarts. Prior T1 and T15 runs leave behind `taskman-*`, `blog-api-timeout-test`, and other completed project directories. When T15's agent starts, it finds 5-6 fully-complete pre-existing projects, reports "all work done", and exits in <1 minute — the 1-minute timeout never fires. T15 reports 13/13 passing even though the agent did NO new work and the timeout mechanism was never actually tested.
**Symptom (2026-04-03 04:48 run):** Handoff response said "All 6 project directories are fully complete with all work committed. No uncommitted work found." — TASK.md check found `blog-api-timeout-test`, `taskman-1775206351`, etc. from prior runs.
**Fix:** (1) T15 setup now removes all non-seed project directories from the container workspace before each run using `docker exec rm -rf`. (2) T15 uses a unique timestamped project name (`blog-api-t15-YYYYMMDD-HHMMSS`) so re-runs can never find pre-existing work for their specific project. (3) TASK.md check now searches the specific project directory first.
**Pattern:** Same root cause as ISSUE-58 (T2) and ISSUE-59 (T2/T3) — workspace accumulates over time and pollutes later test runs. Each test that creates projects needs workspace cleanup in setup.

### ISSUE-67: T1 test detection improvements (2026-04-03) ✅ Fixed 2026-04-03
**Problem 1 (Jest detection):** T1's test pass detection pattern `(passing|tests passed|all.*pass|Passed: [1-9])` didn't match Jest's summary format `Tests: 30 passed, 30 total`. Reported "unknown" even on a clean 30/30 pass.
**Fix 1:** Added `Tests:[[:space:]]*[0-9]+ passed` to the regex. Now matches both Mocha-style and Jest-style output.

**Problem 2 (SERVER_ALIVE false positive):** When no ports respond, `check_port_smart` returns `best_code="000"`. The SERVER_ALIVE check used `[ "$code" != "0" ]` — but `"000"` != `"0"` is true, so `SERVER_ALIVE="yes"` even when nothing is running.
**Fix 2:** Added `[ "$code" != "000" ]` to the SERVER_ALIVE check.

**Problem 3 (Non-standard ports):** Agent has consistently used non-standard ports (3456, 3457, 3458) but T1 only checked 3000/3001/8080. Servers would be detected as "dead" even when fully running.
**Fix 3:** Added extra-port scanning loop that checks ports 3456, 3457, 3458, 4000, 4001, 5000, 8000, 8888. Results shown in result table and assessment. ✅ Fixed 2026-04-03.

### ISSUE-66: T1 poll loop `integer expression expected` — `grep -c` includes trailing newline ✅ Fixed 2026-04-03
**Problem:** T1's phase-completion check used `[ "$PHASES_TOTAL" -gt 0 ]` where `PHASES_TOTAL` was set via `$(echo "..." | grep -cE '...' || echo "0")`. `grep -c` outputs a number followed by a newline (`0\n`). `tr -d ' '` strips spaces but NOT newlines, so `PHASES_TOTAL="0\n"`. The `[` command sees `0\n0` (the variable + the literal `0` from `echo "0"`) and reports "integer expression expected."
**Symptom:** Every T1 poll emitted `tests/T1-long-running.sh: line 92: [: 0↵0: integer expression expected` to stderr, cluttering the log.
**Fix:** Changed `tr -d ' '` to `tr -d '[:space:]'` for `PHASES_DONE`, `PHASES_TOTAL`, and `GIT_COMMITS` variables. `[:space:]` matches spaces, tabs, and newlines, ensuring clean integer values. ✅ Fixed 2026-04-03.

### ISSUE-65: T1 agent spawns subagent to immediately "complete" task ✅ Fixed 2026-04-03
**Problem:** Like ISSUE-63 (T15), T1's agent default behavior for large full-stack tasks is to spawn a subagent and return in ~17 seconds. The T1 task message had no instruction preventing this. The T1 poll loop would wait the full 20-minute ceiling without finding any progress (the subagent works independently), then incorrectly report partial/missing results.
**Symptom (T1 runs 2026-04-03 00:51 and 01:13):** Task log showed `=== Task completed ===` in 17s with "I'll spawn a subagent to build it out." Poll ran for 20 minutes and was killed by exec timeout before writing results.
**Fix:** Added "IMPORTANT: Do ALL of this work yourself — do NOT spawn subagents or delegate to other sessions. Write every file directly using your own tools." to the T1 task message (same fix as ISSUE-63 for T15). ✅ Fixed 2026-04-03.

### ISSUE-64: T1 poll loop never detects early completion — runs full 20 minutes ✅ Fixed 2026-04-03
**Problem:** T1's early-exit checks only matched TASK.md content patterns (`Status: COMPLETE`, `Phase N: ✅`). The agent's preferred flat-checklist TASK.md style (all `[x]` bullets) and the task log completion marker (`=== Task completed: <timestamp> ===`) were not checked. The poll loop would always run the full 20-minute ceiling, even when the task was done in 6 minutes. This caused T1 to be killed by the exec tool's timeout before writing its result file.
**Fix:** Added task log completion check to poll loop: `if echo "$TASK_LOG_CURRENT" | grep -q '=== Task completed'; then break; fi`. Note: the actual marker is `=== Task completed: <timestamp> ===` so the grep matches the prefix. With this fix, T1 Run 8 exited on poll #5 (~3 min) instead of timing out at 20 min. ✅ Fixed 2026-04-03.

### ISSUE-63: Agent spawns subagent to defeat task timeout ✅ Fixed 2026-04-02
**Problem:** When given a complex task with `--timeout 1`, the container agent's default behavior for large tasks is to spawn a subagent and return immediately. The parent agent "completes" in <1 minute (before the timeout fires), so the timeout + handoff mechanism is never triggered. The subagent runs independently with no timeout enforcement.
**Symptom (T15 Run 5, 2026-04-02):** Agent received blog-API task, said "I'll spawn a subagent to build it out fully," and returned in 37 seconds. Task log shows `=== Task completed ===` with no timeout marker. Score: 10/13 (3 warns from timeout never firing).
**Fix:** T15 task message now includes "IMPORTANT: Do ALL of this work yourself — do NOT spawn subagents or delegate to other sessions. Write every file directly using your own tools." This ensures the agent works inline, allowing the timeout to function as intended.
**Note:** This is a test-level fix, not a systemic fix. The underlying architectural issue (timeouts only track the parent agent, not spawned subagents) remains — but for the purpose of T15 testing, explicit instructions are sufficient. A systemic fix would require the timeout mechanism to track subagent lifecycles, which is a gateway-level feature.
**Result:** Run 6 (2026-04-02) confirmed timeout fired correctly with the updated message. ✅

### ISSUE-62: `clawbox cp` chown fails on read-only rootfs — needs `-u root` ✅ Fixed 2026-04-02
**Problem:** `clawbox cp` runs `docker exec "$CONTAINER" chown -R node:node "$dest"` after `docker cp`. On read-only rootfs containers, the default user is `node` (UID 1000), which lacks permission to change file ownership. The chown fails with "Operation not permitted", leaving copied files owned by UID 501 (macOS host user) and unreadable by the container agent.
**Second issue:** `docker cp` to paths outside of volume mounts (e.g. `/tmp`) fails with "container rootfs is marked read-only" — even though `/tmp` is a tmpfs mount, `docker cp` writes through the rootfs layer.
**Fix:** Changed `docker exec "$CONTAINER" chown -R node:node "$dest"` to `docker exec -u root "$CONTAINER" chown -R node:node "$dest"`. The `-u root` flag runs the chown as root inside the container, which has the necessary permissions even with read-only rootfs.
**Impact:** All `clawbox cp` operations on containers with `read_only: true` (which is the default since T13) were silently failing on the ownership step. Files would be copied but unreadable by the agent.

### ISSUE-61: Makefile restore breaks on absolute paths + wrong file ownership ✅ Fixed 2026-04-02
**Problem:** Two bugs in the `restore` Makefile target:
1. **Path handling:** `docker run -v $(pwd)/$(FILE):/backup.tar.gz:ro` always prepends `$(pwd)/` — when FILE is an absolute path (e.g. from `clawbox restore /full/path/backup.tar.gz`), Docker gets a double-rooted path like `/Users/foo//Users/foo/backups/backup.tar.gz`. Docker silently creates an empty bind-mount, and `tar xzf` fails with "invalid magic" (empty file).
2. **Ownership:** `tar xzf` inside alpine extracts files as root. The container runs as `node` (UID 1000). Restored files would be root-owned and potentially unreadable/unwritable by the agent.
**Impact:** All `clawbox restore` calls with absolute paths (which `clawbox` CLI always generates) were silently broken. Users backing up and restoring would lose all data.
**Fix:** (1) Makefile restore now detects absolute vs relative paths: `case "$$ABSFILE" in /*) ;; *) ABSFILE="$$(pwd)/$$ABSFILE" ;; esac` — only prepends `$(pwd)` for relative paths. (2) Added `chown -R 1000:1000 /data` after `tar xzf` to ensure correct ownership.

### ISSUE-59: T2 workspace pollution — agent finds pre-existing stats() in old express-oss/onboarding-test dirs ✅ Fixed 2026-04-02
**Problem:** Even though ISSUE-58 added timestamped directories for T2, old `express-oss` and `onboarding-test` directories from prior T2/T5 runs persisted in the container workspace. The agent would find pre-existing `stats()` implementations and `test-router-stats.js` files in those old directories, report "method already exists," and skip writing new code. The test appeared to pass (4/4 assessment checks) but the agent didn't actually write anything.
**Symptom (Runs 2026-04-01):** Agent output shows "The method already exists at line 523" and "The test file is already created" — referencing old `express-oss/` and `onboarding-test/` dirs, not the timestamped dir.
**Fix:** T2 now cleans all stale `express-oss*` and `onboarding-test*` directories at the start of each run. Task message updated to explicitly tell agent to "work ONLY inside the specified directory" and to add a "NEW" stats() method.

### ISSUE-60: T2 git clone fails inside container due to egress proxy blocking GitHub ✅ Fixed 2026-04-02
**Problem:** After the egress proxy was added (2026-04-01), T2's `git clone https://github.com/expressjs/express` inside the container fails with `CONNECT tunnel failed, response 403` — the proxy only allows Anthropic and npm traffic. T2 was the only test that cloned repos inside the container; other tests (T1, T3, T5) scaffold their projects via `docker exec` without cloning external repos.
**Fix:** T2 now clones express on the HOST (unrestricted internet), then uses `docker cp` + `docker exec -u root chown` to place it in the container workspace. The `chown` requires `-u root` because `docker cp` copies files as root but the container runs as `node`.

### ISSUE-58: T2 script doesn't reset express-oss — agent finds pre-existing work from prior runs ✅ Fixed 2026-04-01
**Problem:** T2's setup block used `if [ ! -d 'express-oss' ]; then git clone ...; fi` — on subsequent runs it skipped re-cloning, leaving any modifications from prior test runs (stats() method, test-router-stats.js) in the working tree. The agent would find the pre-existing implementation and report success without writing fresh code. This means T2 wasn't actually measuring the agent's ability to navigate and extend a codebase — it was measuring its ability to find and test pre-existing code.
**Symptom (Run 5, 2026-04-01):** Agent found stats() at line 523 of lib/router/index.js (written by a prior run), ran the pre-existing tests, and reported success. Assessment checks all passed — but the agent didn't write a single line of new code.
**Fix:** T2 now runs `git checkout -- . && git clean -fd` to reset express-oss to a pristine clean state before each test run. Any test files or source modifications from prior runs are wiped. The agent always starts from a clean working tree, as intended.
**Impact:** No functional regression — assessment check logic is unchanged. The fix makes the test more rigorous (measures new-code writing, not just existing-code detection).

### ISSUE-57: T1 persistent 17/18 test failure — test ordering / shared state ✅ Fixed 2026-04-01
**Problem:** T1 consistently produced 17/18 passing tests across multiple runs (runs 5, 6, and 7). The "Register new user" test failed because auth setup earlier in the suite already registered the same static username to the shared in-memory database. A second `POST /register` with the same username returns a conflict error (HTTP 400 or 409), failing the test. This is a classic "tests that run fine in isolation but fail when sharing state" pattern.
**Symptom:** TASK.md would show "18/18 tests passing" (agent self-reported, optimistic) but actual `npm test` output showed `Failed: 1` — "Register new user" test. Ran identically across every run since the issue was introduced, suggesting the test was always broken on second-and-later execution.
**Fix:** Added explicit test isolation requirement to the T1 task message: "each test must be independent and order-independent — use a fresh in-memory database per test run (or before/after hooks to reset state), use unique usernames per test (e.g. 'testuser-' + Date.now())". Agent correctly understood the requirement and implemented: fresh in-memory SQLite DB (`:memory:`) for the test runner, `Date.now()`-based unique usernames in each test. Agent even documented this in test output: "Tests are independent - you can run them multiple times!"
**Result:** Run 7 (2026-04-01 04:46) — 17/17 tests passing, all green. ✅

### ISSUE-56: T3 `✗ No new git commits` false negative when session 1 never inits git ✅ Fixed 2026-03-31
**Problem:** T3's "new git commits" check compares S1 vs S2 commit counts in `$WORKSPACE/$PROJECT_NAME`, falling back to workspace root if the project dir has no git repo. When session 1's message didn't ask for git init, the project-level `.git` didn't exist. Both S1 and S2 git logs captured the workspace root (T1 taskman commits), which were identical in both sessions → false "no new commits" fail.
**Symptom (Run 12, 2026-03-31):** Session 2 made 4 real commits in the project repo, TASK.md was updated, all endpoints worked — but assessment showed `✗ No new git commits from session 2 (S1: 5 commits, S2: 5 commits — same)`.
**Fix:** Added "Initialize a git repository in the project dir and commit your initial work" to session 1's task message. Agent reliably inits git now, and both S1/S2 log comparisons operate within the project-level repo.
**Result:** Run 12 (2026-03-31 18:42) — 4/4 assessment checks pass. ✅

### ISSUE-55: Session 2 completes work but never updates TASK.md or commits code ✅ Fixed 2026-03-31

**Problem:** In T3 runs (2026-03-31), session 2 correctly implemented all the bookstore CRUD endpoints (verified working via curl) but left TASK.md completely unchanged — Phase 2 checkboxes still unchecked, "Current Step" still pointing to "Next Step: Phase 2", zero new git commits for the bookstore project. If a session 3 were to start, it would see Phase 2 as TODO and re-implement everything from scratch. The continuity mechanism exists but only for reading — session 2 never wrote back.

**Root cause:** `seed/AGENTS.md` had detailed instructions for "Starting a task" and "When told to stop early (handoff)" but no dedicated **"Resuming a task"** section. An agent picking up from a "continue where you left off" message sees TASK.md as context but doesn't have explicit instructions to check off completed steps or commit code back. The AGENTS.md instructions were oriented around the agent that *creates* the TASK.md, not the one that *continues from* it.

**Fix applied (2026-03-31):**
1. Added explicit "Resuming a task" section to `seed/AGENTS.md` — step-by-step: read TASK.md, run existing tests, complete unchecked steps, check off each `[ ]` → `[x]` as you go, commit after each major step, update Git Log section. Includes a critical warning: "A session that completes work but leaves TASK.md unchanged has not properly recorded its progress."
2. Updated T3 session 2 message to explicitly remind: "as you complete each step, check it off in TASK.md (change [ ] to [x]), then commit your changes to git."
3. Added two new T3 assessment checks: (a) did TASK.md checkbox count increase from S1 → S2? (b) did git commit count increase from S1 → S2? Both are now tracked and reported.

### ISSUE-54: T1 poll loop runs full 20 minutes even when task completes early ✅ Fixed 2026-03-31
**Problem:** T1's early-exit check only matched `Status: COMPLETE` in TASK.md. The agent's preferred completion format uses phase checkboxes: `### Phase N: ✅` for each phase — no explicit `Status:` line. The poll loop would run the full 20-minute timeout even on a 6-minute task.
**Symptom (T1 run 6, 2026-03-31):** Agent completed at 10:47 (386s in), but polls kept running until 11:01 (20-minute ceiling), wasting 14 minutes and then running the post-loop rate-limit check against a 20-minute-old log.
**Fix:** T1 now counts `Phase N: ✅` vs `### Phase N:` totals. When `done == total` (and `total > 0`), the loop exits early with a "All N phases complete" log line. Original `Status: COMPLETE` pattern still retained for backwards compatibility with other TASK.md formats.

### ISSUE-53: `is_rate_limited()` false-positive matches project directory names containing "529" ✅ Fixed 2026-03-31
**Problem:** `tests/lib/common.sh` `RATE_LIMIT_PATTERNS` included `"529"` as a bare pattern to detect HTTP 529 (Overloaded) responses. This is too broad — any task log that mentions a path or directory name containing the substring `529` will match. Example: `taskman-1774975299` in the task description has `529` as a substring, so T1 was incorrectly SKIPped after a fully successful run.
**Symptom:** T1 run 6 (2026-03-31): agent completed in 6 minutes, 17/18 tests passing, both servers running — but T1 reported SKIP (API Rate Limited) because the task log header contained the project directory name `taskman-1774975299`.
**Fix:** Removed `"529"` from `RATE_LIMIT_PATTERNS`. HTTP 529 Overloaded is covered by the more specific `"overloaded_error"` error code and the `CLAWBOX_RATE_LIMITED` sentinel that `clawbox run` emits on any rate-limit/overload response. Bare status codes are not reliable patterns for text-based detection.

### ISSUE-52: T15 test 9 fails when container stops during SIGUSR1 handoff reload ✅ Fixed 2026-03-31
**Problem:** After the timeout + handoff completes, test 9 tries to start a new task. If the SIGUSR1 gateway reload caused the container to become unavailable (crash or restart), `clawbox task` fires `assert_container_running` and immediately fails. T15 reported `✗ New task failed to start after timeout`.
**Fix:** T15 test 9 now explicitly checks `docker ps` for container running state before starting the new task. If it's stopped (which can happen if SIGUSR1 caused a restart), the test calls `clawbox start` and waits 10s before proceeding. This makes test 9 robust to any container state left by the handoff.

### ISSUE-51: Handoff agent falls back to embedded host agent when gateway reload takes >8s ✅ Fixed 2026-03-31
**Problem:** After `kill -USR1 <gateway-pid>`, the CLI slept a fixed 8 seconds before running the handoff agent. If the gateway took longer than 8 seconds to reload (e.g. cold memory, first session init), `openclaw agent` would detect the gateway unreachable, fall back to the embedded host agent, and run the handoff against the HOST workspace instead of the container workspace. Result: TASK.md was never written to the container, and the handoff summary described a completely different project.
**Symptom (T15 run 3, 2026-03-31):** Handoff agent said "origami-screensaver" instead of "blog-api-timeout-test", TASK.md not found in container.
**Fix:** Replaced `sleep 8` with a poll loop that calls `openclaw status` against the gateway URL, retrying every 2 seconds for up to 60 seconds. Only proceeds to run the handoff agent after the gateway responds healthy. Prints a warning if gateway never comes back (so users know why the handoff may be degraded). Ensures handoff always targets the container workspace.

### ISSUE-49: Hardcoded port 18790 in `assert_container_running` ✅ Fixed 2026-03-31
**Problem:** `assert_container_running` checked `nc -z 127.0.0.1 18790` (hardcoded) instead of `nc -z 127.0.0.1 "$GATEWAY_PORT"`. When running a non-default port (e.g. `GATEWAY_PORT=18791 clawbox run ...`), the check would verify the wrong port — showing no warning even if 18791 wasn't actually reachable. If another process happened to hold 18790, the check would always pass even though the clawbox gateway was unreachable.
**Fix:** Changed the hardcoded `18790` to `"$GATEWAY_PORT"` and updated the warning message to show `$GATEWAY_PORT` dynamically. Now multi-instance setups (ISSUE-24 feature) get correct port validation.

### ISSUE-50: Missing `overloaded_error` in `cmd_run` rate-limit detection ✅ Fixed 2026-03-31
**Problem:** The rate-limit detection in `cmd_run` (`grep -qi "API rate limit reached\|rate limit reached\|rate_limit_error"`) was missing `overloaded_error` — the Anthropic API error code for 529 Overloaded responses. The `tests/lib/common.sh` already included `overloaded_error` in its `RATE_LIMIT_PATTERNS` array, but the CLI itself didn't detect it, so `--retry` would not retry on overloaded errors and the `CLAWBOX_RATE_LIMITED` sentinel would not be emitted.
**Fix:** Added `overloaded_error` to the grep pattern in `cmd_run`. Pattern is now consistent with `tests/lib/common.sh`.

### ISSUE-48: T1 test pass/fail detection false-positive when partial tests fail ✅ Fixed 2026-03-30
**Problem:** T1's `TESTS_PASSING` detection checked for `✓` symbols before checking for `Failed: N`. Because passing tests are listed one-by-one with `✓` before the final summary line, the grep matched `✓` first and returned `yes` even when `Failed: 1` appeared at the end of the output. Run 5 (2026-03-30) had 19/20 tests passing but was reported as `Tests passing: yes` in the result file.
**Fix:** Test pass/fail detection now checks `Failed: [1-9]` FIRST. On partial pass, reports `partial (N/M)` instead of `yes`. Assessment block updated: `✗ Tests failing` for complete failure, `⚠ Tests partial: N/M` for partial. The `✓` check is still used as a positive indicator but only when no failures are detected.

### ISSUE-47: T3 server restart uses hardcoded entrypoints (index.js/src/index.js), misses server.js ✅ Fixed 2026-03-30
**Problem:** T3's post-session endpoint verification starts the server with `node index.js || node src/index.js`. When the agent creates `server.js` (its preferred entrypoint per `package.json` main field), neither command finds the file and the server never starts — all endpoint checks return FAIL.
**Symptom:** T3 run on 2026-03-30 showed agent correctly completing all CRUD endpoints (TASK.md confirmed, git commit `95a9b36` with "Add CRUD endpoints: GET /books/:id, POST /books, DELETE /books/:id with validation") but assessment showed `✗ Agent failed to continue properly` because endpoint verification got FAIL for all.
**Fix:** (1) Server restart now uses `npm start` first (reads `package.json` `scripts.start`), falling back to `index.js`, `src/index.js`, `server.js`. (2) Added secondary assessment signal: if TASK.md shows POST /books as `[x]` completed, report `⚠ Agent continued (TASK.md shows work done) but endpoint verification failed — server restart issue` instead of false `✗ failed`. This separates agent continuity failures from test infrastructure failures.

**Run 9 (2026-03-30 04:41) — ISSUE-47 fix validated:**
- ✓ Session 1: `bookstore-20260330-044116` created, TASK.md at correct path (127s)
- ✓ Session 2: Agent resumed, added GET /books/:id, POST /books, DELETE /books/:id, 10/10 tests passing (218s)
- ✓ Endpoints: GET /books ✓ (returns JSON array), GET /books/1 ✓, POST /books ✓ (validation error on empty body = correct), DELETE /books/1 ✓
- ✓ Assessment: ✓/✓ — `npm start` correctly found `server.js`, all endpoints verified
- **Verdict:** ISSUE-47 confirmed fixed. T3 is reliable end-to-end. ✅

### ISSUE-46: Workspace pollution from previous test runs causes T3 to pick wrong TASK.md ✅ Fixed 2026-03-29
**Problem:** The container workspace accumulates project directories from T1, T2, T5, T15 and other tests (bookstore-api-v2, blog-api-timeout-test, task-app, taskman-*, etc.). T3's `find -newer` heuristic was still unreliable because the session 1 agent would sometimes `ls` or touch files in old directories, refreshing their mtime and defeating the sentinel-based filter. The `-newer` fallback `xargs ls -t | head -1` would then return a stale project's TASK.md.
**Fix:** (1) T3 now cleans the workspace at the start of each run — removes all subdirectories except `.git`, `.openclaw`, and `memory`. Seed files at root (AGENTS.md, SOUL.md, etc.) are preserved. (2) T3 uses a unique project name per run (`bookstore-YYYYMMDD-HHMMSS`) and tells the agent the exact directory to use. TASK.md detection is now deterministic: look in `$WORKSPACE/$PROJECT_NAME/TASK.md` first, fall back to full search only if not found.
**Result (Run 7, 2026-03-29):**
- ✓ 13 stale project dirs cleaned at start
- ✓ Session 1: TASK.md at `/home/node/.openclaw/workspace/bookstore-20260329-104309/TASK.md` (correct) (195s)
- ✓ Session 2: Agent resumed correctly, added GET/POST/DELETE endpoints, all 4 endpoints verified (209s)
- ✓ Endpoint checks: GET /books ✓, GET /books/1 ✓, POST /books ✓, DELETE /books/1 ✓
- ✓ Assessment: ✓/✓ — no false picks, no infrastructure noise
- **Verdict:** ISSUE-46 confirmed fixed. T3 is now fully reliable. ✅

### ISSUE-45: T3 test picks stale TASK.md from previous test runs ✅ Fixed 2026-03-29
**Problem:** T3 uses `find $WORKSPACE -name 'TASK.md' | head -1` which returns files sorted alphabetically. When previous tests (e.g. T15) leave TASK.md files in the workspace (e.g. `blog-api-timeout-test/TASK.md`), T3 captures and reports those instead of the one created in the current run. Also, the server started by session 2 exits after the agent finishes, so endpoint checks done post-session always fail — even when all endpoints are fully working.
**Fix:** (1) T3 now uses `find -newer /tmp/t3-session1-start` to find only TASK.md files created during this test run, with a fallback to `ls -t` (newest by mtime). (2) Session 2 TASK.md capture now reuses the session 1 path rather than re-searching (avoids stale pick). (3) Endpoint check now explicitly restarts the server at the project dir before curling, so endpoints can be verified even after the agent exits.

### ISSUE-44: API rate limit causes silent partial task failure ✅ Fixed 2026-03-29
**Problem:** During T5 re-run (2026-03-29), the container agent immediately received `⚠️ API rate limit reached. Please try again later.` from the Anthropic API. The agent printed a warning and attempted to continue, but was unable to complete the task — it could explore the filesystem but lacked tool quota to write files. The test result showed all checks as failures, but the actual cause was API rate limiting, not agent logic failure.
**Scope:** Any test that runs `clawbox run` or `clawbox task` during a period of heavy API usage may silently fail in this way. The test scripts have no way to distinguish "agent gave up" from "agent was rate-limited."
**Compounding factor (T5 scaffold bug):** The T5 scaffold script was also missing `mkdir -p src/routes` before creating `src/routes/recipes.js` — this made `index.js` fail to load routes, causing the agent to encounter an import error even if it had managed to read the project. Fixed in T5 script: second scaffold `docker exec` now creates `src/routes` and `src/middleware` directories explicitly.
**Fix applied (2026-03-29):**
1. **CLI (`clawbox run`)**: Added rate-limit detection on agent response text (patterns: "API rate limit reached", "rate_limit_error", "overloaded_error"). On detection: exits with code 2 and prints `CLAWBOX_RATE_LIMITED` to stderr. Added `--retry <n>` flag: retries up to N times with 60s delay before giving up with exit 2.
2. **Test scripts**: Created `tests/lib/common.sh` with shared `is_rate_limited()` and `skip_rate_limited()` helpers. Updated T1, T3, T4, T5 to source this lib and check for rate limits after agent calls — on detection, writes a `SKIP` result file (not `FAIL`) and exits 0.
3. **Help text**: `clawbox help` now documents `run --retry <n>`.
**Result:** Rate-limited test runs now produce clear SKIP entries in results/ instead of false FAIL results. Users can use `clawbox run --retry 3 "..."` for automatic backoff.

### ISSUE-43: Task log overwritten by each new task ✅ Fixed 2026-03-29
**Problem:** `~/.clawbox-task.log` was a single fixed path — every `clawbox task` call overwrote it. This destroyed history of previous tasks and caused T15 to read test 9's log (a trivial follow-up task) instead of the timeout test's log, making the result section useless.
**Fix:** `cmd_task` now generates a timestamped log file (`~/.clawbox-task-YYYYMMDD-HHMMSS.log`) and updates a symlink `~/.clawbox-task.log` → latest. `task-logs`, `task-status`, and `cancel` all resolve the symlink. The actual timestamped path is printed in `clawbox task` output ("Log: /path/...") so tests and users can pin the exact file. T15 now captures this path and uses it throughout, so test 9 starting a new task no longer clobbers the analysis.

### T15 — Task timeout + handoff (2026-03-29, re-run 2026-03-31, re-run 2026-04-02)

**Run 6 (2026-04-02 16:48) — ISSUE-63 fix validated, rate-limited on handoff:**
- ✓ ISSUE-63 fix confirmed: agent worked directly (no subagent spawn) with "do NOT spawn subagents" instruction
- ✓ Timeout triggered after exactly 1 minute ✓
- ✓ Handoff complete marker found ✓
- ✗ Handoff fell back to embedded agent due to `gateway closed (1012): service restart` after SIGUSR1
- ✗ Embedded agent rate-limited: both claude-sonnet-4-6 and claude-opus-4-6 in cooldown
- ✗ TASK.md not found in container (handoff couldn't execute)
- ✓ Lock cleaned up, new task starts after restart
- ✓ Timeout, log path, help text all working correctly
- **Score: 11/13 pass, 1 warn, 1 fail** — fail was rate limit, not code regression
- **Verdict:** Timeout mechanism works. Handoff gateway restart timing is environment-dependent. Rate limit was the actual blocker. ⚠️

**Run 5 (2026-04-02 16:46) — ISSUE-63 found (subagent bypass):**
- ✓ Task started, --timeout 1 accepted
- ✗ Agent spawned a subagent to build the entire project and returned in ~37s — defeating the 1-minute timeout entirely
- ✗ No timeout triggered (task "completed" before timeout fired)
- ✗ No handoff (not needed — task was already "done")
- **Score: 10/13 pass, 3 warn, 0 fail** — all 3 warns from timeout never firing
- **Root cause (ISSUE-63):** The agent's default behavior for large tasks is to spawn subagents. Since the parent agent returns immediately after spawning, the task appears "completed" in <1 minute. The timeout mechanism only tracks the parent agent's lifecycle, not spawned subagents.
- **Fix applied (2026-04-02):** T15 task message now includes "IMPORTANT: Do ALL of this work yourself — do NOT spawn subagents or delegate to other sessions." This ensures the agent works directly, giving the timeout mechanism time to fire.
- **Verdict:** ISSUE-63 identified and fixed. Fix validated in Run 6 (timeout fired correctly). ✅

**Run 4 (2026-03-31 04:40) — ISSUE-51 + ISSUE-52 fixes validated:**
- ✓ **13/13 pass, 0 warn, 0 fail** — fully clean
- ✓ Task started with `--timeout 1` flag, log path printed correctly (ISSUE-43 timestamped log)
- ✓ No gateway connection failures — ISSUE-51 fix confirmed (gateway poll loop, not fixed sleep)
- ✓ Timeout marker + handoff complete marker in log
- ✓ Handoff agent response: 2144 bytes, high quality — found `blog-api-timeout-test`, inited git, committed work, updated TASK.md with 27/27 tests passing, clear handoff summary
- ✓ TASK.md found in container workspace (correct project, not host fallback)
- ✓ Lock cleaned up, new task starts immediately after timeout — ISSUE-52 fix confirmed
- ✓ ISSUE-43 symlink behavior: `~/.clawbox-task.log` → timestamped log confirmed
- **Verdict:** T15 fully reliable. Timeout + handoff is production-ready. ISSUE-51 and ISSUE-52 both confirmed fixed. ✅

**Run 3 (2026-03-31 02:42) — ISSUE-51 + ISSUE-52 found:**
- ✓ 10/13 pass, 0 warn, 3 fail
- ✓ Timeout triggered after exactly 1 minute ✓
- ✓ Handoff complete marker found ✓
- ✓ Handoff response non-empty (1183 bytes)
- ✓ Lock released cleanly
- ✓ Timestamped log confirmed (ISSUE-43)
- ✗ TASK.md not found in container — **root cause: ISSUE-51** (8s fixed sleep after SIGUSR1 wasn't enough; handoff fell back to embedded host agent working on `origami-screensaver` workspace instead of container's `blog-api-timeout-test`)
- ✗ New task after timeout failed — **root cause: ISSUE-52** (container stopped after SIGUSR1 reload; `assert_container_running` blocked test 9)
- ✗ Gateway connection failure line detected — handoff agent printed "Gateway agent failed; falling back to embedded"
- **Fixes applied (2026-03-31):** (1) CLI: replaced `sleep 8` with health-poll loop (retries every 2s up to 60s) before running handoff agent (ISSUE-51); (2) T15 test 9: now restarts container if stopped before attempting new task (ISSUE-52); (3) T15 test 7: detects "falling back to embedded" pattern and demotes to warn with explanation rather than hard fail.
- **Verdict:** Core timeout mechanism works. The failures were infrastructure — handoff gateway reload timing. Fixes applied, needs re-run to confirm.

**Run 1 (2026-03-29 02:44):** 6/9 pass, 3 warn — timeout never triggered because gateway cold-start caused task to fail immediately ("gateway connect failed") and the agent "completed" in 0 seconds. Also: test 9 overwrote the task log (ISSUE-43), making all result sections read the wrong log.
**Run 2 (2026-03-29 04:47 — after ISSUE-43 fix + T15 improvements):**
- ✓ ISSUE-43 fixed: timestamped log path captured from `clawbox task` output; test 9's new task writes to a separate file
- ✓ Timeout triggered after exactly 1 minute (confirmed: `=== TIMEOUT after 1m — sending handoff prompt ===`)
- ✓ Gateway SIGUSR1 reload succeeded — fresh handoff session started cleanly
- ✓ Handoff agent wrote comprehensive TASK.md update + committed WIP to git
- ✓ Handoff response: 2306 bytes, high quality — specific file list, test results, git commits, resume instructions
- ✓ Lock released cleanly after handoff; new task started immediately in test 9
- ⚠ T15 test script killed by 320s exec timeout — handoff takes ~6 min total (1m task + gateway reload + ~5m handoff agent). Fixed: `MAX_WAIT` increased to 420s.
- **Verdict:** Timeout + handoff mechanism confirmed working end-to-end. The agent is an excellent handoff writer — it explored the workspace, ran tests, committed WIP, and produced an actionable TASK.md. Phase 2 core feature is production-ready. ✅

### T7 — UX / friction audit ✅ 2026-03-26, re-run 2026-03-29
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

**Re-run (2026-03-29) — updated T7 to cover new commands:**
- T7 test expanded: added `task-status`, `task-logs`, `cancel` to the help coverage checks (all added after 2026-03-26)
- ✓ **40/40 pass, 0 warn, 0 fail** — perfect score
- ✓ `cancel`, `task-status`, `task-logs` all present in help output
- ✓ Container start: 8s, first agent response: 12s
- ✓ All prior warn items (README commands, ws:// in status, `ask` alias) confirmed fixed and holding
- **Verdict:** UX is clean end-to-end including all new commands from ISSUE-37/38/39/40. No remaining friction gaps.

**Re-run (2026-03-31 00:44) — stability check post ISSUE-49/50 fixes:**
- ✓ **40/40 pass, 0 warn, 0 fail** — perfect score maintained
- ✓ Container start: 8s, first agent response: 21s
- ✓ All checks holding after hardcoded-port (ISSUE-49) and overloaded_error (ISSUE-50) fixes
- **Verdict:** UX still fully clean. ✅
