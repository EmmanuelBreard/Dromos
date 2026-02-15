// Format step3-blocks.json as human-readable plan schedules
// Usage: node format-plan.js [results/batch/run-1.json] [--athlete "Emmanuel"]
const fs = require('fs');
const path = require('path');

const inputFile = process.argv[2] || path.join(__dirname, 'results', 'step3-blocks.json');
const athleteFilter = process.argv.indexOf('--athlete') !== -1
  ? process.argv[process.argv.indexOf('--athlete') + 1]
  : null;

const data = JSON.parse(fs.readFileSync(inputFile, 'utf8'));
const ALL_DAYS = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

for (const r of data) {
  const name = r.athlete_name;
  if (athleteFilter && !name.includes(athleteFilter)) continue;

  const plan = JSON.parse(r.output);
  console.log('\n' + '='.repeat(60));
  console.log('ATHLETE: ' + name);
  console.log('='.repeat(60));

  for (const w of plan.weeks) {
    console.log('\n--- Week ' + w.week_number + ' (' + w.phase + ') ---');

    const byDay = {};
    for (const s of w.sessions || []) {
      const day = s.day;
      byDay[day] = byDay[day] || [];
      byDay[day].push(s);
    }

    for (const day of ALL_DAYS) {
      const sessions = byDay[day] || [];
      if (sessions.length === 0) {
        console.log('  ' + day.substring(0, 3) + ': REST');
        continue;
      }

      // Sort brick sessions: bike before run (athlete does bike first, then transition run)
      const sorted = [...sessions].sort((a, b) => {
        if (a.is_brick && b.is_brick) {
          if (a.sport === 'bike' && b.sport === 'run') return -1;
          if (a.sport === 'run' && b.sport === 'bike') return 1;
        }
        return 0;
      });

      const parts = sorted.map(s => {
        let label = s.sport + ' ' + s.type + ' ' + s.duration_minutes + 'min (' + s.template_id + ')';
        if (s.is_brick) label += ' [brick]';
        return label;
      });

      console.log('  ' + day.substring(0, 3) + ': ' + parts.join(' + '));
    }

    // Week summary
    const totalMin = (w.sessions || []).reduce((sum, s) => sum + s.duration_minutes, 0);
    const sportTotals = {};
    for (const s of w.sessions || []) {
      sportTotals[s.sport] = (sportTotals[s.sport] || 0) + s.duration_minutes;
    }
    const sportStr = Object.entries(sportTotals).map(([k, v]) => k + ':' + v + 'min').join(', ');
    console.log('  TOTAL: ' + totalMin + 'min (' + (totalMin / 60).toFixed(1) + 'h) — ' + sportStr);
  }
}
