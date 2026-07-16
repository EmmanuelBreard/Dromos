// check-step3-violations.js — Step 3 (final plan) constraint checker
//
// Exports a pure `scorePlan(evalPlan, scenarioVars)` — the 8-metric violation scorer
// used by both the CLI (batch promptfoo output files) and the DRO-311 eval harness
// runners (which score DB-materialized plans via `db-plan-to-eval-shape.js`).
// scorePlan takes constraints entirely from the passed `scenarioVars` (the same
// `vars` shape as `vars/athletes.yaml` rows: day durations, swim/bike/run_days as
// comma-separated day-name strings, weekly_hours) — it never reads athletes.yaml
// itself, so it works identically for promptfoo-config scenarios and for harness-
// generated ones that never touch that file.
//
// CLI usage (unchanged): `node check-step3-violations.js <file>` — reads a batch
// output file (array of `{ output, athlete_name }`), resolves each record's vars
// from vars/athletes.yaml by athlete_name, and prints per-athlete violation detail
// plus a machine-readable `__SUMMARY_JSON__` summary line for aggregate-violations.js.

const fs = require('fs');
const path = require('path');
const yaml = require('js-yaml');

const dayNames = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

// Hard violations block a plan from being usable (safety/schedule-breaking).
// Soft violations degrade quality but don't make the plan unfollowable.
const HARD_VIOLATIONS = ['duration', 'sport', 'rest', 'sameday', 'brickorder'];
const SOFT_VIOLATIONS = ['brick', 'cluster', 'intensity'];

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

/**
 * Pure scoring function: given one eval-shaped plan and its athlete's scenario vars,
 * returns the 8-metric violation-count summary (same keys as the legacy
 * __SUMMARY_JSON__ output). Prints the same per-violation detail lines + a per-plan
 * TOTAL line as the original inline checker did, so CLI output is unchanged.
 *
 * @param {{weeks: Array}} evalPlan - `{ weeks: [{ week_number, phase, sessions: [{ day, sport, type, duration_minutes, is_brick }] }] }`
 *   (the shape both `run-step3-blocks.js` output and `db-plan-to-eval-shape.js` produce)
 * @param {object} scenarioVars - the athlete's `vars` (day durations, swim/bike/run_days
 *   as comma-separated day-name strings, weekly_hours) — same shape as an
 *   `vars/athletes.yaml` row's `vars`. NOT read from disk here.
 * @returns {{duration:number, sport:number, rest:number, brick:number, cluster:number, sameday:number, intensity:number, brickorder:number}}
 */
function scorePlan(evalPlan, scenarioVars, { log = false } = {}) {
  // Detail lines are opt-in: the CLI passes log:true; harness runners call scorePlan
  // many times and consume the returned summary, so they leave logging off.
  const emit = log ? (m) => process.stdout.write(m + '\n') : () => {};
  const { dayCaps: caps, sportEligibility: eligible, weeklyHours } = parseConstraintsFromVars(scenarioVars);

  let durationViolations = 0;
  let sportViolations = 0;
  let restViolations = 0;
  let missingBricks = 0;
  let clusterViolations = 0;
  let sameDayViolations = 0;
  let intensityViolations = 0;
  let brickOrderViolations = 0;

  for (const w of evalPlan.weeks) {
    const byDay = {};
    for (const s of w.sessions || []) {
      byDay[s.day] = byDay[s.day] || [];
      byDay[s.day].push(s);
    }

    for (const [day, sessions] of Object.entries(byDay)) {
      const total = sessions.reduce((s, x) => s + x.duration_minutes, 0);
      const cap = caps[day] || 0;

      if (cap === 0) {
        emit('  W' + w.week_number + ' ' + day + ': REST DAY VIOLATION (' + sessions.length + ' sessions)');
        restViolations++;
        continue;
      }

      const TRIGGER_MARGIN = 1.1; // Match 10% tolerance from fixDurationCaps
      if (total > cap * TRIGGER_MARGIN) {
        emit('  W' + w.week_number + ' ' + day + ': ' + total + 'min > ' + Math.round(cap * TRIGGER_MARGIN) + 'min cap+10% (' + sessions.map(s => s.sport + ' ' + s.duration_minutes).join(' + ') + ')');
        durationViolations++;
      }

      const eligibleSports = eligible[day] || [];
      for (const s of sessions) {
        if (!eligibleSports.includes(s.sport)) {
          emit('  W' + w.week_number + ' ' + day + ': ' + s.sport + ' NOT eligible on ' + day + ' (allowed: ' + eligibleSports.join(',') + ')');
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
        emit('  W' + w.week_number + ' (' + w.phase + '): NO BRICK SESSION (expected in Build/Peak/Base-even)');
        missingBricks++;
      }
    }

    // Check for sport clustering on single-session days
    // Skip for high-volume athletes (>= 8h/week) — consecutive same-sport days are expected
    if ((weeklyHours || 0) < 8) {
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
            emit('  W' + w.week_number + ' ' + d1 + '→' + d2 + ': SPORT CLUSTERING (' + sport1 + ' on consecutive single-session days)');
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
          emit('  W' + w.week_number + ' ' + day + ': SAME-DAY CONFLICT (' + sportSessions.length + ' ' + sport + ' sessions on same day)');
          sameDayViolations++;
        }
      }
      // Rule 2: Two hard (bike/run) sessions on same day (brick hard sessions count)
      const hardBikeRun = sessions.filter(s => HARD_TYPES_SD.includes(s.type) && ['bike', 'run'].includes(s.sport));
      if (hardBikeRun.length >= 2) {
        emit('  W' + w.week_number + ' ' + day + ': DUAL HARD CONFLICT (' + hardBikeRun.map(s => s.sport + ' ' + s.type).join(' + ') + ')');
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
            emit('  W' + w.week_number + ' ' + day + ': BRICK ORDER (run before bike)');
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
        emit('  W' + w.week_number + ' ' + d1.day + '→' + d2.day + ': INTENSITY CLUSTERING (' + reason + ')');
        intensityViolations++;
      }
    }
  }

  emit('  TOTAL: ' + durationViolations + ' duration cap, ' + sportViolations + ' sport eligibility, ' + restViolations + ' rest day, ' + missingBricks + ' missing brick, ' + clusterViolations + ' sport clustering, ' + sameDayViolations + ' same-day conflict, ' + intensityViolations + ' intensity, ' + brickOrderViolations + ' brick order violations');

  return {
    duration: durationViolations,
    sport: sportViolations,
    rest: restViolations,
    brick: missingBricks,
    cluster: clusterViolations,
    sameday: sameDayViolations,
    intensity: intensityViolations,
    brickorder: brickOrderViolations,
  };
}

// ─── CLI wrapper (unchanged behavior): reads a batch file, resolves each record's
//     vars from vars/athletes.yaml by athlete_name, calls scorePlan, prints as before ───
function runCli(inputFile) {
  const data = JSON.parse(fs.readFileSync(inputFile, 'utf8'));

  const athletesRaw = fs.readFileSync(path.join(__dirname, 'vars', 'athletes.yaml'), 'utf8');
  const athleteProfiles = yaml.load(athletesRaw);
  const varsByName = {};
  for (const a of athleteProfiles) varsByName[a.vars.athlete_name] = a.vars;

  const summary = {};

  for (const r of data) {
    const plan = JSON.parse(r.output);
    const name = r.athlete_name;
    const vars = varsByName[name];
    if (!vars) {
      console.warn(`No vars/athletes.yaml entry found for athlete_name="${name}" — skipping`);
      continue;
    }

    console.log('\n=== ' + name + ' ===');
    summary[name] = scorePlan(plan, vars, { log: true });
  }

  // Machine-readable summary for aggregate-violations.js
  console.log('\n__SUMMARY_JSON__' + JSON.stringify(summary));
}

if (require.main === module) {
  const inputFile = process.argv[2] || path.join(__dirname, 'results', 'step3-blocks.json');
  runCli(inputFile);
}

module.exports = { scorePlan, HARD_VIOLATIONS, SOFT_VIOLATIONS };
