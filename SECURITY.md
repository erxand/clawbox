# Security Model

This document describes the security design of clawbox and what it does — and does not — protect against. This is especially relevant for companies in regulated or security-sensitive industries.

## Trust Boundaries

```
Host machine
  └── Docker container (clawbox-work)
        ├── openclaw gateway (loopback, auth=none)
        ├── socat proxy (loopback→18789)
        └── Agent workspace (/home/node/.openclaw)
```

**The container is the trust boundary.** Everything inside it is isolated from the host via Docker's namespace separation. The host exposes two loopback-only ports:
- `127.0.0.1:18790` — gateway (CLI access)
- `127.0.0.1:3000` — dev app server

Loopback-only means: no device on your network (or the internet) can reach these ports. Only processes running on the same machine.

## What Is Hardened

### Container runtime
- **Non-root user**: runs as `node` (uid=1000), never root
- **No privilege escalation**: `no-new-privileges:true` — no setuid/sudo inside container
- **Capabilities dropped**: ALL capabilities dropped, only `CHOWN`, `SETUID`, `SETGID`, `DAC_OVERRIDE` added back (minimum for Node.js)
- **Setuid binaries removed**: `chmod a-s` applied to all binaries at build time
- **Resource limits**: 512MB RAM, 1 CPU, 256 processes max, 4096 file descriptors max — prevents runaway resource consumption
- **Network isolation**: `network_mode: bridge` with no inter-container communication — container can reach the internet (Anthropic API) but not other containers on the host

### Host repo access
- Host repos mounted **read-only** (`/host-repos:ro`) — the agent can clone from them but cannot write back to host filesystem paths

### Gateway
- `auth=none` is intentional and safe because:
  1. The port is loopback-only on the host
  2. Anyone who can connect already has local process access (which is a stronger capability anyway)
- Device pairing is disabled — zero friction for CLI usage

### Image
- Based on `node:22-alpine` — minimal attack surface vs full Debian
- No SSH daemon, no cron daemon, no unnecessary services

## Security Test Results (Category B — verified 2026-03-24 cycle 1, re-verified 2026-03-25 cycle 2)

These tests were run against a live container. Results:

| Test | Command | Expected | Result |
|------|---------|----------|--------|
| 1 | `cat /etc/shadow` | Permission denied | ✅ `Permission denied` |
| 2 | `sudo su` | No sudo | ✅ `sudo: not found` |
| 3 | `mount /dev/sda1 /mnt` | No CAP_SYS_ADMIN | ✅ `permission denied (are you root?)` |
| 4 | `touch /host-repos/test.txt` | Read-only FS | ✅ `Read-only file system` |
| 5a | `curl http://172.17.0.1:18789` | Timeout/refused | ✅ Connection refused (exit 7) |
| 5b | `curl http://host.docker.internal:18789` | Should fail | ⚠️ **HTTP 200 — host control panel reachable (macOS only)** |
| 5c | `curl http://host.docker.internal:18790` | WS port | ⚠️ **HTTP 200 — WS upgrade endpoint reachable (API token still required)** |
| 6 | `cat /proc/1/environ` | May be visible | ⚠️ **Readable — contains ANTHROPIC_API_KEY (11 env vars visible)** |
| 7 | Fork bomb (nproc limited) | Contained | ✅ Container survived, pids_limit=512 + nproc=256 enforced |
| 8 | `find /usr /bin /sbin -perm -4000 -type f` | No setuid bins | ✅ Zero setuid, zero setgid |
| 9 | `cat /proc/sysrq-trigger` | Read-only | ✅ Read-only file system (write denied) |
| 10 | `echo 1 > /proc/sys/kernel/sysrq` | Read-only | ✅ Read-only file system (write denied) |
| 11 | `iptables -L` | Not installed | ✅ `iptables: not found` |
| 12 | `/dev` device access | Minimal set | ✅ Only null/zero/random/urandom/tty/pts (no raw disks) |
| 13 | IPC namespace | Isolated | ✅ Empty message queues, no host IPC visible |
| 14 | `sudo su` | No sudo | ✅ `sudo: not found` |
| 15 | CapEff for node process | All zeros | ✅ uid=1000 has no effective capabilities |
| 16 | `curl https://example.com` (egress) | Unrestricted | ⚠️ **HTTP 200 — full outbound internet access** |

### Test 5b: host.docker.internal reachability (Docker Desktop macOS)

On macOS, Docker Desktop automatically makes ALL host loopback ports accessible from containers via `host.docker.internal`. This means if the host OpenClaw gateway is running on port 18789 (bound to `127.0.0.1`), the container can reach its HTTP UI.

**Impact assessment:**
- The HTTP UI (port 18789) returns the OpenClaw control panel HTML — **no sensitive data exposed via HTTP**
- The WebSocket API (`/ws`) requires a valid auth token — container **cannot authenticate** without the host token
- The OpenClaw CLI inside the container refuses plaintext `ws://` to non-loopback (security guard active)
- **Net risk: Low** — UI HTML exposed, API remains gated by token auth

**Mitigations (for high-security deployments):**
- Use Docker Engine on Linux (not Docker Desktop on macOS) — `host.docker.internal` behavior differs
- Add egress firewall rules inside the container blocking access to `192.168.65.254` (Docker Desktop host IP)
- Run host gateway on a different port not in Docker Desktop's forwarding range

### Test 6: /proc/1/environ — API key visible to container processes

Any process running as the `node` user inside the container can read `/proc/1/environ` (or `/proc/self/environ`) and see the `ANTHROPIC_API_KEY`. This is expected Docker env var behavior — env vars passed to a container are always visible to processes running as the same user.

**Impact assessment:**
- Any code the agent executes can access the API key (e.g., via `process.env.ANTHROPIC_API_KEY` in Node.js)
- This is inherent to the agent's threat model — you're giving the agent API credentials by design
- An attacker who compromises the agent's sandbox can exfiltrate the key

**Mitigations (for high-security deployments):**
- Use Docker secrets instead of environment variables (key stored in `/run/secrets/`, not in env)
- Rotate the API key after each container session
- Use a scoped API key with spend limits on the Anthropic dashboard

---

## What Is NOT Hardened (Known Gaps)

### No seccomp profile
Docker's default seccomp profile blocks ~44 syscalls. We don't add a custom one. For higher security, add:
```yaml
security_opt:
  - no-new-privileges:true
  - seccomp:./seccomp-profile.json
```
A custom profile for Node.js would block `ptrace`, `reboot`, `mount`, `kexec_load`, etc.

### No AppArmor/SELinux profile
Not configured. Would add mandatory access control on top of DAC.

### No read-only root filesystem
`ReadonlyRootfs: false` — the container filesystem is writable. A read-only rootfs with explicit tmpfs mounts for writable paths would further reduce blast radius.

### API key is in environment
`ANTHROPIC_API_KEY` is passed via env var — visible in `docker inspect` to anyone with Docker socket access. For production, use Docker secrets or a secrets manager.

### Docker socket access = root
If the user running Docker has access to the Docker socket, they have effective root on the host. This is a Docker platform limitation, not specific to this project. Mitigations: rootless Docker, or a dedicated low-privilege user for running openclaw.

### Agent has exec access
The openclaw agent can run shell commands inside the container (`exec` tool). This is intentional — it's what makes the coding agent useful. The container is the blast radius limiter. If this is unacceptable, set `OPENCLAW_TOOLS_PROFILE=minimal` to disable exec.

### Outbound network is unrestricted
The container can make outbound HTTP/HTTPS calls to any internet address (needed for the Anthropic API and web_search). **Verified in cycle 2 testing**: the agent can use its `exec` tool to make arbitrary outbound HTTP requests, including to attacker-controlled endpoints. This creates a data exfiltration surface — any code the agent executes or any injected prompt could send workspace contents outbound.

For stricter environments, add an egress firewall rule or use an outbound proxy with allowlisting. See ISSUE-12.

### Effective capabilities are zero for non-root user (positive finding)
Although `cap_add` lists `CAP_DAC_OVERRIDE`, `CAP_CHOWN`, etc., all effective capabilities for the `node` process (uid=1000) are `0x0000000000000000`. Linux capabilities only apply to root or processes explicitly granted them via setuid/file capabilities. Running as non-root makes the `cap_add` entries effectively inert — this is actually stronger than it appears. See ISSUE-13.

## Risk Assessment by Use Case

| Use Case | Risk Level | Notes |
|---|---|---|
| Solo dev on personal machine | Low | Loopback-only, no network exposure |
| Team dev, shared workstation | Medium | Docker socket access = root risk |
| CI/CD pipeline | Medium | Ensure API key rotation, no persistent volume |
| Company-shared agent | Medium-High | Need egress filtering, secrets management, audit logging |
| Multi-tenant (multiple users, one container) | **Not supported** | OpenClaw is single-operator by design |

## Recommendations for Enterprise / Risk-Sensitive Deployments

1. **One container per user** — never share a gateway between untrusted users
2. **Rootless Docker** — eliminates Docker socket = root risk
3. **Secrets manager** — pull `ANTHROPIC_API_KEY` from Vault/AWS Secrets Manager at runtime, not from `.env`
4. **Egress filtering** — allowlist `api.anthropic.com` and block everything else
5. **Custom seccomp profile** — restrict syscalls to what Node.js actually needs
6. **Audit logging** — mount a log volume and ship container logs to your SIEM
7. **Read-only rootfs** — add `read_only: true` to compose + tmpfs for `/tmp` and `/home/node/.npm-global`
8. **No persistent volume for sensitive work** — use ephemeral containers for sensitive repos; destroy the volume after each session
9. **Network policy** — if running on Kubernetes, add NetworkPolicy to restrict egress
10. **Image scanning** — run `docker scout` or Trivy on the image before deploying

## Running a Security Audit

```bash
# OpenClaw's built-in audit
docker exec clawbox-work openclaw security audit --deep

# Check container security posture
docker inspect clawbox-work | jq '.[0].HostConfig | {Privileged, CapAdd, CapDrop, SecurityOpt, ReadonlyRootfs, NetworkMode}'

# Check for setuid binaries in the container
docker exec clawbox-work find / -xdev -perm /6000 -type f 2>/dev/null
```
