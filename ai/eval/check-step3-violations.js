// Check Step 3 outputs for constraint violations
const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const inputFile = process.argv[2] || path.join(__dirname, 'results', 'step3-blocks.json');
const data = JSON.parse(fs.readFileSync(inputFile, 'utf8'));

// Load athletes.yaml and parse constraints dynamically (replaces hardcoded maps)
const athletesRaw = fs.readFileSync(path.join(__dirname, 'vars', 'athletes.yaml'), 'utf8');
const athleteProfiles = yaml.load(athletesRaw);

const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

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

  return { dayCaps, sportEligibility, weeklyHours: parseInt(vars.weekly_hours || '0', 10) };
}

// Build constraint maps keyed by athlete name
const allDayCaps = {};
const allSportEligibility = {};
const allWeeklyHours = {};
for (const a of athleteProfiles) {
  const { dayCaps, sportEligibility, weeklyHours } = parseConstraintsFromVars(a.vars);
  allDayCaps[a.vars.athlete_name] = dayCaps;
  allSportEligibility[a.vars.athlete_name] = sportEligibility;
  allWeeklyHours[a.vars.athlete_name] = weeklyHours;
}

const summary = {};

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
  let sameDayViolations = 0;
  let intensityViolations = 0;
  let brickOrderViolations = 0;

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

    // Check for brick sessions in Build/Peak weeks and even-numbered Base weeks
    const expectsBrick =
      w.phase === 'Build' || w.phase === 'Peak' ||
      (w.phase === 'Base' && w.week_number % 2 === 0);
    if (expectsBrick) {
      const hasBrick = (w.sessions || []).some(s => s.is_brick);
      if (!hasBrick) {
        console.log('  W' + w.week_number + ' (' + w.phase + '): NO BRICK SESSION (expected in Build/Peak/Base-even)');
        missingBricks++;
      }
    }

    // Check for sport clustering on single-session days
    // Skip for high-volume athletes (>= 8h/week) — consecutive same-sport days are expected
    if ((allWeeklyHours[name] || 0) < 8) {
      const singleSessionDays = dayNames.filter(day => {
        const cap = caps[day] || 0;
        const daySessions = byDay[day] || [];
        return cap > 0 && daySessions.length === 1;
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

    // Check for same-day conflicts (bike/run only, swim exempt)
    const HARD_TYPES_SD = ['Tempo', 'Intervals'];
    for (const [day, sessions] of Object.entries(byDay)) {
      // Rule 1: Max 1 bike and max 1 run per day (brick sessions count)
      for (const sport of ['bike', 'run']) {
        const sportSessions = sessions.filter(s => s.sport === sport);
        if (sportSessions.length >= 2) {
          console.log('  W' + w.week_number + ' ' + day + ': SAME-DAY CONFLICT (' + sportSessions.length + ' ' + sport + ' sessions on same day)');
          sameDayViolations++;
        }
      }
      // Rule 2: Two hard (bike/run) sessions on same day (brick hard sessions count)
      const hardBikeRun = sessions.filter(s => HARD_TYPES_SD.includes(s.type) && ['bike', 'run'].includes(s.sport));
      if (hardBikeRun.length >= 2) {
        console.log('  W' + w.week_number + ' ' + day + ': DUAL HARD CONFLICT (' + hardBikeRun.map(s => s.sport + ' ' + s.type).join(' + ') + ')');
        sameDayViolations++;
      }
      // Brick order: bike must come before run in sessions array
      const brickSessions = sessions.filter(s => s.is_brick);
      if (brickSessions.length >= 2) {
        const brickBike = brickSessions.find(s => s.sport === 'bike');
        const brickRun = brickSessions.find(s => s.sport === 'run');
        if (brickBike && brickRun) {
          const bikeIdx = (w.sessions || []).indexOf(brickBike);
          const runIdx = (w.sessions || []).indexOf(brickRun);
          if (runIdx < bikeIdx) {
            console.log('  W' + w.week_number + ' ' + day + ': BRICK ORDER (run before bike)');
            brickOrderViolations++;
          }
        }
      }
    }

    // Check for consecutive hard days (Tempo/Intervals) — bike/run only, swim excluded
    // Relaxed rule: 2 consecutive of DIFFERENT sports is OK. Violations are:
    //   - Same sport on consecutive hard days (always bad)
    //   - 3+ consecutive hard days (always bad)
    const HARD_TYPES = ['Tempo', 'Intervals'];
    const hardDayInfo = dayNames.map(day => {
      const sessions = byDay[day] || [];
      const hardSports = sessions
        .filter(s => HARD_TYPES.includes(s.type) && s.sport !== 'swim')
        .map(s => s.sport);
      return { day, hardSports };
    }).filter(d => d.hardSports.length > 0);

    // Density check: available_days / hard_sessions. If >= 2, consecutive is spreadable
    const availableDays = dayNames.filter(day => (caps[day] || 0) > 0).length;
    const numHardSessions = hardDayInfo.length;
    const canSpread = numHardSessions > 0 && (availableDays / numHardSessions) >= 2;

    for (let j = 0; j < hardDayInfo.length - 1; j++) {
      const d1 = hardDayInfo[j];
      const d2 = hardDayInfo[j + 1];
      if (dayNames.indexOf(d2.day) !== dayNames.indexOf(d1.day) + 1) continue;

      const sameSport = d1.hardSports.some(s => d2.hardSports.includes(s));
      const prevIsHard = j > 0 && dayNames.indexOf(hardDayInfo[j - 1].day) === dayNames.indexOf(d1.day) - 1;
      const nextIsHard = j + 2 < hardDayInfo.length && dayNames.indexOf(hardDayInfo[j + 2].day) === dayNames.indexOf(d2.day) + 1;
      const is3Plus = prevIsHard || nextIsHard;

      // Always violation: same sport consecutive or 3+ consecutive
      // Conditional violation: different-sport consecutive when density allows spreading
      if (sameSport || is3Plus || canSpread) {
        const reason = sameSport
          ? 'same sport (' + d1.hardSports.filter(s => d2.hardSports.includes(s)).join(',') + ')'
          : is3Plus ? '3+ consecutive hard days'
          : 'spreadable (' + availableDays + ' days / ' + numHardSessions + ' hard)';
        console.log('  W' + w.week_number + ' ' + d1.day + '→' + d2.day + ': INTENSITY CLUSTERING (' + reason + ')');
        intensityViolations++;
      }
    }
  }
  console.log('  TOTAL: ' + durationViolations + ' duration cap, ' + sportViolations + ' sport eligibility, ' + restViolations + ' rest day, ' + missingBricks + ' missing brick, ' + clusterViolations + ' sport clustering, ' + sameDayViolations + ' same-day conflict, ' + intensityViolations + ' intensity, ' + brickOrderViolations + ' brick order violations');

  summary[name] = {
    duration: durationViolations,
    sport: sportViolations,
    rest: restViolations,
    brick: missingBricks,
    cluster: clusterViolations,
    sameday: sameDayViolations,
    intensity: intensityViolations,
    brickorder: brickOrderViolations
  };
}

// Machine-readable summary for aggregate-violations.js
console.log('\n__SUMMARY_JSON__' + JSON.stringify(summary));
