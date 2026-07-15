// db-plan-to-eval-shape.js
// Adapter: converts a plan read from the DB (training_plans → plan_weeks → plan_sessions)
// into the shape that check-step3-violations.js consumes:
//   { weeks: [ { week_number, phase, sessions: [ { day, sport, type, duration_minutes, is_brick } ] } ] }
//
// This is the one genuinely new piece of glue between the deployed pipeline (DB output)
// and the existing deterministic checker (which was written against run-step3-blocks.js output).

/**
 * @param {object} dbPlan - a training_plans row with nested plan_weeks[].plan_sessions[]
 *   (as returned by: .select('*, plan_weeks(*, plan_sessions(*))'))
 * @returns {{weeks: Array}} eval-shaped plan
 */
function dbPlanToEvalShape(dbPlan) {
  const weeksRaw = dbPlan.plan_weeks || [];
  const weeks = weeksRaw
    .slice()
    .sort((a, b) => a.week_number - b.week_number)
    .map((w) => {
      const sessions = (w.plan_sessions || [])
        .slice()
        // preserve intra-day ordering so brick-order checks are meaningful
        .sort((a, b) => (a.order_in_day || 0) - (b.order_in_day || 0))
        .map((s) => ({
          day: s.day,
          sport: s.sport,
          type: s.type,
          duration_minutes: s.duration_minutes,
          is_brick: !!s.is_brick,
          template_id: s.template_id, // harmless extra; checker ignores unknown fields
        }));
      return {
        week_number: w.week_number,
        phase: w.phase,
        sessions,
      };
    });
  return { weeks };
}

module.exports = { dbPlanToEvalShape };
