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

## [OPEN] ISSUE-8: No read-only root filesystem

**Category:** Security — filesystem hardening
**Severity:** Low-Medium
**Discovered:** Design review

**Description:**
`ReadonlyRootfs: false` — container filesystem is writable. A read-only rootfs with `tmpfs` for `/tmp` and writable overlay for npm cache would reduce blast radius.

**Challenge:** Node.js / npm require several writable paths. Needs careful `tmpfs` mapping.

**Action:** Test with `read_only: true` + appropriate tmpfs mounts.
