# Clawbox Tests

## Philosophy

Tests should **probe open questions**, not confirm known-good behavior. Each test explores a capability boundary — can the agent handle long tasks? Does it recover from errors? Can it resume across sessions?

## Running tests

Each test is independently runnable:

```bash
bash tests/T1-long-running.sh
bash tests/T3-multi-session.sh
bash tests/T4-error-recovery.sh
```

## Results

Tests produce a result file at `tests/results/YYYY-MM-DD-HH-MM-<test>.md`. Results are self-documenting: what was measured, why it matters, what good looks like, and what actually happened.

## Test index

| Test | What it measures | Why it matters |
|------|-----------------|----------------|
| T1 | Long-running task (10-20 min build) | Can the agent sustain multi-step work without getting stuck? |
| T3 | Multi-session continuity | Does TASK.md + git checkpoints enable resume across restarts? |
| T4 | Error recovery | Does the agent diagnose and fix problems or spiral? |

## Writing new tests

- Each test should be a standalone bash script
- Start with a comment block explaining: what you're measuring, why, and what "good" looks like
- Use `clawbox` CLI commands (not raw docker) where possible
- Always record results to `tests/results/`
- Clean up after yourself (or document what state is left behind)
