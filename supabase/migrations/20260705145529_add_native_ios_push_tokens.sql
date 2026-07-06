-- Native iOS push token support.
-- Existing Expo push storage on profiles.push_token remains supported for Android/Expo.

CREATE TABLE IF NOT EXISTS public.push_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    platform TEXT NOT NULL CHECK (platform IN ('ios', 'android', 'web')),
    provider TEXT NOT NULL CHECK (provider IN ('apns', 'expo', 'fcm')),
    token TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT true,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (user_id, provider, token)
);

CREATE INDEX IF NOT EXISTS idx_push_tokens_user_enabled
    ON public.push_tokens (user_id, enabled);

ALTER TABLE public.push_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read their push tokens" ON public.push_tokens;
DROP POLICY IF EXISTS "Users can insert their push tokens" ON public.push_tokens;
DROP POLICY IF EXISTS "Users can update their push tokens" ON public.push_tokens;
DROP POLICY IF EXISTS "Users can delete their push tokens" ON public.push_tokens;

CREATE POLICY "Users can read their push tokens"
    ON public.push_tokens FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can insert their push tokens"
    ON public.push_tokens FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can update their push tokens"
    ON public.push_tokens FOR UPDATE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can delete their push tokens"
    ON public.push_tokens FOR DELETE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.push_tokens TO authenticated;
GRANT ALL ON public.push_tokens TO service_role;
