#!/bin/bash
set -euo pipefail

# Upload static assets to Supabase Storage
# Requires: supabase CLI logged in and linked to project

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

SOURCE="$REPO_ROOT/ai/context/workout-library.json"
if [[ ! -f "$SOURCE" ]]; then
  echo "ERROR: $SOURCE not found"
  exit 1
fi

echo "Uploading workout-library.json to static-assets bucket..."
# --experimental required for `storage cp` (supabase-cli v2.x)
supabase storage cp \
  "$SOURCE" \
  ss:///static-assets/workout-library.json \
  --experimental

echo "Done. Verify in Supabase Dashboard > Storage > static-assets bucket."
