-- Cross-device reading state for the native iOS, Android, and web clients.
-- Local caches remain available offline; Supabase is the canonical signed-in
-- source of truth.

CREATE TABLE IF NOT EXISTS public.reading_progress (
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    book_id TEXT NOT NULL,
    title TEXT NOT NULL,
    author TEXT,
    chapter_title TEXT,
    chapter_index INTEGER NOT NULL DEFAULT 0 CHECK (chapter_index >= 0),
    chapter_count INTEGER NOT NULL DEFAULT 1 CHECK (chapter_count > 0),
    progress DOUBLE PRECISION NOT NULL DEFAULT 0 CHECK (progress >= 0 AND progress <= 1),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, book_id)
);

CREATE INDEX IF NOT EXISTS idx_reading_progress_user_updated
    ON public.reading_progress (user_id, updated_at DESC);

CREATE TABLE IF NOT EXISTS public.reading_quotes (
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    quote_id TEXT NOT NULL,
    text TEXT NOT NULL,
    source_title TEXT NOT NULL,
    source_detail TEXT,
    route_book_id TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (user_id, quote_id)
);

CREATE INDEX IF NOT EXISTS idx_reading_quotes_user_updated
    ON public.reading_quotes (user_id, updated_at DESC);

ALTER TABLE public.reading_progress ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reading_quotes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can read their reading progress" ON public.reading_progress;
DROP POLICY IF EXISTS "Users can insert their reading progress" ON public.reading_progress;
DROP POLICY IF EXISTS "Users can update their reading progress" ON public.reading_progress;
DROP POLICY IF EXISTS "Users can delete their reading progress" ON public.reading_progress;

CREATE POLICY "Users can read their reading progress"
    ON public.reading_progress FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can insert their reading progress"
    ON public.reading_progress FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can update their reading progress"
    ON public.reading_progress FOR UPDATE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can delete their reading progress"
    ON public.reading_progress FOR DELETE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

DROP POLICY IF EXISTS "Users can read their reading quotes" ON public.reading_quotes;
DROP POLICY IF EXISTS "Users can insert their reading quotes" ON public.reading_quotes;
DROP POLICY IF EXISTS "Users can update their reading quotes" ON public.reading_quotes;
DROP POLICY IF EXISTS "Users can delete their reading quotes" ON public.reading_quotes;

CREATE POLICY "Users can read their reading quotes"
    ON public.reading_quotes FOR SELECT
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can insert their reading quotes"
    ON public.reading_quotes FOR INSERT
    TO authenticated
    WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can update their reading quotes"
    ON public.reading_quotes FOR UPDATE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id)
    WITH CHECK ((SELECT auth.uid()) = user_id);

CREATE POLICY "Users can delete their reading quotes"
    ON public.reading_quotes FOR DELETE
    TO authenticated
    USING ((SELECT auth.uid()) = user_id);

GRANT SELECT, INSERT, UPDATE, DELETE ON public.reading_progress TO authenticated;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.reading_quotes TO authenticated;
GRANT ALL ON public.reading_progress TO service_role;
GRANT ALL ON public.reading_quotes TO service_role;
