#!/bin/sh
set -eu

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
    --gateway-token "bootstrap-init-token" \
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
  # Use minimal tools profile to avoid spurious warnings about unavailable tools
  # (the 'coding' profile includes apply_patch/image_generate which aren't available
  # in headless/docker runtimes, causing noisy WARN logs on every startup)
  openclaw config set tools.profile minimal 2>/dev/null || true
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
echo "▶ Starting socat proxy (0.0.0.0:18789 → 127.0.0.1:18788)..."
socat TCP-LISTEN:18789,bind=0.0.0.0,fork,reuseaddr TCP:127.0.0.1:18788 &
SOCAT_PID=$!

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
