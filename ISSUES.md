# ISSUES.md — Open Issues / Tracked Gaps

Issues discovered during stress testing and security audits.
Format: `[STATUS] ISSUE-N: Title`
Status: OPEN | FIXED | WONTFIX | INFO

---

## [INFO] ISSUE-1: host.docker.internal exposes host HTTP UI to container

**Category:** Security — macOS Docker Desktop behavior
**Severity:** Low
**Discovered:** 2026-03-24 Category B security tests

**Description:**
On macOS with Docker Desktop, `host.docker.internal` resolves to a virtual IP that proxies back to the Mac host. Any host port bound to `127.0.0.1` is reachable from inside the container via this hostname. The host OpenClaw gateway's HTTP control panel (port 18789) returns HTTP 200 from inside the container.

**What's blocked:**
- WebSocket API requires a valid auth token — container cannot authenticate
- OpenClaw CLI refuses plaintext `ws://` to non-loopback addresses (security error)

**What's exposed:**
- HTTP 200 on the host control panel HTML (no sensitive data, just the SPA shell)

**Risk:** Low. API access is gated. UI HTML exposure is cosmetic.

**Recommendations for high-security deployments:**
- Use Docker Engine on Linux (not macOS Docker Desktop) — behavior differs
- Add `extra_hosts` to override `host.docker.internal` to a dead IP
- Run host gateway on an unpredictable port or disable when not in use

---

## [INFO] ISSUE-2: ANTHROPIC_API_KEY readable via /proc/1/environ

**Category:** Security — expected Docker env var behavior
**Severity:** Medium (inherent to threat model)
**Discovered:** 2026-03-24 Category B security tests

**Description:**
Any process running as `node` inside the container can read `/proc/1/environ` (or `/proc/self/environ`) and extract the `ANTHROPIC_API_KEY`. This is standard Docker behavior — environment variables are always accessible to same-user processes.

**Impact:**
- Agent-executed code (via `exec` tool) can access the API key
- Inherent to giving the agent API credentials — expected behavior
- Documented in SECURITY.md

**Recommendations for high-security deployments:**
- Use Docker secrets (key mounted at `/run/secrets/` instead of env)
- Rotate API key per session
- Use scoped keys with spend limits

---

## [OPEN] ISSUE-3: No pids_limit in docker-compose.yml (kernel-level cgroup enforcement)

**Category:** Resource limits
**Severity:** Low
**Discovered:** 2026-03-24 Category B security tests

**Description:**
Docker compose had `ulimits.nproc` (per-user process limit) but no `pids_limit` (kernel cgroup PID limit). The cgroup limit is enforced at a lower level and harder to bypass.

**Status:** FIXED in commit after Category B testing — `pids_limit: 512` added.

---

## [OPEN] ISSUE-4: GitHub repo URL is placeholder

**Category:** Documentation
**Severity:** Low
**Discovered:** Earlier sessions

**Description:**
README.md contains placeholder `https://github.com/your-org/clawbox.git`. Repo not yet published.

**Action required:** Xander needs to create the repo and push. No code changes needed.

---

## [INFO] ISSUE-5: CAP_DAC_OVERRIDE grants wide file read/write

**Category:** Security — capability minimization
**Severity:** Low (inherent to Node.js runtime)
**Discovered:** 2026-03-24 Category B security tests

**Description:**
`CAP_DAC_OVERRIDE` allows the container process to read/write any file regardless of Unix permission bits. This is needed by Node.js (npm install, file operations in agent workspace) but is a powerful capability.

**Mitigations already in place:**
- `no-new-privileges:true` prevents escalation
- No setuid binaries (verified)
- Runs as non-root user `node`
- Read-only mount for `/host-repos`

**Note:** Removing `DAC_OVERRIDE` would likely break npm and file operations. Accept as-is or test without it.

---

## [INFO] ISSUE-6: Fork bomb contained but /proc/1/environ check during flood showed "resource temporarily unavailable"

**Category:** Resource limits — fork bomb behavior
**Severity:** Low
**Discovered:** 2026-03-24 Category B security tests

**Description:**
During fork bomb test, attempting to run `find / -xdev -perm /6000` immediately after returned `exec /bin/sh: resource temporarily unavailable`. After ~10 seconds, new shells were available again (nproc limit released as zombie processes were reaped by tini).

**Assessment:**
- Fork bomb was contained — container survived, 0 restarts
- Brief window (~10s) where new shell commands couldn't execute — acceptable behavior
- `pids_limit: 512` (now added) provides kernel-level enforcement as second layer

---

## [OPEN] ISSUE-7: No seccomp profile

**Category:** Security — syscall filtering
**Severity:** Medium (for enterprise deployments)
**Discovered:** Design review

**Description:**
No custom seccomp profile is applied. Docker's default seccomp profile is active (blocks ~44 syscalls) but a Node.js-tuned profile would additionally block `ptrace`, `reboot`, `kexec_load`, `mount`, etc.

**Action:** Define and test a custom seccomp profile for Node.js + OpenClaw. Would be a meaningful hardening step for enterprise/risk-management deployments.

---

## [OPEN] ISSUE-9: No disk quota enforcement (no /tmp tmpfs limit)

**Category:** Resource limits
**Severity:** Medium
**Discovered:** 2026-03-24 Category C resource limit tests

**Description:**
No disk quota is enforced inside the container. The workspace volume is backed by Docker Desktop's overlay2 filesystem on macOS, which doesn't support `storage_opt` quotas. The `/tmp` directory was also unbounded — a rogue process could fill the host disk.

**`dd` test results:**
- 200MB writes to `/tmp` and workspace: both succeeded with no blocking
- Larger writes (1500MB) with `/dev/zero` triggered OOM (via memory buffer), not disk quota
- No disk-space cap was hit — a careful attacker could fill disk without hitting memory limit

**Fix applied (2026-03-24):** Added `tmpfs: [/tmp:size=256m,mode=1777]` to docker-compose.yml.
- `/tmp` is now a ramdisk capped at 256MB (counts toward memory limit)
- Workspace volume still has no quota (macOS Docker Desktop limitation)

**Remaining gap:** Workspace volume (`/home/node/.openclaw`) has no disk quota. On Linux with ext4 + project quotas or overlay2 with `size=` option, this can be enforced.

**Action for enterprise:** Use Linux Docker Engine with `--storage-opt size=10G` or quota-enabled filesystem.

---

## [PARTIAL-FIX] ISSUE-10: Memory limit allows virtual over-allocation (zero-page CoW bypass)

**Category:** Resource limits
**Severity:** Medium
**Discovered:** 2026-03-24 Category C resource limit tests
**Partially fixed:** 2026-03-25 Category C cycle 2

**Description:**
Docker's 512MB memory limit (`memory: 512m`) only triggers the OOM killer when physical pages are actually faulted in (dirty/written). A Node.js script using `Buffer.alloc()` with zero-fill can allocate huge virtual address space without triggering the cgroup memory limit (zero pages use Linux's CoW optimization and don't fault pages in).

**Test results (Cycle 1):**
- `Buffer.alloc(10MB)` × N (zero-filled) → 566GB virtual allocated, no OOM trigger, exit code 137 from timeout (container OOM killed)
- `Buffer.alloc(10MB)` + dirty write (1 byte per page) → OOM kill at ~750MB (512MB RAM + 512MB swap), correct behavior
- The OOM killer kills only the offending process, not the container

**Fix applied (Cycle 2):**
- Added `ulimit -v 16777216` (16GB virtual address cap) in `entrypoint.sh` before starting the gateway
- The ulimit applies to the gateway process and ALL its child processes (exec tool spawns)
- RLIMIT_AS verified: `Max address space = 17179869184` (16GB) in gateway's `/proc/<pid>/limits`
- **Scope**: Agent exec tool children = bounded ✅. `docker exec` sessions = still unlimited (separate process tree, requires host admin access — higher trust level)

**Remaining gap:**
- `docker exec` creates a new process NOT inheriting the gateway's ulimit — shows `unlimited`
- This is acceptable: `docker exec` requires host-level admin access; the threat model is rogue agent code, not admin shell
- Production Linux deployments can add `--ulimit` flags to `docker run` to enforce on all processes

**Mitigations in place:**
- `ulimit -v 16GB` caps agent-spawned processes ✅
- `NODE_OPTIONS=--max-old-space-size=384` caps V8 JS heap ✅
- `memory.max=512MB` + `memory.swap.max=512MB` (cgroup) = 1GB total hard limit ✅
- OOM killer kills only the offending process, container survives ✅

---

## [FIXED] ISSUE-11: socat not in restart loop — container becomes a brick if socat dies

**Category:** Resilience
**Severity:** Medium
**Discovered:** 2026-03-24 Category E recovery and resilience tests

**Description:**
socat was started with a bare `socat ... &` — no restart loop. If socat was killed (e.g., by a process flood consuming the PID namespace, an OOM event, or a direct `pkill socat`), the container kept running but ALL CLI connections from the host were permanently severed. The gateway kept running but was unreachable. Only `docker compose restart` could recover.

**Test result:**
- `docker exec clawbox-work pkill -f socat` → container stayed up, CLI returned "gateway closed (1006 abnormal closure)"
- Container kept running, gateway kept running, but host had no path to it

**Fix (2026-03-24):** Wrapped socat in a while loop in entrypoint.sh (mirroring the existing gateway restart loop). socat now auto-restarts after 1s if it dies.
```sh
(
  while true; do
    socat TCP-LISTEN:18789,bind=0.0.0.0,fork,reuseaddr TCP:127.0.0.1:18788
    echo "▶ socat exited — restarting in 1s..."
    sleep 1
  done
) &
```

**Verification:**
- `pkill -f socat` → socat restarted, CLI immediately reconnected
- Agent responded SOCAT_RESTART_OK with 0 container restarts

---

## [INFO] ISSUE-12: Unrestricted outbound internet access (data exfiltration surface)

**Category:** Security — network egress policy
**Severity:** Medium (for high-security/risk-management deployments)
**Discovered:** 2026-03-25 Category B security tests (cycle 2)

**Description:**
The container has full, unrestricted outbound internet access. Any agent-executed code or tool call can reach arbitrary external endpoints. Verified:
- `curl https://example.com` → HTTP 200
- `curl https://httpbin.org/get` → HTTP 200  
- DNS resolves arbitrary hostnames
- Agent confirmed outbound via exec tool: `HTTP_STATUS:200`

**Impact:**
- An agent (or malicious prompt-injected code) could exfiltrate data from the workspace to an external endpoint
- API key in `/proc/1/environ` could be sent outbound
- No audit trail for network activity

**What IS restricted:**
- Inbound connections blocked (ports are loopback-only on host)
- Container cannot reach other containers via bridge network's 172.17.0.1 (port refused)
- `host.docker.internal` reaches only loopback-mapped ports on the host (documented in ISSUE-1)

**Risk assessment:**
The primary use case (agent calling Anthropic API) requires outbound HTTPS to `api.anthropic.com`. Full internet lock-down would break this. However, for risk-management deployments, egress filtering is a meaningful control.

**Recommendations for high-security deployments:**
1. Use a custom Docker network with `internal: true` + explicit allow rules for Anthropic API
2. Use an HTTP proxy (squid/nginx) that only allows `*.anthropic.com` and required package registries
3. Add network policy via iptables or a sidecar proxy container
4. Monitor network logs for unexpected external connections

---

## [INFO] ISSUE-13: CAP_DAC_OVERRIDE in compose is inert for non-root user (documentation clarification)

**Category:** Security — capability model clarification
**Severity:** Informational
**Discovered:** 2026-03-25 Category B security tests (cycle 2)

**Description:**
The compose file adds `CAP_DAC_OVERRIDE` and other capabilities, but since the container runs as `node` (uid=1000), all effective capabilities are `0x0000000000000000`. Capabilities only apply to root-transitioning processes. The `node` user has no effective capabilities regardless of `cap_add`.

This means:
- `/etc/shadow` (0640 root:shadow) is unreadable — confirmed ✅
- `CAP_DAC_OVERRIDE` cannot be exercised by `node` user processes
- The `cap_add` entries in compose are effectively a no-op for uid=1000

**Impact:** Positive finding — security is actually stronger than the compose config implies. The capability restrictions are belt-AND-suspenders.

**Action:** Update SECURITY.md to document this nuance clearly for auditors.

---

## [INFO] ISSUE-14: Fork bomb recovery requires docker compose restart (self-DoS window)

**Category:** Resource limits — resilience gap
**Severity:** Low
**Discovered:** 2026-03-25 Category B security tests (cycle 2) — confirmed from cycle 1

**Description:**
After a fork bomb (even one that's "contained" by nproc/pids_limit), the container enters a wedged state where `docker exec` returns `sh: can't fork: Resource temporarily unavailable`. This persists for 10-30 seconds while tini reaps zombie processes. During this window, no new commands can run including health check commands.

The healthcheck eventually fails and Docker marks the container unhealthy, but since `restart: "no"`, it doesn't auto-recover. The operator must run `docker compose restart`.

**Impact:**
- Deliberate fork bomb can create a 10-30s window where the agent is unreachable
- No auto-recovery without changing restart policy

**Mitigations already in place:**
- pids_limit: 512 (kernel cgroup)
- nproc ulimit: 256/512

**Recommendations:**
- Change `restart: "no"` to `restart: on-failure` or `unless-stopped` for production
- Consider reducing pids_limit further (256?) to speed up recovery
- Document in runbook: recovery = `docker compose restart`

---

## [OPEN] ISSUE-8: No read-only root filesystem

**Category:** Security — filesystem hardening
**Severity:** Low-Medium
**Discovered:** Design review

**Description:**
`ReadonlyRootfs: false` — container filesystem is writable. A read-only rootfs with `tmpfs` for `/tmp` and writable overlay for npm cache would reduce blast radius.

**Challenge:** Node.js / npm require several writable paths. Needs careful `tmpfs` mapping.

**Action:** Test with `read_only: true` + appropriate tmpfs mounts.

---

## [INFO] ISSUE-15: FD exhaustion limited at 4096 (nofile hard limit)

**Category:** Resource limits
**Severity:** Low
**Discovered:** 2026-03-25 Category C cycle 2 tests

**Description:**
FD exhaustion test confirmed: `EMFILE` error triggers at exactly 4078 open files (4096 hard limit minus FDs already open: stdin/stdout/stderr + a few system FDs). Container survived without restart.

**Assessment:** This is correct behavior — EMFILE kills only the script that exhausted FDs, not the gateway. The nofile limit (1024 soft, 4096 hard) is enforced and appropriate.

**No action needed.**

---

## [INFO] ISSUE-16: CPU throttling at 97.6% during 4-thread saturation (correct behavior)

**Category:** Resource limits
**Severity:** Informational
**Discovered:** 2026-03-25 Category C cycle 2 tests

**Description:**
Running 4 CPU-intensive worker threads for 8 seconds triggered throttling on 81 of 83 new cgroup periods (97.6%). The 1.0 CPU cap was enforced. Host load average was unaffected.

**Assessment:** This is correct behavior. The `cpus: "1.0"` limit works as expected.

**Note:** The container is configured to see ALL CPUs (10 visible via `os.cpus()`), but
the cgroup `cpu.max = 100000 100000` enforces a 1 CPU equivalent over 100ms periods.
This is Docker's normal behavior — visibility vs. allocation are separate concepts.

**No action needed.**

---

## [FIXED→REVERTED] ISSUE-10 partial fix causes BUG-12: ulimit -v breaks gateway API calls

**Category:** Regression from ISSUE-10 partial fix
**Severity:** Critical (breaks agent functionality)
**Discovered:** 2026-03-25 Category D cycle 2 session

**Description:**
The `ulimit -v 16GB` added to `entrypoint.sh` during ISSUE-10 cycle 2 fix caused the OpenClaw gateway (version 2026.3.23-2) to fail ALL Anthropic API calls with "LLM request failed: network connection error."

**Root cause:**
OpenClaw 2026.3.23+ maps 11–12GB virtual address space at startup (WASM, V8, connection pools). With ulimit -v = 16GB, only ~5GB headroom remains. When active TLS sessions + connection pools push virtual size higher, the kernel refuses new memory mappings → undici/fetch connections fail at the TCP/TLS level.

**Evidence:**
- Gateway VmPeak = 11,212,532 KB (~11.2GB) at idle
- `ulimit -v` = 16,384 MB = 16GB hard cap
- Direct curl to api.anthropic.com worked; Node.js `fetch()` worked — only gateway's connection pooling hit the limit
- Removing ulimit -v immediately fixed all API calls

**Fix:**
Removed `ulimit -v` from entrypoint.sh (commit `b88149a`). Documented as ISSUE-18 (exec-tool children CoW bypass cap needs gateway-level support).

**ISSUE-10 status:**
- exec-tool children still have uncapped virtual memory (ISSUE-18 pending)
- Gateway itself is bounded by cgroup memory.max = 512MB (RSS/physical cap)
- Virtual memory bypass is a residual risk but lower priority than gateway functionality

---

## [OPEN] ISSUE-18: exec-tool children can bypass CoW virtual-memory cap

**Category:** Resource limits — security regression
**Severity:** Medium
**Discovered:** 2026-03-25 Category D cycle 2 (BUG-12 investigation)

**Description:**
The ulimit -v approach for capping virtual memory (ISSUE-10 partial fix) was reverted because it also applies to the gateway process and breaks TLS connections. Without it, agent exec tool children can use `Buffer.alloc()` zero-fill to claim unlimited virtual address space.

**Current status:** exec-tool children have no virtual memory cap.

**Mitigations in place:**
- cgroup `memory.max = 512MB + 512MB swap = 1GB` physical/RSS cap ✅
- `NODE_OPTIONS=--max-old-space-size=384` caps V8 heap ✅  
- OOM killer kills only the offending process ✅

**Correct fix (requires gateway support):**
The OpenClaw gateway should apply `ulimit -v` only when forking exec-tool child processes (after the gateway itself is fully initialized), not globally. Needs upstream support.

**Workaround for enterprise:**
1. Use a wrapper script that applies ulimit -v before exec'ing agent processes
2. Or use Linux cgroups v2 with per-process memory limits on exec-tool children

---

## [OPEN] ISSUE-17: Workspace volume has no disk quota (ISSUE-9 follow-up)

**Category:** Resource limits — disk
**Severity:** Medium
**Discovered:** 2026-03-24 Category C tests (original), confirmed 2026-03-25 Category C cycle 2

**Description:**
The `/home/node/.openclaw` workspace volume (overlay2 on Docker Desktop/macOS) has no per-container disk quota. The agent can write files to fill the host disk up to available space (~187GB in current environment).

**Current state:**
- `/tmp` is tmpfs-capped at 256MB ✅
- Workspace volume = uncapped

**Mitigations:**
- On Linux Docker Engine: `storage_opt: size=10g` per container (requires quota-enabled filesystem)
- On macOS Docker Desktop: limited options — Docker VM disk size is a soft cap (VM image max)
- Application-level: agent instructions in AGENTS.md could discourage large writes

**Recommendation for risk-management deployments:**
- Run on Linux Docker Engine with `overlay2` + `projectquota` enabled
- Set `storage_opt: size: 10g` in `docker-compose.yml` under the service
- Document this limitation in SECURITY.md


## [FIXED] BUG-13: socat restart loop broken by `set -e` — SIGTERM exits the while loop

**Category:** Resilience — socat restart loop
**Severity:** High
**Discovered:** 2026-03-25 Category E cycle 2

**Description:**
`entrypoint.sh` uses `set -eu` at the top. The socat restart loop runs in a background subshell:
```sh
(
  while true; do
    socat TCP-LISTEN:18789,...
    sleep 1
  done
) &
```
When `pkill -f socat` (or socat dying from any cause) results in socat exiting with a non-zero
exit code (e.g. 143 = SIGTERM, 137 = SIGKILL), `set -e` causes the subshell to abort immediately
instead of continuing the while loop. The background subshell disappears; socat is never restarted.
Host loses all connectivity to the container gateway with no recovery path except `docker compose restart`.

This bug was in the code since the socat restart loop was added (commit c32015c), but was never
actually confirmed working — the cycle 1 Category E test only ran `docker compose restart` to
recover, which masks the issue.

**Fix (commit pending):**
Added `set +e` and `|| true` inside the socat subshell:
```sh
(
  set +e
  while true; do
    socat TCP-LISTEN:18789,...  || true
    echo "▶ socat exited — restarting in 1s..."
    sleep 1
  done
) &
```

**Verification:**
- `pkill -f socat` → socat PID changes from 142 to 203 within 2s ✅
- CLI agent call after kill → `SOCAT_RESTART_LOOP_FIXED` ✅
- Container: 0 restarts, healthy ✅

---

## [INFO] ISSUE-19: Gateway restart window is ~4s — rapid kill+reconnect (1s gap) falls back to embedded

**Category:** Resilience — reconnect timing
**Severity:** Low / expected behavior
**Discovered:** 2026-03-25 Category E cycle 2

**Description:**
Gateway restart loop takes ~4-5s to bring a new gateway process to a ready state. If a CLI
call is made within 1s of killing the gateway, the CLI sees "gateway closed (1006)" and falls
back to the embedded model for that call. Any call made 4s+ after kill connects to the restarted
gateway correctly.

**Status:** Expected behavior. Not a bug. The restart window is inherent to Node.js startup time.
Documented for operator awareness.

**Recommendation:**
If resilience to rapid kill is required, consider health-check-based routing or a supervisor
that delays CLI calls until gateway ready.


---

## [INFO] ISSUE-20: fork bomb recovery faster in cycle 3 — docker exec stays accessible after 5s

**Category:** Resilience — fork bomb containment
**Severity:** Low / expected behavior
**Discovered:** 2026-03-25 Category B cycle 3

**Description:**
In cycle 3, fork bomb was run inside container via `timeout 10s` wrapper. After the 10s
timeout, `docker exec` returned successfully after 5s wait (compared to requiring `docker
compose restart` in previous cycles). This suggests tini's zombie reaping clears blocked
processes faster when the bomb is timeout-bounded. Container remained accessible, 0 restarts.

**Notes:**
- pids_limit=512 and nproc=256 both held — no process escaped the container
- Container status: running, restarts: 0
- Recovery: passive (no restart needed this cycle)

---

## [INFO] ISSUE-21: /proc/1/environ consistently exposes ANTHROPIC_API_KEY (cycle 3 confirmation)

**Category:** Security — environment variable exposure
**Severity:** Medium (inherent to Docker env var model)
**Discovered:** Cycle 1 (ISSUE-2), reconfirmed cycles 2 and 3

**Description:**
`/proc/1/environ` is readable by the `node` user (uid=1000) because PID 1 runs as `node`.
Contains ANTHROPIC_API_KEY in plaintext. Consistent across all three test cycles.

**Mitigation options documented in SECURITY.md:**
1. Docker secrets (replaces env vars with file-mounted secrets)
2. External secrets manager (Vault, AWS SSM) with runtime injection
3. Accept as inherent risk if container is trusted (single-user deployment)

**Status:** INFO — inherent behavior, documented, awaiting upstream Docker secrets integration.

---

## [INFO] ISSUE-22: /proc/net readable — container can enumerate its own network topology

**Category:** Security — /proc/net visibility
**Severity:** Low / expected
**Discovered:** 2026-03-25 Category B cycle 4

**Description:**
`/proc/net/tcp` and `/proc/net/fib_trie` are readable from inside the container. A container process (or agent via exec tool) can:
- Enumerate open listening ports (tcp entries): ports 18788, 18789, 3000, etc.
- See the container's routing table via fib_trie

**What's isolated:**
- The container only sees its own network namespace — no host TCP connections or host routing table
- PID namespace isolation confirmed: container sees only its own PIDs (1, 7, 161, 162, 163, 171, 500)
- `nsenter` namespace escape attempt blocked: `Operation not permitted`

**Risk:** Low — only exposes the container's own network state, not the host's. An agent with exec access can discover internal ports (which are visible via process listing anyway).

**Recommendation:** No action required. This is standard Linux container behavior. Document for awareness.

**Status:** INFO — expected behavior, no new action needed.

---

## [INFO] ISSUE-23: Agent can read ANTHROPIC_API_KEY via exec tool (cycle 4 confirmation)

**Category:** Security — API key exposure via exec tool
**Severity:** Medium (consistent with ISSUE-2 / ISSUE-21 — this is cycle 4 reconfirmation)
**Discovered:** Confirmed cycles 1–4 consistently

**Description:**
`cat /proc/1/environ | tr '\0' '\n' | grep ANTHROPIC` executed via the agent's exec tool returns the full API key. The agent reported back `ANTHROPIC_API_KEY=sk-ant-oat01` as expected.

This confirms that any prompt injection or compromised agent session can exfiltrate the API key through the exec tool path.

**Consolidated recommendation:**
1. Use Docker secrets instead of env vars (removes key from /proc/1/environ)
2. Add output filtering in the gateway to redact API key patterns in exec output (upstream feature)
3. Scope API keys to read-only / restricted permissions where provider allows

**Status:** INFO — consistent finding across all 4 cycles, documented. Medium severity, inherent to env var model.

---

## [FIXED] ISSUE-24: Two conflicting clawbox instances can run on same host (port conflict) ✅ Fixed 2026-03-27

**Category:** Infrastructure / Multi-instance
**Severity:** Medium
**Discovered:** 2026-03-25 Category F test

**Description:**
When a second clawbox-derived project (e.g. `openclaw-docker`) is already running and bound to
port 18790, starting the `clawbox` project causes a port allocation failure:
`Bind for 127.0.0.1:18790 failed: port is already allocated`
The new container starts but without the gateway port mapping, silently routing CLI connections
to the wrong container. The user has no indication which container the CLI is talking to.

**Fix (2026-03-27):**
1. **Configurable gateway port:** `docker-compose.yml` now uses `${GATEWAY_PORT:-18790}` for the
   host port mapping. Set `GATEWAY_PORT=18791` to run a second instance on a different port.
2. **Port conflict detection in `setup.sh`:** Pre-flight check detects conflicts before
   starting. Prints clear error with instructions to use a different port.
3. **CLI GATEWAY_PORT support:** All `clawbox` CLI commands (start, stop, status, run, chat, task,
   logs, upgrade, clean) now read `GATEWAY_PORT` and pass it to docker compose + connect to the
   correct gateway URL. Help text documents the env var.
4. **Clear conflict message in `clawbox start`:** When the gateway port is in use, shows how to
   run on a different port instead of a bare error.

**Usage for multiple instances:**
```bash
# Instance 1 (default port 18790)
clawbox start
clawbox run "task A"

# Instance 2 on port 18791
GATEWAY_PORT=18791 clawbox start
GATEWAY_PORT=18791 clawbox run "task B"
```

**Status:** FIXED — configurable port + conflict detection in place.

---

## [FIXED] ISSUE-25: Container exits during long agent runs (gateway OOM/crash)

**Category:** Resilience — container lifetime under load
**Severity:** Medium
**Discovered:** 2026-03-25 Category F test

**Description:**
During a long Category F test run (~10 minutes of continuous agent activity including npm installs,
file writes, and server starts), the `openclaw-work` container exited unexpectedly. The CLI then
fell back to embedded (host agent). No error message was shown to the user — they only noticed
when the response came from Arclo (host) instead of the container agent.

**Potential causes:**
- Gateway OOM (npm install during agent run consumed memory near 512MB cap)
- Gateway crash from exec tool workload during long session
- The last log line was `[tools] read failed: EISDIR` suggesting a tool error cascaded

**Impact:**
- Silent fallback to embedded agent: user gets responses but from the wrong agent
- Work done inside the container (files written, servers started) is lost if user doesn't notice
- No retry or reconnect logic in CLI for long-running sessions

**Recommendations:**
- Add visible warning when CLI falls back to embedded: "WARNING: container gateway unreachable — responses from local agent"
- Increase memory limit for long-running agent sessions (or use 1GB RAM cap)
- Consider gateway health monitoring that alerts the user via message if container dies mid-session

**Status:** OPEN — needs upstream CLI improvement + potential memory limit increase for heavy workloads

---

## [INFO] ISSUE-26: Agent confused by dual workspace paths (/home/node/workspace vs .openclaw/workspace)

**Category:** UX / Agent orientation
**Severity:** Low
**Discovered:** 2026-03-25 Category F test

**Description:**
The container has two distinct "workspace" directories:
1. `/home/node/.openclaw/workspace/` — agent's default working directory (AGENTS.md, SOUL.md, etc.)
2. `/home/node/workspace/` — project workspace for user code and files

When asked about file paths, the agent consistently defaults to the `.openclaw/workspace` context
and reports that paths under `/home/node/workspace/` "don't exist" — even when they do.
The agent must use explicit absolute paths to access project files.

**Impact:**
- Category F took 3 retries before agent correctly located local docs
- Agent first reported docs missing, then built app in wrong directory
- Without explicit `workdir` parameter in exec calls, commands run in .openclaw/workspace

**Recommendations:**
- Update `seed/AGENTS.md` to document both workspace paths and their purposes
- Add a note: "Project files live in /home/node/workspace/ — use absolute paths"
- Consider symlinking /home/node/workspace/ into /home/node/.openclaw/workspace/projects/

**Status:** INFO — documented, seed/AGENTS.md should be updated

---

## [FIXED] ISSUE-27: docker compose up -d may start container without port bindings after port conflict ✅ Fixed 2026-03-27

**Category:** Infrastructure / Docker networking
**Severity:** Medium
**Discovered:** 2026-03-25 Category A cycle 5 (during F→A transition)

**Description:**
When `docker compose up -d` is run while another container (e.g., openclaw-work) still holds the
required ports (18790, 3000, 3001), Docker starts clawbox-work but without any port mappings.
The container becomes healthy (gateway starts fine), but `docker port clawbox-work` shows nothing
and CLI connections fail with 1006 abnormal closure.

This is distinct from a hard "port already allocated" error — Docker silently maps no ports.

**Evidence:**
- `docker compose down -v && docker compose up -d` with openclaw-work running → container started,
  gateway healthy, but `docker port clawbox-work` returned empty, 18790 unreachable
- Stopping openclaw-work and running `docker compose up -d --force-recreate` → ports bound correctly
- Pattern also seen in Category F when openclaw-work took over 18790 while clawbox-work was down

**Impact:**
- CLI falls back to embedded host agent (confusing for operators)
- Container appears healthy but is inaccessible from host
- Requires `docker compose up -d --force-recreate` to fix

**Reproduction:**
1. Start openclaw-work (holds ports 18790, 3000, 3001)
2. Run `docker compose down -v && docker compose up -d` in clawbox/
3. Observe: clawbox-work starts but has no port mappings

**Fix/Recommendation:**
- Add port conflict check in setup.sh and/or Makefile start target
- Warn user if any of 18790/3000/3001 are already in use before starting
- Document: `docker compose up -d --force-recreate` as the fix command

**Status:** FIXED — `cmd_start` in clawbox CLI checks ports 18790 and 3000 before starting, warns and exits if occupied. `assert_container_running` also verifies port 18790 is reachable before allowing run/chat/task commands.

---

## [FIXED] ISSUE-28: docker cp preserves macOS UID (501) not container UID (1000); files created with mode 600 are unreadable by container agent ✅ Fixed 2026-03-27

**Category:** Infrastructure / Docker file operations
**Severity:** Medium (Category F specific — doc seeding)
**Discovered:** 2026-03-26 Category F cycle 2

**Description:**
When files are copied from the macOS host into the container using `docker cp`, the files inherit
the macOS user's UID (501) as owner rather than the container's `node` user (UID 1000). Combined
with a default umask that creates files with mode 600, files are readable only by UID 501 — not
by the container's `node` user.

Symptoms:
- Agent reports "Permission denied" when trying to read seeded doc files
- `cat file` inside container returns "Permission denied" even for the agent
- `docker exec --user root clawbox-work chmod ...` is blocked by container security policy
- `chown` as root succeeds but `chmod` does not (sticky bit on parent dir)

**Evidence:**
```
-rw-------  1 501  dialout  63548 Mar 26 06:08 address-book-tutorial.md
# → node user (uid=1000) cannot read this
```

**Workaround used in test:**
- `docker exec --user root ... chown -R node:node /home/node/workspace/docs/`
- Files created as mode 600 (node-owned) are readable by the node process ✅

**Proper Fix:**
Option A: After `docker cp`, run `docker exec --user root ... chown -R node:node <dest>`
Option B: Create files as a tar archive and use `docker exec cat | tar x` (preserves no ownership)
Option C: Write files to the container via the agent's `write` tool (already correct user)

**Category F Impact:**
- Cycle 1: same issue caused agent to build from training data (docs unreadable)
- Cycle 2: same issue, agent used training data, then docs made readable via post-hoc chown
  → Agent confirmed docs readable and relevant after fix
- Workaround: `docker exec --user root clawbox-work chown -R node:node /path/`

**Recommendations:**
- Update Category F test procedure to chown after docker cp
- Consider creating a `scripts/seed-docs.sh` helper that does docker cp + chown in one step
- Document in README: "When manually copying files into the container, run chown after cp"

**Status:** FIXED — `clawbox cp <src> <dest>` command wraps `docker cp` + runs `chown -R node:node` automatically. README documents the `clawbox cp` command as the correct way to copy files into the container.

---

## [INFO] ISSUE-29: Fork bomb requires docker compose restart (cycle 6 confirmation)

**Discovered:** Category B, cycle 6 (2026-03-26 ~2:24 AM MDT)
**Severity:** INFO (expected behavior)

**Observed:** Unbounded fork bomb via `timeout 10s sh -c ':(){ :|:&};:'` caused container to
become wedged — `docker exec` returned "exec /bin/echo: resource temporarily unavailable" after
the bomb completed. Required `docker compose restart` to clear zombie processes.

**Note:** Cycle 3–5 showed improvement when the bomb was run with a bounded timeout (10s) and
accessed after a 5s wait. Cycle 6 the timing didn't allow recovery without restart. This is
non-deterministic: depends on how quickly tini reaps zombies. Not a regression.

**Status:** INFO — expected behavior. pids_limit=512 contains the bomb. Recovery via restart is the documented procedure.

---

## [INFO] ISSUE-30: Container OOM during long-running agent builds (Category F cycle 3)

**Discovered:** Category F, cycle 3 (2026-03-26 ~6:49 AM MDT)
**Severity:** INFO (ISSUE-25 reconfirmation — consistent behavior)

**Observed:** When the agent was asked to do the full F task (read docs + build full React+Prisma
app in one message), the container OOM'd and exited mid-run. The CLI fell back to embedded agent
with no warning. This is the same as ISSUE-25 from cycle 1.

**Root cause:** Long agent turns with npm installs and compilation are memory-intensive. The
512MB RAM + 512MB swap limit (~1GB total) gets exhausted during a large combined task.

**Workaround used in cycle 3:** Split the task into two separate agent calls:
1. Build backend (Prisma setup + Express API)
2. Build frontend (Vite + React Router)
→ Both tasks completed successfully with this approach.

**Recommendation:** For long/complex builds in Category F, split into multiple focused agent
calls to avoid OOM during combined npm install + compile runs.

**Status:** INFO — inherent resource constraint. Workaround documented.


---

## [INFO] ISSUE-31: Fork bomb recovery without restart (cycle 7 positive finding)

**Discovered:** Category B, cycle 7 (2026-03-26 ~9:11 AM MDT)
**Severity:** INFO (positive)

**Observed:** Fork bomb (timeout 10s) ran and the container recovered cleanly without needing
`docker compose restart`. Container remained alive (`CONTAINER_ALIVE`) immediately after fork bomb
completed. This is the 3rd cycle (cycles 3, 5, 7) where no restart was needed.

**Pattern:** Fork bomb recovery is non-deterministic. Whether restart is needed depends on
tini zombie reaping timing vs the 10s post-bomb wait. Cycles 1, 2, 4, 6 needed restart;
cycles 3, 5, 7 did not. The alternating pattern suggests it's timing-dependent rather than
a fundamental change. All cycles: pids_limit=512 contained the bomb. Zero escapes.

**Status:** INFO — no action needed. pids containment working perfectly.
