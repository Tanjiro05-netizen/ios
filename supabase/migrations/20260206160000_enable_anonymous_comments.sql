-- Enable Anonymous Comments
-- Allows guests to comment without being logged in

-- 1. Modify Table Schema
ALTER TABLE public.forum_comments 
ALTER COLUMN author_id DROP NOT NULL;

ALTER TABLE public.forum_comments 
ADD COLUMN IF NOT EXISTS anonymous_name TEXT;

-- 2. Update RLS Policies for Comments

-- Allow anyone (including anon) to view comments
DROP POLICY IF EXISTS "Comments are viewable by authenticated users" ON public.forum_comments;
DROP POLICY IF EXISTS "Comments are viewable by everyone" ON public.forum_comments;

CREATE POLICY "Comments are viewable by everyone"
    ON public.forum_comments FOR SELECT
    TO public
    USING (true);

-- Allow anyone to create comments (including guests)
DROP POLICY IF EXISTS "Users can create comments" ON public.forum_comments;
DROP POLICY IF EXISTS "Anyone can create comments" ON public.forum_comments;

CREATE POLICY "Anyone can create comments"
    ON public.forum_comments FOR INSERT
    TO public
    WITH CHECK (
        (auth.uid() = author_id) OR 
        (author_id IS NULL AND anonymous_name IS NOT NULL)
    );

-- 3. Ensure Threads also support anonymous (idempotent check)
DO $$ 
BEGIN
    -- Check if we need to update threads table (just in case)
    ALTER TABLE public.forum_threads ALTER COLUMN author_id DROP NOT NULL;
    
    BEGIN
        ALTER TABLE public.forum_threads ADD COLUMN anonymous_name TEXT;
    EXCEPTION
        WHEN duplicate_column THEN
            -- Column already exists, ignore
    END;
END $$;

-- Update Thread Policies to ensure Anon can view/post
DROP POLICY IF EXISTS "Threads are viewable by authenticated users" ON public.forum_threads;
DROP POLICY IF EXISTS "Threads are viewable by everyone" ON public.forum_threads;

CREATE POLICY "Threads are viewable by everyone"
    ON public.forum_threads FOR SELECT
    TO public
    USING (true);

DROP POLICY IF EXISTS "Users can create threads" ON public.forum_threads;
DROP POLICY IF EXISTS "Anyone can create threads" ON public.forum_threads;

CREATE POLICY "Anyone can create threads"
    ON public.forum_threads FOR INSERT
    TO public
    WITH CHECK (
        (auth.uid() = author_id) OR 
        (author_id IS NULL AND anonymous_name IS NOT NULL)
    );
