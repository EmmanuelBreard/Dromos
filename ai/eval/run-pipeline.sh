#!/bin/bash
# Runs the 3-step training plan pipeline:
#   Step 1: GPT-4o generates MD plan (coaching quality)
#   Step 2: GPT-4o-mini converts MD → JSON (mechanical)
#   Step 3: GPT-4o selects workouts in 4-week blocks + post-processing

cd "$(dirname "$0")"

echo "=== Step 1: Generating macro plans (markdown) ==="
npx promptfoo eval -o results/step1.json --no-cache || true

echo ""
echo "=== Extracting step 1 outputs for step 2 ==="
node extract-step1-outputs.js

echo ""
echo "=== Step 2: Converting markdown → JSON ==="
npx promptfoo eval -c promptfooconfig.step2.yaml -o results/step2.json --no-cache || true

echo ""
echo "=== Step 3: Selecting workouts (block-based) ==="
node run-step3-blocks.js

echo ""
echo "=== Validating Step 3 outputs ==="
npx promptfoo eval -c promptfooconfig.step3.yaml -o results/step3.json --no-cache

echo ""
echo "=== Done! ==="
echo "View step 1 (coaching quality): npx promptfoo eval && npx promptfoo view"
echo "View step 2 (JSON conversion):  npx promptfoo eval -c promptfooconfig.step2.yaml && npx promptfoo view"
echo "View step 3 (workout selection): npx promptfoo eval -c promptfooconfig.step3.yaml && npx promptfoo view"
