// Aggregate violation stats across N batch runs
// Usage: node aggregate-violations.js <N> [athlete_filter]
//
// Also exports `labelStability(runsWithViolation, totalRuns)` — the CLEAN /
// VARIANCE / INVESTIGATE / SYSTEMATIC stability label used both by this CLI and
// by the DRO-311 harness runners (run-generation-eval.js) so both share one
// source of truth for how per-metric stability is bucketed across N runs.
const fs = require('fs');
const path = require('path');

const VIOLATION_TYPES = ['duration', 'sport', 'rest', 'brick', 'cluster', 'sameday', 'intensity', 'brickorder'];

/**
 * Buckets a metric's cross-run stability. `runsWithViolation` is how many of
 * `totalRuns` had a non-zero count for the metric.
 *   0 runs                → CLEAN         (never violated)
 *   >= 60% of runs        → SYSTEMATIC    (reliably broken — real bug)
 *   >= 30% of runs        → INVESTIGATE   (frequent enough to look at)
 *   otherwise             → VARIANCE (OK) (rare, likely temp-0.2 noise)
 * @returns {'CLEAN'|'SYSTEMATIC'|'INVESTIGATE'|'VARIANCE (OK)'}
 */
function labelStability(runsWithViolation, totalRuns) {
  if (runsWithViolation === 0) return 'CLEAN';
  if (runsWithViolation >= totalRuns * 0.6) return 'SYSTEMATIC';
  if (runsWithViolation >= totalRuns * 0.3) return 'INVESTIGATE';
  return 'VARIANCE (OK)';
}

// ─── CLI: read all summary JSONs from batch violation outputs and print per-athlete
//     stability across the N runs. Guarded so `require()` from a runner is side-effect-free.
function runCli() {
  const N = parseInt(process.argv[2] || '5');
  const athleteFilter = process.argv[3] || null;
  const batchDir = path.join(__dirname, 'results', 'batch');

  const allRuns = [];
  for (let i = 1; i <= N; i++) {
    const violFile = path.join(batchDir, 'violations-' + i + '.txt');
    if (!fs.existsSync(violFile)) {
      console.log('Warning: ' + violFile + ' not found, skipping');
      continue;
    }
    const content = fs.readFileSync(violFile, 'utf8');
    const summaryMatch = content.match(/__SUMMARY_JSON__(.*)/);
    if (summaryMatch) {
      allRuns.push(JSON.parse(summaryMatch[1]));
    }
  }

  if (allRuns.length === 0) {
    console.log('No violation data found in ' + batchDir);
    process.exit(1);
  }

  // Get athlete names
  const athletes = Object.keys(allRuns[0]);

  for (const athlete of athletes) {
    if (athleteFilter && !athlete.includes(athleteFilter)) continue;

    console.log('\n=== ' + athlete + ' (' + allRuns.length + ' runs) ===\n');

    for (const type of VIOLATION_TYPES) {
      const counts = allRuns.map(run => (run[athlete] || {})[type] || 0);
      const runsWithViolation = counts.filter(c => c > 0).length;
      const total = counts.reduce((a, b) => a + b, 0);
      const avg = (total / allRuns.length).toFixed(1);

      const label = labelStability(runsWithViolation, allRuns.length);

      const typeName = {
        duration:   'Duration cap     ',
        sport:      'Sport eligibility ',
        rest:       'Rest day          ',
        brick:      'Missing bricks    ',
        cluster:    'Sport clustering  ',
        sameday:    'Same-day conflict ',
        intensity:  'Intensity cluster ',
        brickorder: 'Brick order       '
      }[type];

      console.log('  ' + typeName + ': ' + runsWithViolation + '/' + allRuns.length + ' runs (' + total + ' total, avg ' + avg + '/run) <- ' + label);
    }

    // Per-run breakdown
    console.log('\n  Per-run breakdown:');
    for (let i = 0; i < allRuns.length; i++) {
      const run = allRuns[i][athlete] || {};
      const totalViolations = VIOLATION_TYPES.reduce((sum, t) => sum + (run[t] || 0), 0);
      const details = VIOLATION_TYPES.filter(t => (run[t] || 0) > 0).map(t => t + ':' + run[t]).join(', ');
      console.log('    Run ' + (i + 1) + ': ' + totalViolations + ' violations' + (details ? ' (' + details + ')' : ' (clean)'));
    }
  }
}

if (require.main === module) {
  runCli();
}

module.exports = { labelStability, VIOLATION_TYPES };
