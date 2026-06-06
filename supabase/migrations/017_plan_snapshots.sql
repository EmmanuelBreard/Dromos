-- Migration: plan_snapshots table + import_plan_atomic stored procedure
-- Description: Enables atomic plan import with rollback safety via snapshot.
-- Date: 2026-06-06
-- Related: DRO-299 (Phase 3 of DRO-296)

-- ============================================================================
-- UP MIGRATION
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Table: plan_snapshots
-- Stores a JSONB snapshot of the user's existing plan before it is replaced
-- by import_plan_atomic. Allows manual or automated rollback.
-- ---------------------------------------------------------------------------
CREATE TABLE public.plan_snapshots (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  snapshot   JSONB       NOT NULL,
  reason     TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE  public.plan_snapshots             IS 'Point-in-time snapshots of training plans taken before destructive import/replace operations.';
COMMENT ON COLUMN public.plan_snapshots.snapshot    IS 'Full plan state: {plan, weeks: [{...week, sessions:[...]}]}';
COMMENT ON COLUMN public.plan_snapshots.reason      IS 'Short slug identifying the trigger, e.g. "import-plan-replace".';

-- Index: fast lookup of a user's snapshot history (newest first)
CREATE INDEX idx_plan_snapshots_user_id_created_at
  ON public.plan_snapshots (user_id, created_at DESC);

-- RLS: enable + read-own-rows policy (writes are service_role only)
ALTER TABLE public.plan_snapshots ENABLE ROW LEVEL SECURITY;

CREATE POLICY "users read own snapshots"
  ON public.plan_snapshots
  FOR SELECT
  USING (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- Function: import_plan_atomic
--
-- Performs a transactional plan replace:
--   1. Reads + snapshots the existing training_plans / plan_weeks / plan_sessions
--      for the given user into plan_snapshots.
--   2. DELETEs the existing training_plans row (CASCADE cleans weeks + sessions).
--   3. INSERTs the new training_plans row.
--   4. INSERTs plan_weeks rows.
--   5. For each week, INSERTs plan_sessions rows (structure JSONB pre-materialised
--      by the Edge Function caller).
--   6. Applies optional profile_updates to public.users.
--   7. Returns a summary JSONB.
--
-- All work is done inside a single implicit Postgres transaction (plpgsql).
-- SECURITY DEFINER so service_role Edge Functions can call it without exposing
-- the service role key to every individual DML statement.
--
-- p_plan    : top-level plan fields (race_objective, race_date, start_date, total_weeks)
-- p_weeks   : array of weeks; each week has a "sessions" array with pre-materialised
--             "structure" JSONB already attached by the Edge Function.
-- p_profile_updates : optional JSONB with keys matching public.users columns.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.import_plan_atomic(
  p_user_id        UUID,
  p_plan           JSONB,
  p_weeks          JSONB,
  p_profile_updates JSONB DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_existing_plan_id   UUID;
  v_snapshot_id        UUID;
  v_new_plan_id        UUID;
  v_week_id            UUID;
  v_week               JSONB;
  v_session            JSONB;
  v_n_weeks            INT := 0;
  v_n_sessions         INT := 0;
  v_snapshot_payload   JSONB;
BEGIN

  -- ── 1. Snapshot existing plan (if any) ────────────────────────────────────
  SELECT id INTO v_existing_plan_id
  FROM public.training_plans
  WHERE user_id = p_user_id
  LIMIT 1;

  IF v_existing_plan_id IS NOT NULL THEN
    -- Build a nested JSONB snapshot: {plan: {...}, weeks: [{...week, sessions:[...]}]}
    SELECT jsonb_build_object(
      'plan', row_to_json(tp)::jsonb,
      'weeks', COALESCE(
        (
          SELECT jsonb_agg(
            jsonb_build_object(
              'week', row_to_json(pw)::jsonb,
              'sessions', COALESCE(
                (
                  SELECT jsonb_agg(row_to_json(ps)::jsonb ORDER BY ps.order_in_day)
                  FROM public.plan_sessions ps
                  WHERE ps.week_id = pw.id
                ),
                '[]'::jsonb
              )
            )
            ORDER BY pw.week_number
          )
          FROM public.plan_weeks pw
          WHERE pw.plan_id = v_existing_plan_id
        ),
        '[]'::jsonb
      )
    )
    INTO v_snapshot_payload
    FROM public.training_plans tp
    WHERE tp.id = v_existing_plan_id;

    INSERT INTO public.plan_snapshots (user_id, snapshot, reason)
    VALUES (p_user_id, v_snapshot_payload, 'import-plan-replace')
    RETURNING id INTO v_snapshot_id;

    -- ── 2. Delete existing plan (CASCADE removes weeks + sessions) ───────────
    DELETE FROM public.training_plans WHERE id = v_existing_plan_id;
  END IF;

  -- ── 3. Insert new training_plans row ──────────────────────────────────────
  INSERT INTO public.training_plans (
    user_id,
    status,
    race_objective,
    race_date,
    start_date,
    total_weeks
  )
  VALUES (
    p_user_id,
    'active',
    p_plan->>'race_objective',
    (p_plan->>'race_date')::date,
    (p_plan->>'start_date')::date,
    (p_plan->>'total_weeks')::int
  )
  RETURNING id INTO v_new_plan_id;

  -- ── 4+5. Insert weeks and their sessions ──────────────────────────────────
  FOR v_week IN SELECT * FROM jsonb_array_elements(p_weeks)
  LOOP
    INSERT INTO public.plan_weeks (
      plan_id,
      week_number,
      phase,
      is_recovery,
      rest_days,
      notes,
      start_date
    )
    VALUES (
      v_new_plan_id,
      (v_week->>'week_number')::int,
      v_week->>'phase',
      (v_week->>'is_recovery')::boolean,
      COALESCE(v_week->'rest_days', '[]'::jsonb),
      v_week->>'notes',
      (v_week->>'start_date')::date
    )
    RETURNING id INTO v_week_id;

    v_n_weeks := v_n_weeks + 1;

    -- Insert each session in this week
    FOR v_session IN SELECT * FROM jsonb_array_elements(v_week->'sessions')
    LOOP
      INSERT INTO public.plan_sessions (
        week_id,
        day,
        sport,
        type,
        template_id,
        duration_minutes,
        is_brick,
        notes,
        order_in_day,
        structure
      )
      VALUES (
        v_week_id,
        v_session->>'day',
        v_session->>'sport',
        v_session->>'type',
        v_session->>'template_id',
        (v_session->>'duration_minutes')::int,
        COALESCE((v_session->>'is_brick')::boolean, false),
        v_session->>'notes',
        COALESCE((v_session->>'order_in_day')::int, 0),
        v_session->'structure'  -- pre-materialised by Edge Function; may be NULL
      );

      v_n_sessions := v_n_sessions + 1;
    END LOOP;
  END LOOP;

  -- ── 6. Apply profile updates (optional) ───────────────────────────────────
  -- Only update columns that are explicitly present in p_profile_updates.
  -- Each field is applied conditionally to avoid clobbering unrelated columns.
  IF p_profile_updates IS NOT NULL THEN
    UPDATE public.users
    SET
      max_hr = CASE WHEN p_profile_updates ? 'max_hr'
                    THEN (p_profile_updates->>'max_hr')::int
                    ELSE max_hr END,
      ftp    = CASE WHEN p_profile_updates ? 'ftp'
                    THEN (p_profile_updates->>'ftp')::int
                    ELSE ftp END,
      vma    = CASE WHEN p_profile_updates ? 'vma'
                    THEN (p_profile_updates->>'vma')::decimal
                    ELSE vma END,
      css_seconds_per100m = CASE WHEN p_profile_updates ? 'css_seconds_per100m'
                                 THEN (p_profile_updates->>'css_seconds_per100m')::int
                                 ELSE css_seconds_per100m END,
      race_objective = CASE WHEN p_profile_updates ? 'race_objective'
                            THEN p_profile_updates->>'race_objective'
                            ELSE race_objective END,
      race_date = CASE WHEN p_profile_updates ? 'race_date'
                       THEN (p_profile_updates->>'race_date')::timestamptz
                       ELSE race_date END
    WHERE id = p_user_id;
  END IF;

  -- ── 7. Return summary ─────────────────────────────────────────────────────
  RETURN jsonb_build_object(
    'plan_id',           v_new_plan_id,
    'snapshot_id',       v_snapshot_id,  -- NULL if there was no prior plan
    'weeks_inserted',    v_n_weeks,
    'sessions_inserted', v_n_sessions
  );

END;
$$;

COMMENT ON FUNCTION public.import_plan_atomic IS
  'Atomically replaces a user''s training plan: snapshots existing data, deletes old plan (CASCADE), inserts new plan/weeks/sessions with pre-materialised structure JSONB, and optionally updates user profile. Called by the import-plan Edge Function. SECURITY DEFINER.';

-- Grant execute to service_role only (Edge Functions call this via their service_role client)
GRANT EXECUTE ON FUNCTION public.import_plan_atomic(UUID, JSONB, JSONB, JSONB)
  TO service_role;

-- ============================================================================
-- DOWN MIGRATION (run manually if rollback needed)
-- ============================================================================
-- REVOKE EXECUTE ON FUNCTION public.import_plan_atomic(UUID, JSONB, JSONB, JSONB) FROM service_role;
-- DROP FUNCTION IF EXISTS public.import_plan_atomic(UUID, JSONB, JSONB, JSONB);
-- DROP POLICY IF EXISTS "users read own snapshots" ON public.plan_snapshots;
-- DROP INDEX IF EXISTS idx_plan_snapshots_user_id_created_at;
-- DROP TABLE IF EXISTS public.plan_snapshots;
