// Check Step 3 outputs for constraint violations
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const data = JSON.parse(fs.readFileSync(path.join(__dirname, 'results', 'step3-blocks.json'), 'utf8'));

// Load athletes.yaml and parse constraints dynamically (replaces hardcoded maps)
const athletesRaw = fs.readFileSync(path.join(__dirname, 'vars', 'athletes.yaml'), 'utf8');
const athleteProfiles = yaml.load(athletesRaw);

function parseConstraintsFromVars(vars) {
  const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
  const durationFields = ['mon_duration', 'tue_duration', 'wed_duration', 'thu_duration', 'fri_duration', 'sat_duration', 'sun_duration'];

  const parseDays = (s) => new Set((s || '').split(',').map(d => d.trim()).filter(Boolean));
  const swimDays = parseDays(vars.swim_days);
  const bikeDays = parseDays(vars.bike_days);
  const runDays = parseDays(vars.run_days);

  const dayCaps = {};
  const sportEligibility = {};

  for (let i = 0; i < dayNames.length; i++) {
    const day = dayNames[i];
    const duration = parseInt(vars[durationFields[i]] || '0', 10);
    dayCaps[day] = duration;

    const eligible = [];
    if (swimDays.has(day)) eligible.push('swim');
    if (bikeDays.has(day)) eligible.push('bike');
    if (runDays.has(day)) eligible.push('run');
    sportEligibility[day] = eligible;
  }

  return { dayCaps, sportEligibility };
}

// Build constraint maps keyed by athlete name
const allDayCaps = {};
const allSportEligibility = {};
for (const a of athleteProfiles) {
  const { dayCaps, sportEligibility } = parseConstraintsFromVars(a.vars);
  allDayCaps[a.vars.athlete_name] = dayCaps;
  allSportEligibility[a.vars.athlete_name] = sportEligibility;
}

for (const r of data) {
  const plan = JSON.parse(r.output);
  const name = r.athlete_name;
  const caps = allDayCaps[name];
  const eligible = allSportEligibility[name];
  let durationViolations = 0;
  let sportViolations = 0;
  let restViolations = 0;

  console.log('\n=== ' + name + ' ===');

  for (const w of plan.weeks) {
    const byDay = {};
    for (const s of w.sessions || []) {
      byDay[s.day] = byDay[s.day] || [];
      byDay[s.day].push(s);
    }

    for (const [day, sessions] of Object.entries(byDay)) {
      const total = sessions.reduce((s, x) => s + x.duration_minutes, 0);
      const cap = caps[day] || 0;

      if (cap === 0) {
        console.log('  W' + w.week_number + ' ' + day + ': REST DAY VIOLATION (' + sessions.length + ' sessions)');
        restViolations++;
        continue;
      }

      if (total > cap) {
        console.log('  W' + w.week_number + ' ' + day + ': ' + total + 'min > ' + cap + 'min cap (' + sessions.map(s => s.sport + ' ' + s.duration_minutes).join(' + ') + ')');
        durationViolations++;
      }

      const eligibleSports = eligible[day] || [];
      for (const s of sessions) {
        if (!eligibleSports.includes(s.sport)) {
          console.log('  W' + w.week_number + ' ' + day + ': ' + s.sport + ' NOT eligible on ' + day + ' (allowed: ' + eligibleSports.join(',') + ')');
          sportViolations++;
        }
      }
    }
  }
  console.log('  TOTAL: ' + durationViolations + ' duration cap, ' + sportViolations + ' sport eligibility, ' + restViolations + ' rest day violations');
}
