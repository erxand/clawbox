#!/usr/bin/env bash
# tests/lib/common.sh — Shared helpers for all Clawbox test scripts
# Source this file at the top of any test: source "$(dirname "${BASH_SOURCE[0]}")/lib/common.sh"

# ── Rate-limit detection (ISSUE-44) ─────────────────────────────────
#
# USAGE:
#   AGENT_OUTPUT=$(clawbox run "..." 2>&1) || AGENT_EXIT=$?
#   if is_rate_limited "$AGENT_OUTPUT"; then
#     skip_test "T5" "API rate limited — run again later"
#   fi
#
# clawbox run exits 2 on rate limit (and prints CLAWBOX_RATE_LIMITED to stderr).
# For tests that invoke openclaw agent directly, we check the output text too.

RATE_LIMIT_PATTERNS=(
  "API rate limit reached"
  "rate limit reached"
  "rate_limit_error"
  "CLAWBOX_RATE_LIMITED"
  "overloaded_error"
)

# ISSUE-53: "529" removed from RATE_LIMIT_PATTERNS — bare "529" is too broad and matches
# project directory names like "taskman-1774975299" in task logs, producing false-positive
# SKIP results. HTTP 529 is indicated by the more specific patterns above (overloaded_error,
# "API rate limit reached", or CLAWBOX_RATE_LIMITED sentinel emitted by `clawbox run`).

# is_rate_limited <output_string>
# Returns 0 (true) if the output looks like a rate-limit response, 1 otherwise.
is_rate_limited() {
  local output="$1"
  for pattern in "${RATE_LIMIT_PATTERNS[@]}"; do
    if echo "$output" | grep -qi "$pattern"; then
      return 0
    fi
  done
  return 1
}

# skip_rate_limited <test_name> <result_file>
# Writes a SKIP result file and prints a clear message.
# Call this instead of writing a failure result when rate-limited.
skip_rate_limited() {
  local test_name="$1"
  local result_file="$2"
  local extra="${3:-}"

  echo ""
  echo "⏭ SKIP: $test_name — API rate limited. Run again later."
  [ -n "$extra" ] && echo "  Details: $extra"
  echo ""

  mkdir -p "$(dirname "$result_file")"
  cat > "$result_file" << SKIP_EOF
# $test_name — SKIPPED (API Rate Limited)
**Date:** $(date '+%Y-%m-%d %H:%M')

## Status: SKIPPED ⏭

This test run was skipped because the Anthropic API returned a rate limit error.
This is an infrastructure issue, not an agent regression.

**What to do:** Wait 5-10 minutes and re-run the test.

$( [ -n "$extra" ] && echo "## Details\n\`\`\`\n$extra\n\`\`\`" )
SKIP_EOF
}
