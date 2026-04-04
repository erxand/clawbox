# T24 — Context injection at scale + clawbox clean abort
**Date:** 2026-04-03 20:57
**Duration:** 33s

## What was tested

### Phase 1 — --context dir at scale
- Injected a realistic 9-file Express invoice API project via `--context <dir>`
- Verified: valid JSON, context_files count, elapsed_ms, session key, agent references project concepts

### Phase 2 — clawbox clean abort
- Sent 'N' to the clean confirmation prompt
- Verified: warning message present, abort confirmed, container NOT deleted, clean in help

### Phase 3 — Large single-file context
- Injected a ~6398-byte JS file with a unique sentinel value
- Verified: context_files=1, agent reads and reports sentinel value

## Results

| Check | Phase | Result |
|-------|-------|--------|
| ✓ container running at test start\n  ✓ Phase 1: --context dir output is valid JSON\n  ✓ Phase 1: context_files=10 (>1, correct for multi-file dir)\n  ✓ Phase 1: context_files=10 (below 50-file cap)\n  ✓ Phase 1: elapsed_ms=16809 (positive)\n  ✓ Phase 1: session key present in JSON (value: t24-ctx-scale)\n  ✓ Phase 1: agent response references project concepts (5/5 keywords found)\n  ✓ Phase 2: clean prints destructive warning message\n  ✓ Phase 2: clean prints abort/cancel confirmation\n  ✓ Phase 2: container still running after clean abort (data NOT deleted)\n  ✓ Phase 2: 'clean' listed in clawbox help\n  ✓ Phase 3: large file --context output is valid JSON\n  ✓ Phase 3: context_files=1 for single file\n  ✓ Phase 3: agent correctly read and quoted the sentinel value from large file\n | P2 | |

**Pass:** 14 / 14 | **Fail:** 0 | **Warn:** 0 | **Duration:** 33s

## Findings
  ✓ container running at test start\n  ✓ Phase 1: --context dir output is valid JSON\n  ✓ Phase 1: context_files=10 (>1, correct for multi-file dir)\n  ✓ Phase 1: context_files=10 (below 50-file cap)\n  ✓ Phase 1: elapsed_ms=16809 (positive)\n  ✓ Phase 1: session key present in JSON (value: t24-ctx-scale)\n  ✓ Phase 1: agent response references project concepts (5/5 keywords found)\n  ✓ Phase 2: clean prints destructive warning message\n  ✓ Phase 2: clean prints abort/cancel confirmation\n  ✓ Phase 2: container still running after clean abort (data NOT deleted)\n  ✓ Phase 2: 'clean' listed in clawbox help\n  ✓ Phase 3: large file --context output is valid JSON\n  ✓ Phase 3: context_files=1 for single file\n  ✓ Phase 3: agent correctly read and quoted the sentinel value from large file\n

## Phase 1 agent response
```
`XYZZY_T24_CANARY_42`
```

## Phase 2 clean output
```
⚠ This will STOP the container and DELETE all agent data.
Aborted.
```
