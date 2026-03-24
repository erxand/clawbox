# OpenClaw Docker

Run [OpenClaw](https://github.com/openclaw/openclaw) in a Docker container. One command to set up, persistent state via Docker volumes, and easy CLI connectivity from your host.

## Prerequisites

- **Docker Desktop** (or Docker Engine + Compose v2 on Linux)
- **Anthropic API key** — [get one here](https://console.anthropic.com/settings/keys)
- **OpenClaw CLI** on your host machine: `npm install -g openclaw`

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/your-org/openclaw-docker.git
cd openclaw-docker

# 2. Run setup (builds image, creates .env, starts container)
bash setup.sh

# 3. Connect your CLI
export OPENCLAW_GATEWAY_URL=ws://localhost:18790
export OPENCLAW_GATEWAY_TOKEN=<token-from-setup-output>
openclaw gateway health
```

That's it. The setup script will prompt for your API key and generate a secure gateway token.

## How It Works

```
┌─────────────────────┐         ┌──────────────────────────┐
│  Host Machine        │         │  Docker Container        │
│                      │  ws://  │                          │
│  openclaw CLI ───────┼────────►│  openclaw gateway (fg)   │
│                      │ :18790  │  port 18789              │
│                      │         │                          │
│                      │         │  /home/node/.openclaw/   │
│                      │         │  ├── openclaw.json       │
│                      │         │  └── workspace/          │
│                      │         │      ├── SOUL.md         │
│                      │         │      ├── USER.md         │
│                      │         │      └── ...             │
└─────────────────────┘         └──────────────────────────┘
                                         │
                                    Docker Volume
                                 openclaw-work-state
```

- The **gateway** runs in foreground mode inside the container via `openclaw gateway run`
- Your **host CLI** connects over WebSocket on `localhost:18790`
- All state (config, workspace, memory) persists in a **named Docker volume**
- Port is bound to **loopback only** (127.0.0.1) — not exposed to the network

## Usage

### Start / Stop

```bash
make start    # docker compose up -d
make stop     # docker compose down
make status   # show container + gateway status
make logs     # tail container logs
```

### Shell Access

```bash
make shell    # sh into the running container
```

### CLI Connection

Point your host CLI at the container:

```bash
export OPENCLAW_GATEWAY_URL=ws://localhost:18790
export OPENCLAW_GATEWAY_TOKEN=<your-token>
```

Add these to your `~/.zshrc` or `~/.bashrc` to persist across sessions.

Then use the CLI normally:

```bash
openclaw gateway health     # check gateway is reachable
openclaw gateway status     # full status
openclaw tui                # terminal UI
openclaw agent --message "Review this PR" --deliver
```

## What Persists

Everything under `/home/node/.openclaw` lives in the `openclaw-work-state` Docker volume:

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
# Open a shell in the container
make shell

# Edit workspace files
vi ~/.openclaw/workspace/USER.md
vi ~/.openclaw/workspace/SOUL.md
```

Or copy files in from the host:

```bash
docker cp my-custom-SOUL.md openclaw-work:/home/node/.openclaw/workspace/SOUL.md
```

## Backup & Restore

```bash
# Create a timestamped backup
make backup
# → creates backups/openclaw-work-state-20260318-143022.tar.gz

# Restore from a backup
make restore FILE=backups/openclaw-work-state-20260318-143022.tar.gz
```

## Upgrading OpenClaw

```bash
make upgrade
```

This rebuilds the image (pulling the latest `openclaw` from npm) and restarts the container. Your volume data is preserved.

## Environment Variables

| Variable | Required | Description |
|----------|----------|-------------|
| `ANTHROPIC_API_KEY` | Yes | Your Anthropic API key |
| `OPENCLAW_GATEWAY_TOKEN` | Yes | Shared secret for CLI ↔ gateway auth |

These are stored in `.env` (git-ignored, mode 600).

## Troubleshooting

### Container won't start

```bash
docker compose logs    # check for errors
docker compose ps      # check container state
```

### CLI can't connect

1. Verify the container is running: `make status`
2. Check env vars are set: `echo $OPENCLAW_GATEWAY_URL`
3. Verify the token matches: compare `$OPENCLAW_GATEWAY_TOKEN` with `.env`
4. Test the port: `curl -s http://localhost:18790` (should get a WebSocket upgrade error — that's fine, it means the port is reachable)

### Gateway health check fails

```bash
# Check gateway health from inside the container
docker compose exec openclaw-work openclaw gateway health
```

### Permission issues

The container runs as `node` (uid 1000). If you mount host directories instead of Docker volumes, ensure they're owned by uid 1000.

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

## Security Notes

- The gateway port is bound to **127.0.0.1 only** — it's not accessible from other machines on your network
- **Token auth** is enabled by default — the CLI must present the correct token to connect
- The `.env` file has **mode 600** — only your user can read it
- API keys are passed via environment variables, never baked into the image
- The container runs as a **non-root user** (`node`)

## Project Structure

```
.
├── Dockerfile          # Container image definition
├── docker-compose.yml  # Service orchestration
├── entrypoint.sh       # Container startup script
├── setup.sh            # Interactive first-run setup
├── Makefile            # Convenience targets
├── seed/               # Default workspace files
│   ├── AGENTS.md
│   ├── HEARTBEAT.md
│   ├── SOUL.md
│   └── USER.md
├── .env.example        # Template for .env
├── .gitignore
└── README.md
```

## License

MIT
