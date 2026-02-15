#!/bin/bash
# Usage: ./batch-eval.sh [N] [athlete_name]
# Example: ./batch-eval.sh 5 "Emmanuel"

set -e
cd "$(dirname "$0")"

N=${1:-5}
ATHLETE=${2:-""}
BATCH_DIR="results/batch"

echo "Batch eval: $N runs"
if [ -n "$ATHLETE" ]; then
  echo "Athlete filter: $ATHLETE"
fi
echo ""

# Clean previous batch results
rm -rf "$BATCH_DIR"
mkdir -p "$BATCH_DIR"

# Run N iterations
for i in $(seq 1 $N); do
  echo "=========================================="
  echo "Run $i/$N — $(date '+%H:%M:%S')"
  echo "=========================================="

  if [ -n "$ATHLETE" ]; then
    node run-step3-blocks.js --athlete "$ATHLETE"
  else
    node run-step3-blocks.js
  fi

  # Save results
  cp results/step3-blocks.json "$BATCH_DIR/run-$i.json"

  # Run violation check
  node check-step3-violations.js "$BATCH_DIR/run-$i.json" > "$BATCH_DIR/violations-$i.txt" 2>&1

  # Format readable plan
  node format-plan.js "$BATCH_DIR/run-$i.json" ${ATHLETE:+--athlete "$ATHLETE"} > "$BATCH_DIR/plan-$i.txt"

  echo "Saved to $BATCH_DIR/run-$i.json"
  echo ""
done

echo ""
echo "=========================================="
echo "AGGREGATE RESULTS"
echo "=========================================="
node aggregate-violations.js $N ${ATHLETE:+"$ATHLETE"}

echo ""
echo "Readable plans saved to: $BATCH_DIR/plan-*.txt"
echo "Violation details saved to: $BATCH_DIR/violations-*.txt"
