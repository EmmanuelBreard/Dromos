// Validates the macro plan output from Step 1
// Used by promptfoo as a custom assertion

module.exports = (output, context) => {
  const errors = [];
  const warnings = [];

  // Parse JSON from the output (handle markdown code fences)
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

  const weeklyHoursBudget = parseFloat(context.vars.weekly_hours);
  const weeks = plan.weeks;

  // 1. Check week count is reasonable (at least 4 weeks)
  if (weeks.length < 4) {
    errors.push(`Plan only has ${weeks.length} weeks — too short`);
  }

  // 2. Check each week
  let prevHours = 0;
  let loadWeeksInRow = 0;
  let hasRecoveryWeek = false;
  let hasTaper = false;

  for (let i = 0; i < weeks.length; i++) {
    const w = weeks[i];
    const wn = w.week_number || i + 1;

    // Check total hours within budget (+20% tolerance)
    if (w.total_hours > weeklyHoursBudget * 1.2) {
      errors.push(`Week ${wn}: ${w.total_hours}h exceeds budget of ${weeklyHoursBudget}h (+20% tolerance)`);
    }

    // Check sport hours add up
    const sportSum = (w.swim?.hours || 0) + (w.bike?.hours || 0) + (w.run?.hours || 0);
    if (Math.abs(sportSum - w.total_hours) > 0.5) {
      warnings.push(`Week ${wn}: sport hours (${sportSum.toFixed(1)}) don't match total (${w.total_hours})`);
    }

    // Check progressive overload (not more than 15% jump)
    if (prevHours > 0 && w.phase !== 'Recovery' && w.phase !== 'Taper') {
      const increase = (w.total_hours - prevHours) / prevHours;
      if (increase > 0.20) {
        warnings.push(`Week ${wn}: ${(increase * 100).toFixed(0)}% volume jump from previous week`);
      }
    }

    // Track load/recovery pattern
    if (w.phase === 'Recovery') {
      hasRecoveryWeek = true;
      loadWeeksInRow = 0;
    } else if (w.phase === 'Taper') {
      hasTaper = true;
    } else {
      loadWeeksInRow++;
      if (loadWeeksInRow > 4) {
        warnings.push(`Week ${wn}: ${loadWeeksInRow} consecutive load weeks without recovery`);
      }
    }

    // Check sessions exist
    for (const sport of ['swim', 'bike', 'run']) {
      if (w[sport]?.hours > 0 && (!w[sport]?.sessions || w[sport].sessions.length === 0)) {
        errors.push(`Week ${wn}: ${sport} has ${w[sport].hours}h but no sessions`);
      }
    }

    prevHours = w.total_hours;
  }

  // 3. Global checks
  if (!hasRecoveryWeek && weeks.length > 6) {
    errors.push('No recovery week found in a plan longer than 6 weeks');
  }
  if (!hasTaper) {
    errors.push('No taper phase before race');
  }

  // Check phase ordering makes sense
  const phases = weeks.map(w => w.phase);
  const lastPhase = phases[phases.length - 1];
  if (lastPhase !== 'Taper' && lastPhase !== 'Recovery') {
    warnings.push(`Last week phase is "${lastPhase}" — expected Taper or Recovery`);
  }

  // Score: start at 1.0, deduct for errors and warnings
  let score = 1.0;
  score -= errors.length * 0.15;
  score -= warnings.length * 0.05;
  score = Math.max(0, Math.min(1, score));

  const allIssues = [
    ...errors.map(e => `ERROR: ${e}`),
    ...warnings.map(w => `WARN: ${w}`)
  ];

  return {
    pass: errors.length === 0,
    score,
    reason: allIssues.length > 0 ? allIssues.join('\n') : 'All checks passed'
  };
};
