# T8 — Context injection test
**Date:** 2026-04-04 00:52
**Duration:** 36s
**Container running:** true

## Summary

| Metric | Value |
|--------|-------|
| Pass | 10 |
| Warn | 0 |
| Fail | 0 |

## What was tested
- `--context <file>`: single-file injection, agent references injected code
- `--context <dir>`: directory injection, all files included, node_modules excluded
- `--thinking <level>`: flag forwarded, agent still responds normally
- `--quiet`: banners suppressed on stdout (sent to stderr)
- `--json`: valid JSON output with required keys
- Invalid path → clear error message
- Missing message → usage hint

## Live E2E — Single file context
```
It exports `add` and `subtract`.
```

## Live E2E — Directory context
```
▶ Attaching 3 file(s) from /var/folders/wk/ctwq36r557v6sg619wf3qp1c0000gn/T/tmp.AI6wL9Ttoq/src as context...
add, subtract, PI, E
```

## Live E2E — --thinking flag
```
HELLO
```

## Assessment
✓ All checks passed
✓ No warnings
