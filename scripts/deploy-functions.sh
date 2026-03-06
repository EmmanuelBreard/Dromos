#!/bin/bash
# Deploy all (or a specific) Supabase Edge Function.
#
# Usage:
#   ./scripts/deploy-functions.sh              # deploy all functions
#   ./scripts/deploy-functions.sh chat-adjust  # deploy one function
#
# All functions are deployed with --no-verify-jwt because our edge functions
# validate JWTs themselves via authClient.auth.getUser(jwt). The Supabase
# gateway JWT check is redundant and has caused persistent 401 issues.

set -euo pipefail

PROJECT_REF="cumbrfnguykvxhvdelru"
FUNCTIONS_DIR="supabase/functions"

# List of all deployable functions
ALL_FUNCTIONS=(
  "generate-plan"
  "strava-auth"
  "strava-sync"
  "chat-adjust"
  "session-feedback"
)

deploy_function() {
  local fn="$1"
  echo "Deploying $fn..."
  npx supabase functions deploy "$fn" \
    --no-verify-jwt \
    --project-ref "$PROJECT_REF"
  echo "✓ $fn deployed"
}

if [ $# -gt 0 ]; then
  # Deploy specific function(s)
  for fn in "$@"; do
    deploy_function "$fn"
  done
else
  # Deploy all functions
  for fn in "${ALL_FUNCTIONS[@]}"; do
    deploy_function "$fn"
  done
fi

echo ""
echo "Done. Dashboard: https://supabase.com/dashboard/project/$PROJECT_REF/functions"
