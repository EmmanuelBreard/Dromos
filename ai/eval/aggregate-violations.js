// Aggregate violation stats across N batch runs
// Usage: node aggregate-violations.js <N> [athlete_filter]
const fs = require('fs');
const path = require('path');

const N = parseInt(process.argv[2] || '5');
const athleteFilter = process.argv[3] || null;
const batchDir = path.join(__dirname, 'results', 'batch');

const VIOLATION_TYPES = ['duration', 'sport', 'rest', 'brick', 'cluster', 'sameday', 'intensity', 'brickorder'];

// Read all summary JSONs from violation outputs
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

    let label;
    if (runsWithViolation === 0) label = 'CLEAN';
    else if (runsWithViolation >= allRuns.length * 0.6) label = 'SYSTEMATIC';
    else if (runsWithViolation >= allRuns.length * 0.3) label = 'INVESTIGATE';
    else label = 'VARIANCE (OK)';

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
