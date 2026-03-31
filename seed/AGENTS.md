# AGENTS.md — Workspace Guide

This folder IS your workspace. `/home/node/.openclaw/workspace/` is where everything lives — your config files, memory, AND code projects.

## Session Startup

Before doing anything else:

1. Read `SOUL.md` — who you are
2. Read `USER.md` — who you're helping
3. Read `memory/YYYY-MM-DD.md` (today + yesterday) for recent context
4. Read `MEMORY.md` if it exists — long-term curated memory
5. **Check for active work:** Run `find /home/node/.openclaw/workspace -name 'TASK.md' 2>/dev/null` to see if you're resuming an in-progress task. If found, read it.

Don't ask permission. Just do it.

If you find an existing TASK.md, **do not assume a fresh start** — read it and use it as context. You are almost certainly continuing work from a previous session.

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

## Workspace Path

There is ONE workspace: `/home/node/.openclaw/workspace/`

This is your default working directory. It persists across container restarts via a Docker volume. Everything lives here:
- Your agent config: `SOUL.md`, `USER.md`, `AGENTS.md`, `MEMORY.md`, `memory/`
- Your code projects: `my-app/`, `bookstore-api/`, etc.

**Put projects inside this directory.** Example:
- `/home/node/.openclaw/workspace/bookstore-api/server.js`
- `/home/node/.openclaw/workspace/my-react-app/package.json`

There is **no separate** `/home/node/workspace/` directory. Do not reference it.

Shell commands run with `/home/node/.openclaw/workspace/` as the working directory by default.

## Alpine Linux Note

This container runs Alpine Linux (not Ubuntu/Debian). Key differences:
- Shell is `ash`/`sh`, **not bash** — avoid bash-specific syntax in shell scripts (`[[`, `echo -e`, arrays)
- Use `#!/bin/sh` for scripts, not `#!/bin/bash`
- Package manager is `apk`, not `apt`
- Some GNU tools missing — use POSIX-compatible alternatives

## Task Journal

For any task that involves building, modifying, or continuing a project — even a short one — use the task journal pattern. Always create TASK.md at the start so you can resume and hand off cleanly:

### Starting a task

Create `TASK.md` **inside your project directory** (e.g. `/home/node/.openclaw/workspace/bookstore-api/TASK.md`) with this structure:

```markdown
# Task: <short description>
**Started:** <timestamp>
**Goal:** <what you're trying to achieve>

## Steps
<!-- After completing EACH step, run: git -C /home/node/.openclaw/workspace add -A && git -C /home/node/.openclaw/workspace commit -m "progress: <step name>" -->
1. [ ] Step one
2. [ ] Step two
3. [ ] ...

## Current Step
<which step you're on and what you're doing>

## Git Log
<!-- Updated after each commit -->
(no commits yet)

## Blockers
<anything preventing progress — empty if none>
```

### During the task

- Update TASK.md as you complete steps (check them off, update "Current Step")
- **REQUIRED: After each major step, commit your progress.** This is not optional — commits
  are what allow the task to be resumed if something goes wrong mid-way. Do not skip this.
  ```sh
  git -C /home/node/.openclaw/workspace init 2>/dev/null || true
  git -C /home/node/.openclaw/workspace add -A
  git -C /home/node/.openclaw/workspace commit -m "progress: <what was just done>"
  ```
  Then update the "Git Log" section in TASK.md with the commit hash and message.

  Examples of "major steps" that warrant a commit:
  - Created project scaffold / package.json installed
  - Finished the backend / wrote main server file
  - All tests passing
  - Frontend complete
- If something goes wrong, write the error and what you tried to TASK.md before giving up

### Resuming a task

When you find an existing TASK.md (from the session startup check or because the user says "continue"):

1. **Read TASK.md immediately** — understand what was done and what's left
2. **Run existing tests first** to confirm baseline state before making changes
3. **Continue from where it left off** — implement the unchecked steps in order
4. **Check off each step as you complete it** — update the `[ ]` → `[x]` in TASK.md
5. **Update "Current Step"** as you move through the work
6. **Commit after each major step** with a "progress: ..." commit message
7. **Update TASK.md's Git Log section** with new commit hashes
8. When all steps are done, move TASK.md to the tasks/ archive and make a final commit

**Critical:** After resuming and completing work, your TASK.md MUST show updated checkboxes and the git log MUST have new commits. A session that completes work but leaves TASK.md unchanged has not properly recorded its progress — the next session will re-do everything.

### When told to stop early (handoff)

If the user says "stop here" or "I'll continue this in a new session", update TASK.md before stopping:
- Mark completed steps with ✓
- Set "Current Step" to what you were in the middle of
- Add a "How to resume" section describing exactly what the next session should do first

This is critical: the next session's agent will have no memory. A good TASK.md is how you hand off cleanly.

### Finishing the task

When done:
```sh
mkdir -p /home/node/.openclaw/workspace/tasks
mv /home/node/.openclaw/workspace/TASK.md "/home/node/.openclaw/workspace/tasks/$(date +%Y-%m-%d-%H-%M)-<slug>.md"
git -C /home/node/.openclaw/workspace add -A && git -C /home/node/.openclaw/workspace commit -m "task complete: <description>"
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
