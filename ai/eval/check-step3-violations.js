// Check Step 3 outputs for constraint violations
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const data = JSON.parse(fs.readFileSync(path.join(__dirname, 'results', 'step3-blocks.json'), 'utf8'));

// Load athletes.yaml and parse constraints dynamically (replaces hardcoded maps)
const athletesRaw = fs.readFileSync(path.join(__dirname, 'vars', 'athletes.yaml'), 'utf8');
const athleteProfiles = yaml.load(athletesRaw);

const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
const SINGLE_SESSION_CAP = 75; // Days with ≤75min are single-session; enforce sport alternation

function parseConstraintsFromVars(vars) {
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
  let missingBricks = 0;
  let clusterViolations = 0;

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

      const TRIGGER_MARGIN = 1.1; // Match 10% tolerance from fixDurationCaps
      if (total > cap * TRIGGER_MARGIN) {
        console.log('  W' + w.week_number + ' ' + day + ': ' + total + 'min > ' + Math.round(cap * TRIGGER_MARGIN) + 'min cap+10% (' + sessions.map(s => s.sport + ' ' + s.duration_minutes).join(' + ') + ')');
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

    // Check for brick sessions in Build/Peak weeks
    if (w.phase === 'Build' || w.phase === 'Peak') {
      const hasBrick = (w.sessions || []).some(s => s.is_brick);
      if (!hasBrick) {
        console.log('  W' + w.week_number + ' (' + w.phase + '): NO BRICK SESSION (expected in Build/Peak)');
        missingBricks++;
      }
    }

    // Check for sport clustering on single-session days
    const singleSessionDays = dayNames.filter(day => {
      const cap = caps[day] || 0;
      const daySessions = byDay[day] || [];
      return cap > 0 && cap <= SINGLE_SESSION_CAP && daySessions.length === 1;
    });

    // Check consecutive single-session days for same sport
    for (let j = 0; j < singleSessionDays.length - 1; j++) {
      const d1 = singleSessionDays[j];
      const d2 = singleSessionDays[j + 1];
      const d1Idx = dayNames.indexOf(d1);
      const d2Idx = dayNames.indexOf(d2);
      if (d2Idx === d1Idx + 1) {
        const sport1 = byDay[d1][0].sport;
        const sport2 = byDay[d2][0].sport;
        if (sport1 === sport2) {
          console.log('  W' + w.week_number + ' ' + d1 + '→' + d2 + ': SPORT CLUSTERING (' + sport1 + ' on consecutive single-session days)');
          clusterViolations++;
        }
      }
    }
  }
  console.log('  TOTAL: ' + durationViolations + ' duration cap, ' + sportViolations + ' sport eligibility, ' + restViolations + ' rest day, ' + missingBricks + ' missing brick, ' + clusterViolations + ' sport clustering violations');
}
