#!/bin/bash
set -euo pipefail

# Detect repo root
REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

# Define source -> target mappings
SOURCES=(
  "ai/prompts/step1-macro-plan.txt"
  "ai/prompts/step2-md-to-json.txt"
  "ai/prompts/step3-workout-block.txt"
  "ai/prompts/adjust-step1-v0.txt"
)

TARGETS=(
  "supabase/functions/generate-plan/prompts/step1-macro-plan-prompt.ts"
  "supabase/functions/generate-plan/prompts/step2-md-to-json-prompt.ts"
  "supabase/functions/generate-plan/prompts/step3-workout-block-prompt.ts"
  "supabase/functions/chat-adjust/prompts/adjust-step1-v0-prompt.ts"
)

echo "Syncing prompts from ai/prompts/ to edge function..."

for i in "${!SOURCES[@]}"; do
  SOURCE="${SOURCES[$i]}"
  TARGET="${TARGETS[$i]}"

  if [[ ! -f "$SOURCE" ]]; then
    echo "ERROR: Source file $SOURCE not found"
    exit 1
  fi

  # Extract the base name for the comment
  BASENAME=$(basename "$SOURCE")

  # Read the source content and escape backticks and ${
  CONTENT=$(sed 's/`/\\`/g; s/\${/\\\${/g' "$SOURCE")

  # Write the .ts file with AUTO-GENERATED header
  {
    echo "// AUTO-GENERATED from ai/prompts/$BASENAME — do not edit directly. Run scripts/sync-prompts.sh"
    printf 'export default `%s`\n' "$CONTENT"
  } > "$TARGET"

  echo "✓ Synced $SOURCE -> $TARGET"
done

echo ""
echo "All prompts synced successfully!"
