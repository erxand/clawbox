# Clawbox

Run [OpenClaw](https://github.com/openclaw/openclaw) in a Docker container. One command to set up, persistent state via Docker volumes, and zero-friction CLI connectivity from your host.

## Prerequisites

- **Docker Desktop** (or Docker Engine + Compose v2 on Linux)
- **Anthropic API key** — run `claude setup-token` and copy the key it gives you
- **OpenClaw CLI** on your host machine: `npm install -g openclaw`

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/erxand/clawbox.git
cd clawbox

# 2. Create .env with your API key
cp .env.example .env
# Edit .env and set ANTHROPIC_API_KEY

# 3. Run setup (builds image, starts container, waits for healthy)
bash setup.sh

# 4. (Optional) Install the clawbox CLI for convenience
make install   # copies clawbox to /usr/local/bin

# 5. Send your first message
clawbox run "hello"

# Or open an interactive chat session
clawbox chat
```

> **Without `make install`:** use `./clawbox run "hello"` from the project directory, or set env vars manually:
> ```bash
> export OPENCLAW_GATEWAY_URL=ws://localhost:18790
> export OPENCLAW_GATEWAY_TOKEN=clawbox
> openclaw agent --agent main -m "hello"
> ```

## Architecture

```
┌─────────────────────────┐         ┌───────────────────────────────────┐
│  Host Machine            │         │  Docker Container                 │
│                          │         │                                   │
│  openclaw CLI ───────────┼── ws ──►│  socat (0.0.0.0:18789)           │
│  ws://localhost:18790    │ :18790  │    │                              │
│                          │         │    ▼                              │
│  (loopback only — safe)  │         │  openclaw gateway (127.0.0.1:18788)
│                          │         │    --bind loopback --auth none    │
│                          │         │                                   │
│                          │         │  /home/node/.openclaw/            │
│                          │         │  ├── openclaw.json                │
│                          │         │  └── workspace/                   │
└─────────────────────────┘         └───────────────────────────────────┘
                                             │
                                        Docker Volume
                                     clawbox-work-state
```

### Why socat?

The gateway runs with `--auth none` and `--bind loopback` inside the container. This means it only listens on `127.0.0.1:18788` — unreachable from Docker's port mapping. **socat** bridges the gap by listening on `0.0.0.0:18789` inside the container and forwarding to `127.0.0.1:18788`.

On the host side, Docker maps `127.0.0.1:18790 → container:18789`, so the gateway is **only reachable from your machine's loopback interface**. No device pairing, no token management — zero friction for developers.

### Security Model

- **auth=none** is safe because the port is **loopback-only on the host** (`127.0.0.1:18790`)
- No other machine on your network can reach the gateway
- The `.env` file has **mode 600** — only your user can read it
- API keys are passed via environment variables, never baked into the image
- The container runs as a **non-root user** (`node`)

## Daily Usage

### Start / Stop

```bash
make start    # docker compose up -d
make stop     # docker compose down
make status   # show container + gateway status
make logs     # tail container logs
```

### Send Messages

```bash
# Set the gateway URL and token (add to ~/.zshrc to persist)
# Note: OPENCLAW_GATEWAY_TOKEN is required by the CLI when overriding the URL.
# The value doesn't matter (auth=none) — any non-empty string works.
export OPENCLAW_GATEWAY_URL=ws://localhost:18790
export OPENCLAW_GATEWAY_TOKEN=clawbox

# Send a message
openclaw agent --agent main -m "review this PR"

# Or open the TUI
make chat
```

**Recommended: add a shell alias to `~/.zshrc`:**

```bash
export OPENCLAW_GATEWAY_URL=ws://localhost:18790
export OPENCLAW_GATEWAY_TOKEN=clawbox
alias owc="openclaw agent --agent main"
```

Then just: `owc -m "hello"`

You can also source the included connect script:

```bash
source .clawbox-connect
openclaw agent --agent main -m "hello"
```

### Shell Access

```bash
make shell    # sh into the running container
```

## What Persists

Everything under `/home/node/.openclaw` lives in the `clawbox-work-state` Docker volume:

| Path | Purpose |
|------|---------|
| `openclaw.json` | Gateway and agent configuration |
| `workspace/SOUL.md` | Agent identity and personality |
| `workspace/USER.md` | Info about you (fill this in!) |
| `workspace/AGENTS.md` | Workspace rules and conventions |
| `workspace/HEARTBEAT.md` | Periodic heartbeat tasks |
| `workspace/memory/` | Agent memory (daily notes + long-term) |
| `credentials/` | Auth tokens and channel credentials |
| `logs/` | Session logs |

## Customizing the Agent

Edit workspace files directly in the volume:

```bash
make shell
vi ~/.openclaw/workspace/USER.md
vi ~/.openclaw/workspace/SOUL.md
```

Or copy files in from the host:

```bash
docker cp my-custom-SOUL.md clawbox-work:/home/node/.openclaw/workspace/SOUL.md
```

## Backup & Restore

```bash
# Create a timestamped backup
make backup
# → creates backups/clawbox-work-state-20260318-143022.tar.gz

# Restore from a backup
make restore FILE=backups/clawbox-work-state-20260318-143022.tar.gz
```

## Upgrading OpenClaw

```bash
make upgrade
```

This rebuilds the image (pulling the latest `openclaw` from npm) and restarts the container. Your volume data is preserved.

## Environment Variables

| Variable | Required | Default | Description |
|----------|----------|---------|-------------|
| `ANTHROPIC_API_KEY` | Yes | — | Your Anthropic API key |
| `OPENCLAW_DEFAULT_MODEL` | No | `anthropic/claude-haiku-4-5` | LLM model for the agent (only applied on first run / fresh volume) |
| `OPENCLAW_TOOLS_PROFILE` | No | `coding` | Tool profile for the agent: `minimal` (session_status only), `coding` (read/write/exec/web/memory), `messaging`, `full` |

Stored in `.env` (git-ignored, mode 600).

**Changing the model on an existing volume:**

```bash
# Shell into the container and use the config command
make shell
openclaw config set agents.defaults.model.primary anthropic/claude-sonnet-4-6
```

**Example `.env` to use Sonnet instead of Haiku:**

```bash
ANTHROPIC_API_KEY=sk-ant-...
OPENCLAW_DEFAULT_MODEL=anthropic/claude-sonnet-4-6
```

## Troubleshooting

### Container won't start

```bash
docker compose logs    # check for errors
docker compose ps      # check container state
```

### CLI can't connect

1. Verify the container is running and healthy: `make status`
2. Check the gateway URL is set: `echo $OPENCLAW_GATEWAY_URL`
3. Test the port: `curl -s http://localhost:18790` (should get a WebSocket upgrade error — that means the port is reachable)
4. Check container logs: `make logs`

### Gateway health check fails inside the container

```bash
docker compose exec clawbox-work openclaw gateway health
```

### socat proxy not working

```bash
# Check if socat is running inside the container
docker compose exec clawbox-work ps aux | grep socat

# Check if the gateway is listening on 18788
docker compose exec clawbox-work netstat -tlnp 2>/dev/null || \
  docker compose exec clawbox-work ss -tlnp
```

### Permission issues

The container runs as `node` (uid 1000). If you mount host directories instead of Docker volumes, ensure they're owned by uid 1000.

### Container doesn't restart after machine reboot

The default `restart: "no"` policy is intentional for development use — you control when the container runs. For always-on/production usage, change it in `docker-compose.yml`:

```yaml
services:
  clawbox-work:
    restart: unless-stopped   # or always
```

### Out of memory

Increase the memory limit in `docker-compose.yml`:

```yaml
deploy:
  resources:
    limits:
      memory: 1024m
```

### Reset everything

```bash
make clean    # stops container + removes volume (with confirmation)
bash setup.sh # start fresh
```

## Project Structure

```
.
├── Dockerfile                  # Container image definition
├── docker-compose.yml          # Service orchestration
├── entrypoint.sh               # Container startup (socat + gateway)
├── setup.sh                    # Interactive first-run setup
├── Makefile                    # Convenience targets
├── .clawbox-connect    # Source this to set env vars for CLI
├── seed/                       # Default workspace files
│   ├── AGENTS.md
│   ├── HEARTBEAT.md
│   ├── SOUL.md
│   └── USER.md
├── .env.example                # Template for .env
├── .gitignore
└── README.md
```

## License

MIT
