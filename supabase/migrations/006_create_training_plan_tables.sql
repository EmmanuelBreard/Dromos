-- Migration: Create training plan tables
-- Description: Creates training_plans, plan_weeks, and plan_sessions tables as the contract between Edge Function writer (DRO-41) and iOS display layer (DRO-43/44). SELECT-only RLS — Edge Function writes via service_role key.
-- Date: 2026-02-01
-- Related: DRO-40

-- ============================================================================
-- UP MIGRATION
-- ============================================================================

-- Ensure update_updated_at() function exists (created in migration 001)
CREATE OR REPLACE FUNCTION public.update_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$;

-- Create training_plans table
-- Stores the top-level training plan for each user
-- UNIQUE(user_id) ensures only one active plan per user (delete-and-replace on re-generation)
CREATE TABLE public.training_plans (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL UNIQUE REFERENCES public.users(id) ON DELETE CASCADE,
    status TEXT NOT NULL CHECK (status IN ('generating', 'active')),
    race_date DATE, -- Snapshot from user profile
    race_objective TEXT, -- Snapshot from user profile
    total_weeks INT NOT NULL CHECK (total_weeks > 0),
    start_date DATE NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.training_plans IS 'Top-level training plan for each user. One plan per user (UNIQUE constraint).';
COMMENT ON COLUMN public.training_plans.status IS 'Status: generating (plan being created) or active (plan ready for use)';
COMMENT ON COLUMN public.training_plans.race_date IS 'Snapshot of user race_date at plan creation time';
COMMENT ON COLUMN public.training_plans.race_objective IS 'Snapshot of user race_objective at plan creation time';

-- Create plan_weeks table
-- Stores weekly plan information within a training plan
CREATE TABLE public.plan_weeks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    plan_id UUID NOT NULL REFERENCES public.training_plans(id) ON DELETE CASCADE,
    week_number INT NOT NULL CHECK (week_number > 0),
    phase TEXT NOT NULL CHECK (phase IN ('Base', 'Build', 'Peak', 'Taper', 'Recovery')),
    is_recovery BOOLEAN NOT NULL DEFAULT false,
    rest_days JSONB NOT NULL DEFAULT '[]'::jsonb, -- Explicit rest days from macro plan (e.g., ["Monday", "Friday"])
    notes TEXT, -- Per-week coach notes from macro plan
    start_date DATE NOT NULL,
    UNIQUE(plan_id, week_number)
);

COMMENT ON TABLE public.plan_weeks IS 'Weekly plan information within a training plan';
COMMENT ON COLUMN public.plan_weeks.rest_days IS 'Explicit rest days from macro plan as JSON array of day names';
COMMENT ON COLUMN public.plan_weeks.notes IS 'Per-week coach notes from macro plan';

-- Create plan_sessions table
-- Stores individual training sessions within a week
CREATE TABLE public.plan_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    week_id UUID NOT NULL REFERENCES public.plan_weeks(id) ON DELETE CASCADE,
    day TEXT NOT NULL CHECK (day IN ('Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday')),
    sport TEXT NOT NULL CHECK (sport IN ('swim', 'bike', 'run')),
    type TEXT NOT NULL CHECK (type IN ('Easy', 'Tempo', 'Intervals')),
    template_id TEXT NOT NULL, -- Reference to workout template
    duration_minutes INT NOT NULL CHECK (duration_minutes > 0),
    is_brick BOOLEAN NOT NULL DEFAULT false, -- Multi-sport session (e.g., bike+run)
    notes TEXT, -- Future: coach notes per session (left NULL for now)
    order_in_day INT NOT NULL DEFAULT 0 -- Order when multiple sessions on same day
);

COMMENT ON TABLE public.plan_sessions IS 'Individual training sessions within a week';
COMMENT ON COLUMN public.plan_sessions.template_id IS 'Reference to workout template (used by iOS to fetch workout details)';
COMMENT ON COLUMN public.plan_sessions.is_brick IS 'True if this is a multi-sport session (e.g., bike followed by run)';
COMMENT ON COLUMN public.plan_sessions.order_in_day IS 'Order when multiple sessions occur on the same day';

-- Create indexes for common query patterns
CREATE INDEX idx_plan_sessions_week_id_day ON public.plan_sessions(week_id, day);
CREATE INDEX idx_plan_weeks_start_date ON public.plan_weeks(start_date);

-- Add updated_at trigger on training_plans
CREATE TRIGGER update_training_plans_updated_at
    BEFORE UPDATE ON public.training_plans
    FOR EACH ROW
    EXECUTE FUNCTION public.update_updated_at();

-- Enable Row Level Security on all tables
ALTER TABLE public.training_plans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plan_weeks ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.plan_sessions ENABLE ROW LEVEL SECURITY;

-- RLS Policy: Users can SELECT their own training plan
CREATE POLICY "Users can read own training plan"
    ON public.training_plans
    FOR SELECT
    USING (auth.uid() = user_id);

-- RLS Policy: Users can SELECT plan_weeks for their own training plan
CREATE POLICY "Users can read own plan weeks"
    ON public.plan_weeks
    FOR SELECT
    USING (plan_id IN (SELECT id FROM public.training_plans WHERE user_id = auth.uid()));

-- RLS Policy: Users can SELECT plan_sessions for their own training plan
-- Join through plan_weeks -> training_plans -> user_id
CREATE POLICY "Users can read own plan sessions"
    ON public.plan_sessions
    FOR SELECT
    USING (
        week_id IN (
            SELECT pw.id
            FROM public.plan_weeks pw
            INNER JOIN public.training_plans tp ON pw.plan_id = tp.id
            WHERE tp.user_id = auth.uid()
        )
    );

-- ============================================================================
-- DOWN MIGRATION (run manually if rollback needed)
-- ============================================================================
-- DROP POLICY IF EXISTS "Users can read own plan sessions" ON public.plan_sessions;
-- DROP POLICY IF EXISTS "Users can read own plan weeks" ON public.plan_weeks;
-- DROP POLICY IF EXISTS "Users can read own training plan" ON public.training_plans;
-- DROP TRIGGER IF EXISTS update_training_plans_updated_at ON public.training_plans;
-- DROP INDEX IF EXISTS idx_plan_weeks_start_date;
-- DROP INDEX IF EXISTS idx_plan_sessions_week_id_day;
-- DROP TABLE IF EXISTS public.plan_sessions;
-- DROP TABLE IF EXISTS public.plan_weeks;
-- DROP TABLE IF EXISTS public.training_plans;

