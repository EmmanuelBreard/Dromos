-- Migration: Add reorder_sessions RPC on plan_sessions
-- Description: First client-side write path to plan_sessions. All writes go through
--              the reorder_sessions RPC function (SECURITY DEFINER), which validates
--              per-row ownership. No direct UPDATE RLS policy — principle of least privilege.
-- Date: 2026-02-21
-- Related: DRO-133, DRO-134

-- ============================================================================
-- UP MIGRATION
-- ============================================================================

-- RPC Function: reorder_sessions
-- Accepts a JSONB array of {id, day, week_id, order_in_day} objects and applies all
-- updates atomically. SECURITY DEFINER bypasses RLS internally; ownership is validated
-- explicitly per row before any write occurs.
CREATE FUNCTION public.reorder_sessions(session_updates JSONB)
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
    -- Validate input is a non-null JSON array
    IF session_updates IS NULL OR jsonb_typeof(session_updates) != 'array' THEN
        RAISE EXCEPTION 'session_updates must be a non-null JSON array';
    END IF;

    -- No-op for empty array
    IF jsonb_array_length(session_updates) = 0 THEN
        RETURN;
    END IF;

    FOR update_item IN SELECT * FROM jsonb_array_elements(session_updates)
    LOOP
        session_id  := (update_item->>'id')::UUID;
        new_day     := update_item->>'day';
        new_week_id := (update_item->>'week_id')::UUID;
        new_order   := (update_item->>'order_in_day')::INT;

        -- Validate all required fields are present
        IF session_id IS NULL OR new_day IS NULL OR new_week_id IS NULL OR new_order IS NULL THEN
            RAISE EXCEPTION 'Missing required fields in update item: id, day, week_id, and order_in_day are all required (got: %)', update_item;
        END IF;

        -- Validate day value
        IF new_day NOT IN ('Monday','Tuesday','Wednesday','Thursday','Friday','Saturday','Sunday') THEN
            RAISE EXCEPTION 'Invalid day value: %', new_day;
        END IF;

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

        -- Validate that the destination week belongs to the calling user
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

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Session % not found or was deleted during the transaction', session_id;
        END IF;
    END LOOP;
END;
$$;

COMMENT ON FUNCTION public.reorder_sessions(JSONB) IS
    'Batch-updates day/week_id/order_in_day on plan_sessions for drag-and-drop rescheduling. '
    'Validates per-row ownership. Runs within the caller''s transaction scope (all-or-nothing).';

-- Grant execute to authenticated users (required for Supabase .rpc() calls)
GRANT EXECUTE ON FUNCTION public.reorder_sessions(JSONB) TO authenticated;

-- ============================================================================
-- DOWN MIGRATION (run manually if rollback needed)
-- ============================================================================
-- REVOKE EXECUTE ON FUNCTION public.reorder_sessions(JSONB) FROM authenticated;
-- DROP FUNCTION IF EXISTS public.reorder_sessions(JSONB);
