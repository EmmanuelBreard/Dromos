// Validates the markdown macro plan output from Step 1
// Parses the compact MD format and checks coaching quality

module.exports = (output, context) => {
  const errors = [];
  const warnings = [];

  const weeklyHoursBudget = parseFloat(context.vars.weekly_hours);

  // Normalize line endings
  const text = output.replace(/\r\n/g, '\n');

  // More resilient regex: allow various dash types, flexible whitespace, optional newlines
  const weekPattern = /## W(\d+)\s*[-–—]+\s*(Base|Build|Peak|Taper|Recovery)\s*[-–—]+\s*(\S+)\s*\n\s*Total:\s*([\d.]+)h/gi;
  const weeks = [];
  let match;

  while ((match = weekPattern.exec(text)) !== null) {
    weeks.push({
      week_number: parseInt(match[1]),
      phase: match[2],
      start_date: match[3],
      total_hours: parseFloat(match[4])
    });
  }

  if (weeks.length === 0) {
    // Debug: show first 500 chars to understand the format
    const preview = text.substring(0, 500);
    return { pass: false, score: 0, reason: `Could not parse any week blocks.\nFirst 500 chars:\n${preview}` };
  }

  if (weeks.length < 4) {
    errors.push(`Plan only has ${weeks.length} weeks — too short`);
  }

  // Detect recovery by either phase label OR volume drop ≥25% from previous week
  function isRecoveryWeek(w, idx) {
    if (w.phase === 'Recovery') return true;
    if (idx > 0) {
      const prev = weeks[idx - 1];
      const drop = (prev.total_hours - w.total_hours) / prev.total_hours;
      if (drop >= 0.25) return true;
    }
    return false;
  }

  // Check each week
  let prevNonRecoveryHours = 0;
  let loadWeeksInRow = 0;
  let hasRecoveryWeek = false;
  let hasTaper = false;

  for (let i = 0; i < weeks.length; i++) {
    const w = weeks[i];
    const isRecovery = isRecoveryWeek(w, i);

    // Check total hours within budget (+20% tolerance)
    if (w.total_hours > weeklyHoursBudget * 1.2) {
      errors.push(`W${w.week_number}: ${w.total_hours}h exceeds budget of ${weeklyHoursBudget}h (+20% tolerance)`);
    }

    // Check progressive overload — only between consecutive load weeks
    if (prevNonRecoveryHours > 0 && !isRecovery && w.phase !== 'Taper') {
      const increase = (w.total_hours - prevNonRecoveryHours) / prevNonRecoveryHours;
      if (increase > 0.20) {
        warnings.push(`W${w.week_number}: ${(increase * 100).toFixed(0)}% volume jump from last load week`);
      }
    }

    // Track load/recovery pattern
    if (isRecovery || w.phase === 'Taper') {
      if (isRecovery) hasRecoveryWeek = true;
      if (w.phase === 'Taper') hasTaper = true;
      loadWeeksInRow = 0;
    } else {
      loadWeeksInRow++;
      // Allow up to 5 consecutive load weeks (e.g. steady peak block is fine)
      if (loadWeeksInRow > 5) {
        warnings.push(`W${w.week_number}: ${loadWeeksInRow} consecutive load weeks without recovery or taper`);
      }
      prevNonRecoveryHours = w.total_hours;
    }
  }

  // Global checks
  if (!hasRecoveryWeek && weeks.length > 8) {
    errors.push('No recovery week found in a plan longer than 8 weeks (neither labeled nor detected by ≥25% volume drop)');
  }
  if (!hasTaper) {
    errors.push('No taper phase before race');
  }

  // Check phase ordering
  const phases = weeks.map(w => w.phase);
  const lastPhase = phases[phases.length - 1];
  if (lastPhase !== 'Taper' && lastPhase !== 'Recovery') {
    warnings.push(`Last week phase is "${lastPhase}" — expected Taper or Recovery`);
  }

  // Check sessions exist per week by looking for sport lines
  const weekBlocks = text.split(/## W\d+/);
  for (let i = 1; i < weekBlocks.length; i++) {
    const block = weekBlocks[i];
    if (!block.includes('- Swim:') && !block.includes('- Bike:') && !block.includes('- Run:')) {
      warnings.push(`W${i}: missing sport session lines`);
    }
  }

  // Score
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
    reason: allIssues.length > 0 ? allIssues.join('\n') : `All checks passed (${weeks.length} weeks parsed)`
  };
};
