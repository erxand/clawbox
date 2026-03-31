# T13 — Read-only root filesystem validation
**Date:** 2026-03-30 20:42

## What was tested
Verified ISSUE-8 fix: read-only root filesystem with tmpfs mounts for /tmp and /run,
and redirected writes (GIT_CONFIG_GLOBAL, NPM_CONFIG_CACHE) pointing to the persistent volume.

## Results

| Check | Result |
|-------|--------|
| ReadonlyRootfs=true (Docker inspect) | ✓ true |
| System paths read-only (/usr /bin /lib /etc /sbin) | ✓ all read-only |
| /tmp tmpfs writable | ✓ yes |
| /run tmpfs writable | ✓ yes |
| Volume (/home/node/.openclaw) writable | ✓ yes |
| GIT_CONFIG_GLOBAL set | ✓ yes (GIT_CONFIG_GLOBAL=/home/node/.openclaw/.gitconfig) |
| git config --global writes to volume | ✓ yes |
| ~/.gitconfig absent from rootfs | ✓ correct |
| NPM_CONFIG_CACHE set | ✓ yes (NPM_CONFIG_CACHE=/home/node/.openclaw/.npm-cache) |
| npm install in /tmp | ✓ works |
| npm install in workspace | ✓ works |
| git init+commit in workspace | ✓ works |

## Summary
- **Pass:** 15 / 15
- **Fail:** 0
- **Warn:** 0

## Technical Notes
- read_only: true in docker-compose.yml makes the container rootfs read-only
- tmpfs mounts provide writable ephemeral storage at /tmp (256MB) and /run (32MB)
- Persistent writes go to the named volume at /home/node/.openclaw
- GIT_CONFIG_GLOBAL=/home/node/.openclaw/.gitconfig redirects git config to volume
- NPM_CONFIG_CACHE=/home/node/.openclaw/.npm-cache redirects npm cache to volume
- .npm-global dir in rootfs becomes read-only but global npm installs aren't needed at runtime
