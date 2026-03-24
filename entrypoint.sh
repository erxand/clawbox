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
    --gateway-bind loopback \
    --no-install-daemon \
    --skip-channels \
    --skip-skills \
    --skip-search \
    --skip-ui \
    --skip-health \
    --workspace "$WORKSPACE_DIR"
fi

# ── Seed workspace files if workspace is empty ───────────────────────
if [ ! -f "$WORKSPACE_DIR/SOUL.md" ] && [ -d /home/node/seed ]; then
  echo "▶ Seeding workspace with default files..."
  mkdir -p "$WORKSPACE_DIR"
  cp /home/node/seed/*.md "$WORKSPACE_DIR/"
  # Initialize git repo in workspace (openclaw expects it for skill tooling)
  cd "$WORKSPACE_DIR"
  if [ ! -d .git ]; then
    git init -q
    git add -A
    git commit -q -m "Initial workspace seed"
  fi
  cd "$HOME"
fi

# ── Start gateway + socat proxy ───────────────────────────────────────
# The gateway binds to loopback (127.0.0.1:18788) with auth=none.
# socat proxies 0.0.0.0:18789 → 127.0.0.1:18788 so Docker's port
# mapping (host 127.0.0.1:18790 → container :18789) can reach it.
# Security: the host-side port 18790 is loopback-only, so only processes
# on the host machine can connect — no network exposure.
echo "▶ Starting OpenClaw gateway (foreground)..."
socat TCP-LISTEN:18789,bind=0.0.0.0,fork,reuseaddr TCP:127.0.0.1:18788 &

exec openclaw gateway run \
  --bind loopback \
  --auth none \
  --allow-unconfigured \
  --port 18788
