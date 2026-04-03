# T8 — Context injection test
**Date:** 2026-04-02 18:50
**Duration:** 51s
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
▶ Attaching 3 file(s) from /var/folders/wk/ctwq36r557v6sg619wf3qp1c0000gn/T/tmp.rG7Gg6RBdD/src as context...
`add`, `subtract`, `PI`, `E`.

(`constants.js` exports both `PI` and `E`; `index.js` re-exports `add`, `subtract`, and `PI` from the other modules; `math.js` exports `add` and `subtract`.)
```

## Live E2E — --thinking flag
```
HELLO
```

## Assessment
✓ All checks passed
✓ No warnings
