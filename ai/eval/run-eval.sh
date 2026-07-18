#!/bin/bash
# run-eval.sh — DRO-317 (Phase 5 of the DRO-311 eval harness)
#
# One-command entry point for the real-edge-function generation eval.
# Runs `run-generation-eval.js` (which itself scores each plan, attaches the advisory
# Yupa coaching audit inline, writes the results JSON, AND renders the markdown report),
# then prints the report path at the end for easy review.
#
# All flags are passed straight through to the runner:
#   --scenarios <N>   only the first N scenarios
#   --runs <N>        iterations per scenario (default 3)
#   --label <tag>     output filename tag (results/eval-report-<tag>.md)
#
# Usage:
#   ./run-eval.sh                              # all scenarios, N=3  (⚠️ real prod cost)
#   ./run-eval.sh --scenarios 1 --runs 1       # cheap smoke test
#   ./run-eval.sh --scenarios 2 --label pre-fix
#
# ⚠️  COST: every run is a real prod `generate-plan` call (~1-2 min, costs OpenAI) plus
#     one gpt-4.1 advisory-audit call per scored plan. Use --scenarios/--runs to keep it cheap.
#
# Requires (same as run-generation-eval.js): SUPABASE_URL, SUPABASE_ANON_KEY,
#   SUPABASE_SERVICE_ROLE_KEY (for test-user cleanup) and OPENAI_API_KEY (for the audit).

set -euo pipefail
cd "$(dirname "$0")"

# Stream the runner's output live while also capturing it so we can re-surface the
# report path as the final line (the runner prints "Report written to <path>").
OUTPUT_LOG="$(mktemp)"
trap 'rm -f "$OUTPUT_LOG"' EXIT

node run-generation-eval.js "$@" | tee "$OUTPUT_LOG"

echo ""
echo "=========================================="
REPORT_LINE="$(grep -E '^Report written to ' "$OUTPUT_LOG" | tail -1 || true)"
if [ -n "$REPORT_LINE" ]; then
  echo "📄 ${REPORT_LINE#Report written to }"
else
  echo "⚠️  No report path found in output — check the run above."
fi
echo "=========================================="
