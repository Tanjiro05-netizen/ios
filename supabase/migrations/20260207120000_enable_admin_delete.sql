-- Enable Admin/Moderator Delete Permissions
-- Allows users with role 'admin' or 'moderator' to delete any thread or comment

-- 1. Update Forum Threads Delete Policy
DROP POLICY IF EXISTS "Users can delete their own threads" ON public.forum_threads;
DROP POLICY IF EXISTS "Delete threads policy" ON public.forum_threads;

CREATE POLICY "Delete threads policy"
    ON public.forum_threads FOR DELETE
    TO public
    USING (
        (auth.uid() = author_id) OR 
        (EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE id = auth.uid() 
            AND role IN ('admin', 'moderator')
        ))
    );

-- 2. Update Forum Comments Delete Policy
DROP POLICY IF EXISTS "Users can delete their own comments" ON public.forum_comments;
DROP POLICY IF EXISTS "Delete comments policy" ON public.forum_comments;

CREATE POLICY "Delete comments policy"
    ON public.forum_comments FOR DELETE
    TO public
    USING (
        (auth.uid() = author_id) OR 
        (EXISTS (
            SELECT 1 FROM public.profiles 
            WHERE id = auth.uid() 
            AND role IN ('admin', 'moderator')
        ))
    );
