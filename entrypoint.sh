#!/bin/sh
set -eu

# Clear any stale NODE_OPTIONS that reference removed proxy-bootstrap.js
export NODE_OPTIONS=""

OPENCLAW_DIR="$HOME/.openclaw"
WORKSPACE_DIR="$OPENCLAW_DIR/workspace"

# ── First-run: initialize config if missing ──────────────────────────
if [ ! -f "$OPENCLAW_DIR/openclaw.json" ]; then
  echo "▶ First run detected — initializing OpenClaw config..."
  openclaw onboard \
    --non-interactive \
    --accept-risk \
    --mode local \
    --auth-choice anthropic-api-key \
    --anthropic-api-key "${ANTHROPIC_API_KEY:-placeholder}" \
    --gateway-auth token \
    --gateway-token "openclaw-docker" \
    --gateway-bind loopback \
    --no-install-daemon \
    --skip-channels \
    --skip-skills \
    --skip-search \
    --skip-ui \
    --skip-health \
    --workspace "$WORKSPACE_DIR"

  # Patch config: switch to auth=none so the file matches how we start
  # the gateway. Without this, openclaw's reload watcher sees a mismatch
  # between file (token auth) and runtime (none), triggers a full restart,
  # and kills the container on the first `openclaw config set` call.
  echo "▶ Patching config: auth=none, default model..."
  openclaw config set gateway.auth.mode none 2>/dev/null || true
  openclaw config set gateway.auth.token "" 2>/dev/null || true
  # Set a sensible default model (haiku is much cheaper than opus)
  DEFAULT_MODEL="${OPENCLAW_DEFAULT_MODEL:-anthropic/claude-haiku-4-5}"
  openclaw config set agents.defaults.model.primary "$DEFAULT_MODEL" 2>/dev/null || true
  # Set tools profile. 'coding' gives read/write/exec/web/memory tools — the
  # practical minimum for a useful agent. 'minimal' only grants session_status.
  # Note: coding profile logs benign "[tools] unknown entries" warnings for
  # apply_patch and image_generate (unavailable in this runtime) — not errors.
  TOOLS_PROFILE="${OPENCLAW_TOOLS_PROFILE:-coding}"
  openclaw config set tools.profile "$TOOLS_PROFILE" 2>/dev/null || true

  # ── Deny list: tools the agent should never have access to ──────────
  # web_search and web_fetch allow arbitrary internet browsing — disable
  # them by default. Set OPENCLAW_ALLOW_WEB=1 in .env to re-enable.
  # browser is also denied (no browser runtime in the container anyway).
  ALLOW_WEB="${OPENCLAW_ALLOW_WEB:-0}"
  if [ "$ALLOW_WEB" != "1" ]; then
    echo "▶ Disabling web browsing tools (OPENCLAW_ALLOW_WEB=$ALLOW_WEB)..."
    openclaw config set tools.deny '["web_search","web_fetch","browser"]' || true
  fi
fi

# ── Seed workspace files on first run ────────────────────────────────
# Use a sentinel file to track whether seeding has happened.
# We can't rely on SOUL.md absence because openclaw onboard creates one.
SEED_SENTINEL="$OPENCLAW_DIR/.seed-applied"
if [ ! -f "$SEED_SENTINEL" ] && [ -d /home/node/seed ]; then
  echo "▶ Seeding workspace with custom files..."
  mkdir -p "$WORKSPACE_DIR"
  # Copy all seed files — including BOOTSTRAP.md which replaces the one
  # openclaw onboard creates (the default one prompts for name/personality,
  # but our seed files already define identity so we override it)
  cp /home/node/seed/*.md "$WORKSPACE_DIR/"
  touch "$SEED_SENTINEL"
  cd "$WORKSPACE_DIR"
  # Ensure git user identity is set for commits
  git config --global user.email "openclaw-docker@localhost" 2>/dev/null || true
  git config --global user.name "OpenClaw Docker" 2>/dev/null || true
  if [ -d .git ]; then
    git add -A
    git commit -q -m "Apply custom seed files" 2>/dev/null || true
  else
    git init -q
    git add -A
    git commit -q -m "Initial workspace seed" 2>/dev/null || true
  fi
  cd "$HOME"
fi

# ── Start socat proxy: 0.0.0.0:18789 → 127.0.0.1:18788 ─────────────
# The gateway binds to loopback (auth=none) on port 18788.
# socat exposes it on all interfaces at port 18789 so Docker's port
# mapping (host 127.0.0.1:18790 → container :18789) can reach it.
# From the CLI's perspective the URL is ws://localhost:18790 — loopback —
# so OpenClaw's CLI skips device identity/pairing automatically.
# socat is wrapped in a restart loop so that if it dies (e.g. SIGKILL
# during a process flood) it automatically recovers instead of making
# the container unreachable from the host.
echo "▶ Starting socat proxy (0.0.0.0:18789 → 127.0.0.1:18788)..."
(
  # Disable set -e inside this subshell so that socat dying with a
  # non-zero exit code (e.g. SIGTERM → exit 143) doesn't abort the loop.
  set +e
  while true; do
    socat TCP-LISTEN:18789,bind=0.0.0.0,fork,reuseaddr TCP:127.0.0.1:18788 || true
    echo "▶ socat exited — restarting in 1s..."
    sleep 1
  done
) &
SOCAT_PID=$!

# ── Apply virtual memory limit to exec-tool children only ────────────
# Buffer.alloc() with zero-fill uses Linux's CoW zero-page optimization:
# it can claim huge virtual address space without triggering the cgroup
# memory limit (which tracks RSS, not VIRT). We want to cap rogue scripts
# spawned via the agent exec tool, but NOT the gateway itself.
#
# ⚠️ Problem with ulimit -v in the entrypoint:
# OpenClaw gateway 2026.3.23+ maps 11-12GB of virtual address space at
# startup (WASM + V8 + connection pools). Setting ulimit -v here caps
# the gateway process too, and at 16GB there's not enough headroom for
# active TLS sessions → "Connection error" on every API call.
#
# ✅ Correct approach: export OPENCLAW_VIRTUAL_MEM_KB for the gateway
# to pass to exec-tool child processes. The gateway itself should read
# this env var and apply ulimit -v only when forking agent exec shells.
# Until the gateway supports this natively, we document the gap here.
#
# ISSUE-18: exec-tool children don't inherit ulimit -v without gateway support.
# When resolved: apply ulimit -v only to exec_tool fork paths, not gateway.
echo "▶ Virtual memory cap: delegated to exec-tool children (ISSUE-18 pending)"

# ── NODE_OPTIONS for gateway ──────────────────────────────────────────
# NODE_OPTIONS contains --require for proxy-bootstrap.js which the gateway
# needs to route API calls through the Anthropic-only proxy. We keep it.
# (Previously this unset NODE_OPTIONS to remove --max-old-space-size=384
# which caused GC thrashing — that's no longer in docker-compose.yml.)
# (NODE_OPTIONS intentionally empty — no proxy bootstrap needed)

# ── Start the gateway with auto-restart loop ─────────────────────────
# openclaw's `config set` can trigger a full process restart (SIGUSR1
# → new child process → parent exits 0). Without a restart loop, this
# kills the container. The loop restarts the gateway process while the
# socat proxy (running as background job) stays alive.
echo "▶ Starting OpenClaw gateway (loopback, auth=none)..."
while true; do
  openclaw gateway run \
    --bind loopback \
    --auth none \
    --allow-unconfigured \
    --port 18788 || EXIT_CODE=$?
  # Exit code 0 = clean restart requested (e.g. config reload)
  # Exit code non-zero = real error — propagate and stop
  EXIT_CODE=${EXIT_CODE:-0}
  if [ "$EXIT_CODE" -ne 0 ]; then
    echo "▶ Gateway exited with code $EXIT_CODE — stopping container"
    kill $SOCAT_PID 2>/dev/null || true
    exit "$EXIT_CODE"
  fi
  echo "▶ Gateway restarting (config reload)..."
  sleep 1
done
