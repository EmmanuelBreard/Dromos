-- UP
-- Creates the chat_messages table for storing conversation history between
-- athletes and the AI coaching agent. Messages are appended in a single
-- continuous thread per user (no sessions). The edge function inserts via
-- service_role; the iOS client only reads and deletes via RLS policies.

CREATE TABLE public.chat_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant')),
  content TEXT NOT NULL,
  status TEXT CHECK (status IN ('ready', 'need_info', 'no_action', 'escalate')),
  constraint_summary JSONB,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Index for efficient per-user message retrieval ordered by time
CREATE INDEX idx_chat_messages_user_id_created_at
  ON public.chat_messages (user_id, created_at);

ALTER TABLE public.chat_messages ENABLE ROW LEVEL SECURITY;

-- Authenticated users can read their own messages
CREATE POLICY "Users can read own messages"
  ON public.chat_messages FOR SELECT
  USING (auth.uid() = user_id);

-- Authenticated users can delete their own messages (clear history)
CREATE POLICY "Users can delete own messages"
  ON public.chat_messages FOR DELETE
  USING (auth.uid() = user_id);

-- Edge function inserts via service_role (bypasses RLS)
-- No INSERT policy needed for authenticated users

-- DOWN MIGRATION (run manually if rollback needed)
-- DROP TABLE IF EXISTS public.chat_messages;
