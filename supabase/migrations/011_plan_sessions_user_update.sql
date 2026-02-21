-- Migration: Add UPDATE RLS policy and reorder_sessions RPC on plan_sessions
-- Description: First client-side write path to plan_sessions. Allows authenticated users
--              to move sessions between days/weeks (drag & drop). Adds an UPDATE RLS policy
--              and a transactional batch-reorder RPC function.
-- Date: 2026-02-21
-- Related: DRO-133, DRO-134

-- ============================================================================
-- UP MIGRATION
-- ============================================================================

-- RLS Policy: Users can UPDATE their own plan sessions (day, week_id, order_in_day only)
-- Ownership validated via join: plan_sessions → plan_weeks → training_plans → user_id
CREATE POLICY "Users can update own plan sessions"
    ON public.plan_sessions
    FOR UPDATE
    USING (
        week_id IN (
            SELECT pw.id
            FROM public.plan_weeks pw
            INNER JOIN public.training_plans tp ON pw.plan_id = tp.id
            WHERE tp.user_id = auth.uid()
        )
    )
    WITH CHECK (
        week_id IN (
            SELECT pw.id
            FROM public.plan_weeks pw
            INNER JOIN public.training_plans tp ON pw.plan_id = tp.id
            WHERE tp.user_id = auth.uid()
        )
    );

-- RPC Function: reorder_sessions
-- Accepts a JSONB array of {id, day, week_id, order_in_day} objects and applies all
-- updates in a single transaction. SECURITY DEFINER bypasses RLS internally; ownership
-- is validated explicitly per row before any write occurs.
CREATE OR REPLACE FUNCTION public.reorder_sessions(session_updates JSONB)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    update_item  JSONB;
    session_id   UUID;
    new_day      TEXT;
    new_week_id  UUID;
    new_order    INT;
    is_owner     BOOLEAN;
BEGIN
    FOR update_item IN SELECT * FROM jsonb_array_elements(session_updates)
    LOOP
        session_id  := (update_item->>'id')::UUID;
        new_day     := update_item->>'day';
        new_week_id := (update_item->>'week_id')::UUID;
        new_order   := (update_item->>'order_in_day')::INT;

        -- Validate that the calling user owns the target session
        SELECT EXISTS (
            SELECT 1
            FROM public.plan_sessions ps
            INNER JOIN public.plan_weeks pw ON ps.week_id = pw.id
            INNER JOIN public.training_plans tp ON pw.plan_id = tp.id
            WHERE ps.id = session_id
              AND tp.user_id = auth.uid()
        ) INTO is_owner;

        IF NOT is_owner THEN
            RAISE EXCEPTION 'Unauthorized: session % does not belong to the calling user', session_id;
        END IF;

        -- Also validate that the destination week belongs to the calling user
        SELECT EXISTS (
            SELECT 1
            FROM public.plan_weeks pw
            INNER JOIN public.training_plans tp ON pw.plan_id = tp.id
            WHERE pw.id = new_week_id
              AND tp.user_id = auth.uid()
        ) INTO is_owner;

        IF NOT is_owner THEN
            RAISE EXCEPTION 'Unauthorized: week % does not belong to the calling user', new_week_id;
        END IF;

        UPDATE public.plan_sessions
        SET
            day          = new_day,
            week_id      = new_week_id,
            order_in_day = new_order
        WHERE id = session_id;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.reorder_sessions(JSONB) IS
    'Batch-updates day/week_id/order_in_day on plan_sessions for drag-and-drop rescheduling. '
    'Validates per-row ownership. Runs in a single transaction (all-or-nothing).';

-- ============================================================================
-- DOWN MIGRATION (run manually if rollback needed)
-- ============================================================================
-- DROP FUNCTION IF EXISTS public.reorder_sessions(JSONB);
-- DROP POLICY IF EXISTS "Users can update own plan sessions" ON public.plan_sessions;
