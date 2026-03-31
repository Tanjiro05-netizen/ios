-- Relax content AND title length constraints for testing
-- Changes minimum length from 10/3 to 1 for both

-- 1. Relax Content Length (10 -> 1)
ALTER TABLE public.forum_threads 
DROP CONSTRAINT IF EXISTS forum_threads_content_check;

ALTER TABLE public.forum_threads 
ADD CONSTRAINT forum_threads_content_check CHECK (char_length(content) >= 1);

-- 2. Relax Title Length (3 -> 1)
ALTER TABLE public.forum_threads 
DROP CONSTRAINT IF EXISTS forum_threads_title_check;

ALTER TABLE public.forum_threads 
ADD CONSTRAINT forum_threads_title_check CHECK (char_length(title) >= 1 AND char_length(title) <= 200);
