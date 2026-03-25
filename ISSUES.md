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
README.md contains placeholder `https://github.com/your-org/openclaw-docker.git`. Repo not yet published.

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

## [OPEN] ISSUE-10: Memory limit allows virtual over-allocation (zero-page CoW bypass)

**Category:** Resource limits
**Severity:** Medium
**Discovered:** 2026-03-24 Category C resource limit tests

**Description:**
Docker's 512MB memory limit (`memory: 512m`) only triggers the OOM killer when physical pages are actually faulted in (dirty/written). A Node.js script using `Buffer.alloc()` with zero-fill allocated 566GB of virtual address space before the timeout killed it — no OOM triggered because zero pages use Linux's CoW optimization.

**Test results:**
- `Buffer.alloc(10MB)` × N (zero-filled) → 566GB virtual allocated, no OOM trigger, exit code 137 from timeout
- `Buffer.alloc(10MB)` + dirty write (1 byte per page) → OOM kill at ~750MB (512MB RAM + 512MB swap), correct behavior
- The OOM killer kills only the offending process, not the container

**Impact:** 
- Virtual address exhaustion can make the runtime unstable before OOM triggers
- A malicious Node.js process could allocate huge virtual address space without triggering limits
- The OOM killer works correctly when pages are actually written

**Mitigations in place:**
- Node.js has a default `--max-old-space-size` of ~4GB (not 566GB) in practice due to V8 heap
- Container survived both tests with 0 restarts — OOM killed only the process

**Potential fix:** Add `--max-old-space-size=384` to NODE_OPTIONS in the container environment.
This caps Node.js V8 heap at 384MB regardless of virtual overcommit behavior.

---

## [FIXED] ISSUE-11: socat not in restart loop — container becomes a brick if socat dies

**Category:** Resilience
**Severity:** Medium
**Discovered:** 2026-03-24 Category E recovery and resilience tests

**Description:**
socat was started with a bare `socat ... &` — no restart loop. If socat was killed (e.g., by a process flood consuming the PID namespace, an OOM event, or a direct `pkill socat`), the container kept running but ALL CLI connections from the host were permanently severed. The gateway kept running but was unreachable. Only `docker compose restart` could recover.

**Test result:**
- `docker exec openclaw-work pkill -f socat` → container stayed up, CLI returned "gateway closed (1006 abnormal closure)"
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
