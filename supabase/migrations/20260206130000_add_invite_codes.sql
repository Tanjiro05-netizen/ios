-- Invite Codes System
-- Based on Marxist-Platform implementation

-- Invite codes table
CREATE TABLE IF NOT EXISTS public.invite_codes (
    id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
    code TEXT NOT NULL UNIQUE,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    used_at TIMESTAMPTZ,
    used_by UUID REFERENCES public.profiles(id),
    is_active BOOLEAN DEFAULT true
);

-- Add invite status to profiles
ALTER TABLE public.profiles 
ADD COLUMN IF NOT EXISTS has_invite_access BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS invite_code_used TEXT;

-- Enable RLS on invite_codes
ALTER TABLE public.invite_codes ENABLE ROW LEVEL SECURITY;

-- Only admins can manage invite codes
CREATE POLICY "Admins can manage invite codes" ON public.invite_codes
    FOR ALL USING (public.is_admin());

-- Anyone can check if a code is valid (for registration/UI feedback)
CREATE POLICY "Anyone can validate codes" ON public.invite_codes
    FOR SELECT USING (true);

-- Function to validate and use an invite code
CREATE OR REPLACE FUNCTION public.use_invite_code(p_code TEXT, p_user_id UUID)
RETURNS JSON
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_invite_id UUID;
BEGIN
    -- Find valid code
    SELECT id INTO v_invite_id 
    FROM public.invite_codes 
    WHERE code = p_code 
      AND is_active = true 
      AND used_by IS NULL;
    
    IF v_invite_id IS NULL THEN
        RETURN json_build_object('success', false, 'error', 'Invalid or already used invite code');
    END IF;
    
    -- Mark code as used
    UPDATE public.invite_codes 
    SET used_at = now(), used_by = p_user_id, is_active = false
    WHERE id = v_invite_id;
    
    -- Grant access to user
    UPDATE public.profiles 
    SET has_invite_access = true, invite_code_used = p_code
    WHERE id = p_user_id;
    
    RETURN json_build_object('success', true);
END;
$$;

-- Update handle_new_user to process invite codes
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
    v_invite_code TEXT;
    v_invite_id UUID;
BEGIN
    -- Get invite code from user metadata
    v_invite_code := new.raw_user_meta_data->>'invite_code';
    
    -- Insert profile
    INSERT INTO public.profiles (id, username, avatar_url, has_invite_access)
    VALUES (
        new.id, 
        new.raw_user_meta_data->>'user_name', 
        new.raw_user_meta_data->>'avatar_url',
        false  -- Default to no access
    );
    
    -- If invite code provided, try to use it
    IF v_invite_code IS NOT NULL AND v_invite_code != '' THEN
        -- Find and validate the code
        SELECT id INTO v_invite_id 
        FROM public.invite_codes 
        WHERE code = UPPER(v_invite_code) 
          AND is_active = true 
          AND used_by IS NULL;
        
        IF v_invite_id IS NOT NULL THEN
            -- Mark code as used
            UPDATE public.invite_codes 
            SET used_at = now(), used_by = new.id, is_active = false
            WHERE id = v_invite_id;
            
            -- Grant access to user
            UPDATE public.profiles 
            SET has_invite_access = true, invite_code_used = UPPER(v_invite_code)
            WHERE id = new.id;
        END IF;
    END IF;
    
    RETURN new;
END;
$$;

-- Grant permissions
GRANT EXECUTE ON FUNCTION public.use_invite_code(TEXT, UUID) TO authenticated;
GRANT ALL ON TABLE public.invite_codes TO authenticated;
GRANT ALL ON TABLE public.invite_codes TO service_role;
