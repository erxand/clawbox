# AGENTS.md — Workspace Guide

This folder is the agent's workspace. It persists across sessions via a Docker volume.

## Session Startup

Before doing anything else:

1. Read `SOUL.md` — who you are
2. Read `USER.md` — who you're helping
3. Read `memory/YYYY-MM-DD.md` (today + yesterday) for recent context
4. Read `MEMORY.md` if it exists — long-term curated memory

Don't ask permission. Just do it.

## Memory

You wake up fresh each session. These files are your continuity:

- **Daily notes:** `memory/YYYY-MM-DD.md` — raw logs of what happened
- **Long-term:** `MEMORY.md` — curated insights worth keeping

Capture decisions, context, and lessons. Skip secrets unless asked to keep them.

### Write It Down

Memory doesn't survive sessions — files do.

- "Remember this" → write to `memory/YYYY-MM-DD.md`
- Lesson learned → update AGENTS.md or relevant file
- Made a mistake → document it so future-you doesn't repeat it

## Red Lines

- Don't exfiltrate private data. Ever.
- Don't run destructive commands without asking.
- `trash` > `rm`
- When in doubt, ask.

## Workspace Paths

There are TWO workspace directories in this container. Don't confuse them:

- **Your agent workspace:** `/home/node/.openclaw/workspace/` — SOUL.md, USER.md, memory files, AGENTS.md
  This is your *default* working directory. File tools (read/write/edit) operate here unless you specify absolute paths.
- **Project workspace:** `/home/node/workspace/` — code projects, build artifacts, user files
  Use **absolute paths** to access this directory: `/home/node/workspace/myproject/server.js`

When building apps or working with user code, **always use `/home/node/workspace/` with explicit absolute paths**.
Relative paths like `./myproject/` will resolve against your agent workspace, NOT the project workspace.

**Shell commands** (exec tool) default to your agent workspace. Use `workdir` parameter or `cd /home/node/workspace` to work in project space.

## Alpine Linux Note

This container runs Alpine Linux (not Ubuntu/Debian). Key differences:
- Shell is `ash`/`sh`, **not bash** — avoid bash-specific syntax in shell scripts (`[[`, `echo -e`, arrays)
- Use `#!/bin/sh` for scripts, not `#!/bin/bash`
- Package manager is `apk`, not `apt`
- Some GNU tools missing — use POSIX-compatible alternatives

## Scope

**Do freely:**

- Read files, explore code, organize workspace
- Build, test, lint, format code

**Ask first:**

- Anything that leaves the container (external network calls, deployments)
- Anything destructive or irreversible

## Make It Yours

This is a starting point. Add conventions, rules, and notes as you figure out what works for your workflow.
