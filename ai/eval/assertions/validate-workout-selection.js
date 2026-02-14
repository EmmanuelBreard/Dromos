// Validates workout selection output from Step 3
// Checks template_ids, sport/type matching, brick sessions, variety, coverage

const fs = require('fs');
const path = require('path');

// Load workout library to get valid template IDs and metadata
const libraryPath = path.join(__dirname, '..', '..', 'context', 'workout-library.json');
let VALID_IDS;
let TEMPLATE_META = {}; // template_id -> { sport, type, total_duration }
let CATEGORY_COUNTS = {}; // "bike_Easy" -> 6 (how many templates per sport/type)

try {
  const lib = JSON.parse(fs.readFileSync(libraryPath, 'utf8'));
  VALID_IDS = new Set();
  for (const sport of ['swim', 'bike', 'run']) {
    if (lib[sport]) {
      lib[sport].forEach(w => {
        VALID_IDS.add(w.template_id);
        const type = w.template_id.split('_')[1];
        const totalMin = (w.segments || []).reduce((sum, s) => sum + (s.duration_minutes || 0), 0);
        TEMPLATE_META[w.template_id] = { sport, type, total_duration: totalMin };
        const cat = `${sport}_${type}`;
        CATEGORY_COUNTS[cat] = (CATEGORY_COUNTS[cat] || 0) + 1;
      });
    }
  }
} catch (e) {
  VALID_IDS = new Set();
}

// Map template_id prefix to expected sport
const PREFIX_TO_SPORT = { 'SWIM': 'swim', 'BIKE': 'bike', 'RUN': 'run' };

// Normalize day names (macro plan may use "Mon" or "Monday")
const DAY_NORMALIZE = {
  'mon': 'Monday', 'monday': 'Monday',
  'tue': 'Tuesday', 'tues': 'Tuesday', 'tuesday': 'Tuesday',
  'wed': 'Wednesday', 'wednesday': 'Wednesday',
  'thu': 'Thursday', 'thur': 'Thursday', 'thurs': 'Thursday', 'thursday': 'Thursday',
  'fri': 'Friday', 'friday': 'Friday',
  'sat': 'Saturday', 'saturday': 'Saturday',
  'sun': 'Sunday', 'sunday': 'Sunday'
};
function normalizeDay(d) { return DAY_NORMALIZE[(d || '').toLowerCase()] || d; }

module.exports = (output, context) => {
  const errors = [];
  const warnings = [];

  // Parse output
  let plan;
  try {
    const jsonStr = output.replace(/```json\n?/g, '').replace(/```\n?/g, '').trim();
    plan = JSON.parse(jsonStr);
  } catch (e) {
    return { pass: false, score: 0, reason: `Invalid JSON: ${e.message}` };
  }

  if (!plan.weeks || !Array.isArray(plan.weeks)) {
    return { pass: false, score: 0, reason: 'Missing "weeks" array' };
  }

  // Parse macro plan to check session coverage
  let macroPlan;
  try {
    const macroStr = (context.vars.macro_plan_json || '').trim();
    macroPlan = JSON.parse(macroStr);
  } catch (e) {
    // Can't compare coverage without macro plan — skip that check
    macroPlan = null;
  }

  const usedPerWeek = {};
  const globalUsage = {};
  let totalSessions = 0;
  let totalBrickPairs = 0;

  for (const week of plan.weeks) {
    const wn = week.week_number;
    usedPerWeek[wn] = [];

    if (!week.sessions || !Array.isArray(week.sessions)) {
      errors.push(`W${wn}: missing sessions array`);
      continue;
    }

    // Group sessions by day for brick and scheduling checks
    const sessionsByDay = {};
    const brickSessionsByDay = {};

    for (const session of week.sessions) {
      const tid = session.template_id;
      totalSessions++;

      // 1. Check template_id exists
      if (!VALID_IDS.has(tid)) {
        errors.push(`W${wn}: template_id "${tid}" does not exist in library`);
        continue;
      }

      // 2. Check sport matches prefix
      const prefix = tid.split('_')[0];
      const expectedSport = PREFIX_TO_SPORT[prefix];
      if (expectedSport && session.sport !== expectedSport) {
        errors.push(`W${wn}: ${tid} is ${expectedSport} but session says ${session.sport}`);
      }

      // 3. Check type matches template_id (type field must match the template's type)
      const tidType = tid.split('_')[1]?.toLowerCase();
      const sessionType = session.type?.toLowerCase();
      if (tidType && sessionType && tidType !== sessionType) {
        errors.push(`W${wn}: ${tid} is type "${tidType}" but session says "${sessionType}"`);
      }

      // 4. Check day is valid
      const validDays = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];
      if (!validDays.includes(session.day)) {
        errors.push(`W${wn}: invalid day "${session.day}"`);
      }

      // Track by day
      if (session.day) {
        sessionsByDay[session.day] = sessionsByDay[session.day] || [];
        sessionsByDay[session.day].push(session);
      }

      // Track bricks
      if (session.is_brick) {
        brickSessionsByDay[session.day] = brickSessionsByDay[session.day] || [];
        brickSessionsByDay[session.day].push(session);
      }

      // Track variety
      usedPerWeek[wn].push(tid);
      globalUsage[tid] = (globalUsage[tid] || 0) + 1;
    }

    // 5. Validate brick sessions per day
    for (const [day, brickSessions] of Object.entries(brickSessionsByDay)) {
      const sports = brickSessions.map(s => s.sport);
      const hasBike = sports.includes('bike');
      const hasRun = sports.includes('run');

      if (!hasBike || !hasRun) {
        errors.push(`W${wn} ${day}: brick sessions must include both bike and run (found: ${sports.join(', ')})`);
      } else {
        totalBrickPairs++;
      }

      if (brickSessions.length > 2) {
        warnings.push(`W${wn} ${day}: ${brickSessions.length} brick sessions — expected exactly 2`);
      }
    }

    // 6. Check no more than 2 sessions per day (3 if brick pair + 1)
    for (const [day, daySessions] of Object.entries(sessionsByDay)) {
      if (daySessions.length > 3) {
        warnings.push(`W${wn} ${day}: ${daySessions.length} sessions on one day`);
      }
    }
  }

  // 7. Check session coverage and rest days against macro plan
  if (macroPlan && macroPlan.weeks) {
    for (const macroWeek of macroPlan.weeks) {
      const wn = macroWeek.week_number;
      const selectionWeek = plan.weeks.find(w => w.week_number === wn);

      if (!selectionWeek) {
        errors.push(`W${wn}: week from macro plan is missing in workout selection`);
        continue;
      }

      // Count expected sessions per sport
      for (const sport of ['swim', 'bike', 'run']) {
        const expectedCount = macroWeek[sport]?.sessions?.length || 0;
        const actualCount = (selectionWeek.sessions || []).filter(s => s.sport === sport).length;

        if (expectedCount > 0 && actualCount === 0) {
          errors.push(`W${wn}: macro plan has ${expectedCount} ${sport} sessions but selection has none`);
        } else if (Math.abs(expectedCount - actualCount) > 1) {
          warnings.push(`W${wn}: macro plan has ${expectedCount} ${sport} sessions, selection has ${actualCount}`);
        }
      }

      // Check rest days are respected (normalize abbreviated day names)
      const restDays = (macroWeek.rest_days || []).map(normalizeDay);
      if (restDays.length > 0 && selectionWeek.sessions) {
        for (const session of selectionWeek.sessions) {
          const sessionDay = normalizeDay(session.day);
          if (restDays.includes(sessionDay)) {
            errors.push(`W${wn}: session on ${sessionDay} violates rest day`);
          }
        }
      }
    }
  }

  // 8. Check variety — Tempo/Intervals only (Easy is exempt from rotation)
  const weekNums = Object.keys(usedPerWeek).map(Number).sort((a, b) => a - b);

  // Build per-week sport/type → template map for consecutive check (Tempo & Intervals only)
  const weekSportTypeMap = {};
  for (const week of plan.weeks) {
    const wn = week.week_number;
    weekSportTypeMap[wn] = {};
    for (const session of (week.sessions || [])) {
      if (session.type === 'Easy') continue; // Easy exempt from variety checks
      const key = `${session.sport}_${session.type}`;
      if (!weekSportTypeMap[wn][key]) weekSportTypeMap[wn][key] = [];
      weekSportTypeMap[wn][key].push(session.template_id);
    }
  }

  let consecutiveRepeatCount = 0;
  for (let i = 1; i < weekNums.length; i++) {
    const prevMap = weekSportTypeMap[weekNums[i - 1]] || {};
    const currMap = weekSportTypeMap[weekNums[i]] || {};
    for (const key of Object.keys(currMap)) {
      if (prevMap[key]) {
        const prevSet = new Set(prevMap[key]);
        const repeated = currMap[key].filter(t => prevSet.has(t));
        if (repeated.length > 0) {
          consecutiveRepeatCount += repeated.length;
        }
      }
    }
  }
  // Allow some consecutive repeats (e.g. small library categories) but flag excessive
  if (consecutiveRepeatCount > weekNums.length * 0.3) {
    errors.push(`Excessive consecutive-week Tempo/Intervals repeats: ${consecutiveRepeatCount} template reuses across ${weekNums.length} week transitions`);
  } else if (consecutiveRepeatCount > weekNums.length * 0.15) {
    warnings.push(`${consecutiveRepeatCount} consecutive-week Tempo/Intervals template repeats — aim for more rotation`);
  }

  // 9. Check global variety — Tempo/Intervals only (Easy exempt)
  // Group usage by category (sport_type)
  const categoryUsage = {}; // "bike_Tempo" -> { "BIKE_Tempo_01": 5, "BIKE_Tempo_02": 1, ... }
  for (const [tid, count] of Object.entries(globalUsage)) {
    const meta = TEMPLATE_META[tid];
    if (!meta) continue;
    if (meta.type === 'Easy') continue; // Easy exempt from variety checks
    const cat = `${meta.sport}_${meta.type}`;
    if (!categoryUsage[cat]) categoryUsage[cat] = {};
    categoryUsage[cat][tid] = count;
  }

  for (const [cat, usage] of Object.entries(categoryUsage)) {
    const totalInCategory = Object.values(usage).reduce((a, b) => a + b, 0);
    const availableTemplates = CATEGORY_COUNTS[cat] || 1;

    for (const [tid, count] of Object.entries(usage)) {
      const share = count / totalInCategory;
      // If category has 6+ templates and one is used >40% of the time → error
      if (availableTemplates >= 4 && share > 0.4 && totalInCategory >= 6) {
        errors.push(`${tid} used ${count}/${totalInCategory} times (${(share*100).toFixed(0)}%) — ${availableTemplates} templates available in ${cat}`);
      } else if (availableTemplates >= 3 && share > 0.5 && totalInCategory >= 4) {
        warnings.push(`${tid} used ${count}/${totalInCategory} times — low variety in ${cat}`);
      }
    }
  }

  // Score
  let score = 1.0;
  score -= errors.length * 0.1;
  score -= warnings.length * 0.03;
  score = Math.max(0, Math.min(1, score));

  const summary = [
    `${plan.weeks.length} weeks, ${totalSessions} sessions, ${totalBrickPairs} brick pairs`
  ];

  const allIssues = [
    ...errors.map(e => `ERROR: ${e}`),
    ...warnings.map(w => `WARN: ${w}`)
  ];

  return {
    pass: errors.length === 0,
    score,
    reason: allIssues.length > 0
      ? `${summary[0]}\n${allIssues.join('\n')}`
      : `All checks passed — ${summary[0]}`
  };
};
