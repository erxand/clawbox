# AGENTS.md — Workspace Guide

This folder is the agent's workspace. It persists across sessions via a Docker volume.

## Session Startup

Before doing anything else:

1. Read `SOUL.md` — who you are
2. Read `USER.md` — who you're helping
3. Read `memory/YYYY-MM-DD.md` (today + yesterday) for recent context
4. Read `MEMORY.md` if it exists — long-term curated memory
5. **Check for active work:** Scan `/home/node/workspace/` for any `TASK.md` files. If found, read them — you may be resuming an in-progress task.

Don't ask permission. Just do it.

If you find an existing TASK.md, **do not assume a fresh start** — read it and use it as context. You may be continuing work from a previous session.

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

## Task Journal

For any task that involves building, modifying, or continuing a project — even a short one — use the task journal pattern. Always create TASK.md at the start so you can resume and hand off cleanly:

### Starting a task

Create `TASK.md` **inside your project directory** (e.g. `/home/node/workspace/bookstore-api/TASK.md`) with this structure:

```markdown
# Task: <short description>
**Started:** <timestamp>
**Goal:** <what you're trying to achieve>

## Steps
1. [ ] Step one
2. [ ] Step two
3. [ ] ...

## Current Step
<which step you're on and what you're doing>

## Blockers
<anything preventing progress — empty if none>
```

### During the task

- Update TASK.md as you complete steps (check them off, update "Current Step")
- After each major step, commit your progress:
  ```sh
  cd /home/node/workspace
  git init 2>/dev/null || true
  git add -A
  git commit -m "progress: <what was just done>"
  ```
- If something goes wrong, write the error and what you tried to TASK.md before giving up

### When told to stop early (handoff)

If the user says "stop here" or "I'll continue this in a new session", update TASK.md before stopping:
- Mark completed steps with ✓
- Set "Current Step" to what you were in the middle of
- Add a "How to resume" section describing exactly what the next session should do first

This is critical: the next session's agent will have no memory. A good TASK.md is how you hand off cleanly.

### Finishing the task

When done:
```sh
mkdir -p /home/node/workspace/tasks
mv /home/node/workspace/TASK.md "/home/node/workspace/tasks/$(date +%Y-%m-%d-%H-%M)-<slug>.md"
git -C /home/node/workspace add -A && git -C /home/node/workspace commit -m "task complete: <description>"
```

This lets you (and the human) see what happened, resume interrupted work, and learn from past tasks.

## Scope

**Do freely:**

- Read files, explore code, organize workspace
- Build, test, lint, format code

**Ask first:**

- Anything that leaves the container (external network calls, deployments)
- Anything destructive or irreversible

## Make It Yours

This is a starting point. Add conventions, rules, and notes as you figure out what works for your workflow.
