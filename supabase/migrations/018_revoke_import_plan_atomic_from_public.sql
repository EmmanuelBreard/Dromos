-- Migration: Security hardening for import_plan_atomic
-- Description:
--   1. Revoke PUBLIC/anon/authenticated EXECUTE on import_plan_atomic — the
--      Postgres default grants EXECUTE to PUBLIC on new functions, which means
--      any authenticated user could call the function via PostgREST /rpc/ and
--      overwrite any other user's plan by passing an arbitrary p_user_id UUID.
--      Only service_role (used by the import-plan Edge Function) should call it.
--   2. Replace the function body to fix a timezone-fragile cast:
--      `race_date::timestamptz` depended on the session timezone; changed to
--      `race_date::date::timestamptz` which always resolves to UTC midnight.
-- Date: 2026-06-06
-- Related: DRO-299 code-review fix #1 (security) and #8 (timezone)
-- Prerequisite: migration 017_plan_snapshots.sql must be applied.

-- ============================================================================
-- UP MIGRATION
-- ============================================================================

-- ---------------------------------------------------------------------------
-- Step 1: Revoke the implicit PUBLIC grant and explicit anon/authenticated grants
-- ---------------------------------------------------------------------------
REVOKE EXECUTE ON FUNCTION public.import_plan_atomic(UUID, JSONB, JSONB, JSONB)
  FROM PUBLIC;

REVOKE EXECUTE ON FUNCTION public.import_plan_atomic(UUID, JSONB, JSONB, JSONB)
  FROM anon, authenticated;

-- ---------------------------------------------------------------------------
-- Step 2: Replace the function body with the timezone-safe cast
--   Only the race_date UPDATE inside the IF p_profile_updates IS NOT NULL block
--   changes: `::timestamptz` → `::date::timestamptz`
--   The full body is reproduced here so this migration is self-contained and
--   Postgres can swap the body atomically.
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
        -- Defense-in-depth: coerce any non-boolean JSON value to false rather
        -- than erroring; the TS layer enforces typeof === "boolean" upstream.
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
      -- Fix #8: cast via ::date first to normalise to UTC midnight regardless
      -- of the Postgres session timezone. The previous ::timestamptz cast was
      -- fragile when the session tz was not UTC.
      race_date = CASE WHEN p_profile_updates ? 'race_date'
                       THEN (p_profile_updates->>'race_date')::date::timestamptz
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
  'Atomically replaces a user''s training plan: snapshots existing data, deletes old plan (CASCADE), inserts new plan/weeks/sessions with pre-materialised structure JSONB, and optionally updates user profile. Called by the import-plan Edge Function only. SECURITY DEFINER — callable by service_role only (PUBLIC/anon/authenticated revoked in migration 018).';

-- Ensure the service_role grant is still in place after OR REPLACE
-- (OR REPLACE preserves existing grants but we state this explicitly for clarity)
GRANT EXECUTE ON FUNCTION public.import_plan_atomic(UUID, JSONB, JSONB, JSONB)
  TO service_role;

-- ============================================================================
-- DOWN MIGRATION (run manually if rollback needed)
-- ============================================================================
-- GRANT EXECUTE ON FUNCTION public.import_plan_atomic(UUID, JSONB, JSONB, JSONB) TO PUBLIC;
-- (Restoring the original function body is not scripted — restore from git if needed)
