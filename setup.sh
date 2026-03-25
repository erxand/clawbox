#!/usr/bin/env bash
set -euo pipefail

# ── Clawbox — First-Run Setup ────────────────────────────────
# This script gets you from zero to running in one command.

COMPOSE_FILE="docker-compose.yml"
ENV_FILE=".env"
VOLUME_NAME="clawbox_clawbox-work-state"

# Colors (disabled if not a terminal)
if [ -t 1 ]; then
  BOLD='\033[1m' DIM='\033[2m' GREEN='\033[32m' YELLOW='\033[33m' RED='\033[31m' RESET='\033[0m'
else
  BOLD='' DIM='' GREEN='' YELLOW='' RED='' RESET=''
fi

info()  { echo -e "${GREEN}▶${RESET} $*"; }
warn()  { echo -e "${YELLOW}⚠${RESET} $*"; }
error() { echo -e "${RED}✗${RESET} $*" >&2; }
die()   { error "$@"; exit 1; }

# ── Preflight checks ────────────────────────────────────────────────

info "Checking prerequisites..."

# Docker installed?
if ! command -v docker &>/dev/null; then
  die "Docker is not installed. Get it at https://docs.docker.com/get-docker/"
fi

# Docker daemon running?
if ! docker info &>/dev/null; then
  die "Docker daemon is not running. Start Docker Desktop (or systemctl start docker) and try again."
fi

# docker compose available?
if ! docker compose version &>/dev/null; then
  die "docker compose (v2) not found. Update Docker Desktop or install the compose plugin."
fi

info "Docker is ready."

# ── Environment file ────────────────────────────────────────────────

if [ -f "$ENV_FILE" ]; then
  info "Found existing .env — not overwriting."
  set -a; source "$ENV_FILE"; set +a
else
  info "Creating .env file..."

  # Anthropic API key
  if [ -n "${ANTHROPIC_API_KEY:-}" ]; then
    info "Using ANTHROPIC_API_KEY from environment."
  else
    echo ""
    echo -e "${BOLD}Anthropic API Key${RESET}"
    echo "  Get one at https://console.anthropic.com/settings/keys"
    echo ""
    read -rp "  Enter your Anthropic API key: " ANTHROPIC_API_KEY
    if [ -z "$ANTHROPIC_API_KEY" ]; then
      die "API key is required."
    fi
  fi

  # Write .env
  cat > "$ENV_FILE" <<EOF
ANTHROPIC_API_KEY=${ANTHROPIC_API_KEY}
EOF
  chmod 600 "$ENV_FILE"
  info ".env created (permissions: 600)."
fi

# ── Build and start ─────────────────────────────────────────────────

info "Building container image..."
docker compose build --quiet

info "Starting clawbox-work..."
docker compose up -d

# ── Wait for container to be healthy ────────────────────────────────
echo ""
info "Waiting for gateway to become healthy (up to 60s)..."
for i in $(seq 1 30); do
  STATUS=$(docker inspect --format='{{.State.Health.Status}}' clawbox-work 2>/dev/null || echo "unknown")
  if [ "$STATUS" = "healthy" ]; then
    info "Gateway is healthy!"
    break
  fi
  sleep 2
done

STATUS=$(docker inspect --format='{{.State.Health.Status}}' clawbox-work 2>/dev/null || echo "unknown")
if [ "$STATUS" != "healthy" ]; then
  warn "Container not yet healthy (status: $STATUS). Check: docker compose logs -f"
fi

# ── Print next steps ────────────────────────────────────────────────

echo ""
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo -e "${BOLD} Clawbox is ready!${RESET}"
echo -e "${BOLD}═══════════════════════════════════════════════════${RESET}"
echo ""
echo -e "  Gateway:  ${GREEN}ws://localhost:18790${RESET}"
echo -e "  Auth:     ${DIM}none (loopback-only, host access only)${RESET}"
echo ""
echo -e "${BOLD}Connect the CLI:${RESET}"
echo ""
echo "  export OPENCLAW_GATEWAY_URL=ws://localhost:18790"
echo "  export OPENCLAW_GATEWAY_TOKEN=clawbox"
echo "  openclaw agent --agent main -m \"hello\""
echo ""
echo -e "  ${DIM}(OPENCLAW_GATEWAY_TOKEN is required by the CLI when overriding the URL;"
echo -e "   the value doesn't matter — auth=none on the gateway)${RESET}"
echo ""
echo -e "${BOLD}Or add to ~/.zshrc for convenience:${RESET}"
echo ""
echo "  export OPENCLAW_GATEWAY_URL=ws://localhost:18790"
echo "  export OPENCLAW_GATEWAY_TOKEN=clawbox"
echo "  alias owc=\"openclaw agent --agent main\""
echo ""
echo -e "${BOLD}Useful commands:${RESET}"
echo ""
echo "  make status   — check gateway status"
echo "  make logs     — tail gateway logs"
echo "  make stop     — stop the container"
echo "  make shell    — shell into the container"
echo "  make chat     — open openclaw TUI"
echo ""
echo -e "${DIM}Run 'make help' for all available targets.${RESET}"
echo ""
