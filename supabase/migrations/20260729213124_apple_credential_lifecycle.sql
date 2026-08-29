-- Apple refresh credentials are server-only account lifecycle data. The
-- encrypted value is never exposed to anon/authenticated Data API roles.
create table if not exists public.apple_refresh_tokens (
    user_id uuid primary key references auth.users(id) on delete cascade,
    encrypted_refresh_token text not null,
    encryption_iv text not null,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.apple_refresh_tokens enable row level security;
revoke all on table public.apple_refresh_tokens from public, anon, authenticated;
grant all on table public.apple_refresh_tokens to service_role;

-- Failed provider revocations must not block account deletion. This queue is
-- deliberately detached from auth.users so a protected retry record can
-- remain after the Supabase account itself has been removed.
create table if not exists public.apple_revocation_queue (
    id uuid primary key default gen_random_uuid(),
    former_user_hash text not null,
    encrypted_refresh_token text not null,
    encryption_iv text not null,
    attempt_count integer not null default 1 check (attempt_count > 0),
    last_error text not null,
    next_attempt_at timestamptz not null default now(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

alter table public.apple_revocation_queue enable row level security;
revoke all on table public.apple_revocation_queue from public, anon, authenticated;
grant all on table public.apple_revocation_queue to service_role;

comment on table public.apple_refresh_tokens is
    'AES-GCM encrypted Sign in with Apple refresh tokens used only for account revocation.';
comment on table public.apple_revocation_queue is
    'Encrypted retry records for Apple revocation failures after user deletion.';
