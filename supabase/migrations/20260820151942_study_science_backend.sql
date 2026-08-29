-- Secure, invite-only sync for the PHY111 science-course beta.
--
-- Client roles may read only their own rows. All writes pass through narrowly
-- scoped RPCs which derive the owner from auth.uid(), reject anonymous Auth
-- users, enforce the bundled content allowlist, and make client-generated UUID
-- retries idempotent.

create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table private.study_science_invites (
    id uuid primary key default gen_random_uuid(),
    course_id text not null default 'PHY111' check (course_id = 'PHY111'),
    code_hash bytea not null unique check (octet_length(code_hash) = 32),
    code_hint text not null check (char_length(code_hint) between 4 and 8),
    expires_at timestamptz not null,
    consumed_at timestamptz,
    consumed_by uuid references public.profiles(id) on delete set null,
    created_at timestamptz not null default now(),
    check (expires_at > created_at),
    check (consumed_by is null or consumed_at is not null)
);

comment on table private.study_science_invites is
    'Single-use PHY111 invitation hashes. Plaintext invitation codes are never stored.';

create index study_science_invites_available_idx
    on private.study_science_invites (course_id, expires_at)
    where consumed_at is null;

create index study_science_invites_consumed_by_idx
    on private.study_science_invites (consumed_by)
    where consumed_by is not null;

create table private.study_science_activity_catalog (
    course_id text not null check (course_id = 'PHY111'),
    course_version text not null,
    activity_id text not null,
    allows_progress boolean not null default true,
    allows_attempt boolean not null default true,
    primary key (course_id, course_version, activity_id),
    check (course_version ~ '^[0-9]+\.[0-9]+\.[0-9]+$'),
    check (activity_id ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$'),
    check (allows_progress or allows_attempt)
);

comment on table private.study_science_activity_catalog is
    'Exact bundled science activity/version allowlist accepted by sync RPCs.';

insert into private.study_science_activity_catalog (
    course_id, course_version, activity_id, allows_progress, allows_attempt
)
select 'PHY111', '0.1.0', activity_id, true, true
from unnest(array[
    'PHY111.activity.orientation.scientific-standard',
    'PHY111.activity.foundation.dimensions',
    'PHY111.activity.foundation.uncertainty',
    'PHY111.activity.m01.check.1.1',
    'PHY111.activity.m01.worked.round-trip',
    'PHY111.activity.m01.check.1.2',
    'PHY111.activity.m01.worked.braking',
    'PHY111.activity.m01.check.1.3',
    'PHY111.activity.m01.worked.projectile',
    'PHY111.activity.m01.check.1.4',
    'PHY111.activity.m01.worked.two-blocks',
    'PHY111.activity.m01.check.1.5',
    'PHY111.activity.m01.worked.elevator',
    'PHY111.activity.m01.guided.1A',
    'PHY111.activity.m01.guided.1B',
    'PHY111.activity.m01.derivation-board',
    'PHY111.activity.m01.worked.non-uniform-acceleration',
    'PHY111.activity.m01.worked.horizontal-curve',
    'PHY111.activity.m01.tutorial.A',
    'PHY111.activity.m01.tutorial.B',
    'PHY111.activity.m01.debug.circular-motion',
    'PHY111.activity.m01.video.motion-tracking-briefing',
    'PHY111.activity.m01.lab.motion-tracking',
    'PHY111.activity.m01.lab.numerical-guided',
    'PHY111.activity.m01.lab.python',
    'PHY111.activity.m01.problem.01',
    'PHY111.activity.m01.problem.02',
    'PHY111.activity.m01.problem.03',
    'PHY111.activity.m01.problem.04',
    'PHY111.activity.m01.problem.05',
    'PHY111.activity.m01.problem.06',
    'PHY111.activity.m01.problem.07',
    'PHY111.activity.m01.problem.08',
    'PHY111.activity.m01.problem.09',
    'PHY111.activity.m01.problem.10',
    'PHY111.assessment.m01.mastery',
    'PHY111.assessment.m01.quiz'
]::text[]) as allowed(activity_id)
on conflict (course_id, course_version, activity_id) do update
set allows_progress = excluded.allows_progress,
    allows_attempt = excluded.allows_attempt;

insert into private.study_science_activity_catalog (
    course_id, course_version, activity_id, allows_progress, allows_attempt
)
select 'PHY111', '0.1.0',
       format('PHY111.item.m01.%s.%s', assessment, lpad(item_number::text, 2, '0')),
       false,
       true
from unnest(array['mastery', 'quiz']::text[]) as kinds(assessment)
cross join generate_series(1, 8) as item_numbers(item_number)
on conflict (course_id, course_version, activity_id) do update
set allows_progress = excluded.allows_progress,
    allows_attempt = excluded.allows_attempt;

create table public.study_science_memberships (
    user_id uuid not null references public.profiles(id) on delete cascade,
    course_id text not null check (course_id = 'PHY111'),
    granted_at timestamptz not null default now(),
    revoked_at timestamptz,
    primary key (user_id, course_id),
    check (revoked_at is null or revoked_at >= granted_at)
);

create index study_science_memberships_active_user_idx
    on public.study_science_memberships (user_id, course_id)
    where revoked_at is null;

create table public.study_science_progress_events (
    id uuid primary key,
    user_id uuid not null references public.profiles(id) on delete cascade,
    course_id text not null,
    course_version text not null,
    activity_id text not null,
    event_type text not null check (
        event_type in ('started', 'saved', 'submitted', 'completed', 'mastered')
    ),
    origin_device_id uuid not null,
    occurred_at timestamptz not null,
    payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
    payload_hash bytea not null check (octet_length(payload_hash) = 32),
    server_created_at timestamptz not null default clock_timestamp(),
    foreign key (course_id, course_version, activity_id)
        references private.study_science_activity_catalog(course_id, course_version, activity_id)
        on update restrict on delete restrict
);

create index study_science_progress_events_user_cursor_idx
    on public.study_science_progress_events (user_id, server_created_at, id);

create index study_science_progress_events_user_activity_idx
    on public.study_science_progress_events (user_id, course_id, course_version, activity_id, occurred_at desc);

create table public.study_science_attempts (
    id uuid primary key,
    user_id uuid not null references public.profiles(id) on delete cascade,
    course_id text not null,
    course_version text not null,
    activity_id text not null,
    attempt_kind text not null check (attempt_kind in ('activity', 'assessment')),
    origin_device_id uuid not null,
    occurred_at timestamptz not null,
    payload jsonb not null check (jsonb_typeof(payload) = 'object'),
    payload_hash bytea not null check (octet_length(payload_hash) = 32),
    server_created_at timestamptz not null default clock_timestamp(),
    foreign key (course_id, course_version, activity_id)
        references private.study_science_activity_catalog(course_id, course_version, activity_id)
        on update restrict on delete restrict
);

create index study_science_attempts_user_cursor_idx
    on public.study_science_attempts (user_id, server_created_at, id);

create index study_science_attempts_user_activity_idx
    on public.study_science_attempts (user_id, course_id, course_version, activity_id, occurred_at desc);

alter table public.study_science_memberships enable row level security;
alter table public.study_science_progress_events enable row level security;
alter table public.study_science_attempts enable row level security;

revoke all on table private.study_science_invites from public, anon, authenticated;
revoke all on table private.study_science_activity_catalog from public, anon, authenticated;
revoke all on table public.study_science_memberships from public, anon, authenticated;
revoke all on table public.study_science_progress_events from public, anon, authenticated;
revoke all on table public.study_science_attempts from public, anon, authenticated;

grant all on table private.study_science_invites to service_role;
grant all on table private.study_science_activity_catalog to service_role;
grant all on table public.study_science_memberships to service_role;
grant all on table public.study_science_progress_events to service_role;
grant all on table public.study_science_attempts to service_role;

grant select on table public.study_science_memberships to authenticated;
grant select on table public.study_science_progress_events to authenticated;
grant select on table public.study_science_attempts to authenticated;

create policy "Users can read their own science membership"
    on public.study_science_memberships for select
    to authenticated
    using ((select auth.uid()) = user_id);

create policy "Users can read their own science progress events"
    on public.study_science_progress_events for select
    to authenticated
    using ((select auth.uid()) = user_id);

create policy "Users can read their own science attempts"
    on public.study_science_attempts for select
    to authenticated
    using ((select auth.uid()) = user_id);

create or replace function private.study_science_request_user()
returns uuid
language plpgsql
stable
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := auth.uid();
    v_session_id_text text := auth.jwt() ->> 'session_id';
begin
    if v_user_id is null
        or lower(coalesce(auth.jwt() ->> 'is_anonymous', 'false')) = 'true'
        or v_session_id_text is null
        or v_session_id_text !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
        or not exists (
            select 1
            from auth.sessions as session
            where session.id = v_session_id_text::uuid
              and session.user_id = v_user_id
        )
    then
        raise exception using
            errcode = '28000',
            message = 'A current non-anonymous session is required.';
    end if;

    return v_user_id;
end;
$$;

revoke execute on function private.study_science_request_user() from public, anon, authenticated;

create or replace function private.study_science_payload_is_safe(p_payload jsonb)
returns boolean
language plpgsql
immutable
strict
set search_path = ''
as $$
declare
    v_key text;
    v_value jsonb;
    v_text text;
begin
    if jsonb_typeof(p_payload) = 'object' then
        for v_key, v_value in select key, value from pg_catalog.jsonb_each(p_payload)
        loop
            if v_key ~* '^(raw[_-]?video|video[_-]?(data|bytes|url)|thumbnail|base64|file[_-]?(path|url|bytes)|local[_-]?(path|url)|media[_-]?blob)$' then
                return false;
            end if;
            if not private.study_science_payload_is_safe(v_value) then
                return false;
            end if;
        end loop;
    elsif jsonb_typeof(p_payload) = 'array' then
        for v_value in select value from pg_catalog.jsonb_array_elements(p_payload)
        loop
            if not private.study_science_payload_is_safe(v_value) then
                return false;
            end if;
        end loop;
    elsif jsonb_typeof(p_payload) = 'string' then
        v_text := p_payload #>> '{}';
        if v_text ~* '^data:(image|video|audio)/[^;]+;base64,' or v_text ~* '^file://' then
            return false;
        end if;
    end if;

    return true;
end;
$$;

revoke execute on function private.study_science_payload_is_safe(jsonb) from public, anon, authenticated;

create or replace function private.study_science_payload_hash(
    p_record_kind text,
    p_id uuid,
    p_user_id uuid,
    p_course_id text,
    p_course_version text,
    p_activity_id text,
    p_subtype text,
    p_origin_device_id uuid,
    p_occurred_at timestamptz,
    p_payload jsonb
)
returns bytea
language sql
immutable
strict
set search_path = ''
as $$
    select extensions.digest(
        pg_catalog.convert_to(
            pg_catalog.concat_ws(
                pg_catalog.chr(31),
                p_record_kind,
                p_id::text,
                p_user_id::text,
                p_course_id,
                p_course_version,
                p_activity_id,
                p_subtype,
                p_origin_device_id::text,
                pg_catalog.date_part('epoch', p_occurred_at)::text,
                p_payload::text
            ),
            'UTF8'
        ),
        'sha256'
    );
$$;

revoke execute on function private.study_science_payload_hash(text, uuid, uuid, text, text, text, text, uuid, timestamptz, jsonb)
    from public, anon, authenticated;

create or replace function public.create_study_science_invite(
    p_expires_at timestamptz default (statement_timestamp() + interval '30 days')
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_secret text := upper(pg_catalog.encode(extensions.gen_random_bytes(16), 'hex'));
    v_code text;
    v_normalized_code text;
    v_invite_id uuid;
begin
    if p_expires_at < statement_timestamp() + interval '1 hour'
        or p_expires_at > statement_timestamp() + interval '180 days'
    then
        raise exception using errcode = '22023', message = 'Invitation expiry is outside the allowed range.';
    end if;

    v_code := 'PHY111-'
        || substr(v_secret, 1, 4) || '-'
        || substr(v_secret, 5, 4) || '-'
        || substr(v_secret, 9, 4) || '-'
        || substr(v_secret, 13, 4) || '-'
        || substr(v_secret, 17, 4) || '-'
        || substr(v_secret, 21, 4) || '-'
        || substr(v_secret, 25, 4) || '-'
        || substr(v_secret, 29, 4);
    v_normalized_code := pg_catalog.regexp_replace(v_code, '[^A-Z0-9]', '', 'g');

    insert into private.study_science_invites (course_id, code_hash, code_hint, expires_at)
    values (
        'PHY111',
        extensions.digest(pg_catalog.convert_to(v_normalized_code, 'UTF8'), 'sha256'),
        right(v_secret, 4),
        p_expires_at
    )
    returning id into v_invite_id;

    return jsonb_build_object(
        'id', v_invite_id,
        'course_id', 'PHY111',
        'code', v_code,
        'expires_at', p_expires_at
    );
end;
$$;

create or replace function public.redeem_study_science_invite(p_code text)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := private.study_science_request_user();
    v_normalized_code text;
    v_invite private.study_science_invites%rowtype;
    v_granted_at timestamptz := clock_timestamp();
begin
    v_normalized_code := pg_catalog.regexp_replace(
        upper(pg_catalog.btrim(coalesce(p_code, ''))),
        '[^A-Z0-9]',
        '',
        'g'
    );

    if char_length(v_normalized_code) < 20 or char_length(v_normalized_code) > 64 then
        return jsonb_build_object('success', false, 'status', 'invalid_or_unavailable');
    end if;

    select invitation.*
      into v_invite
      from private.study_science_invites as invitation
     where invitation.code_hash = extensions.digest(pg_catalog.convert_to(v_normalized_code, 'UTF8'), 'sha256')
       and invitation.course_id = 'PHY111'
       and invitation.consumed_at is null
       and invitation.expires_at > statement_timestamp()
     for update;

    if not found then
        return jsonb_build_object('success', false, 'status', 'invalid_or_unavailable');
    end if;

    update private.study_science_invites
       set consumed_at = v_granted_at,
           consumed_by = v_user_id
     where id = v_invite.id
       and consumed_at is null;

    if not found then
        return jsonb_build_object('success', false, 'status', 'invalid_or_unavailable');
    end if;

    insert into public.study_science_memberships (user_id, course_id, granted_at, revoked_at)
    values (v_user_id, v_invite.course_id, v_granted_at, null)
    on conflict (user_id, course_id) do update
       set granted_at = excluded.granted_at,
           revoked_at = null;

    return jsonb_build_object(
        'success', true,
        'status', 'granted',
        'course_id', v_invite.course_id,
        'granted_at', v_granted_at
    );
end;
$$;

create or replace function public.append_study_science_progress_event(
    p_id uuid,
    p_course_id text,
    p_course_version text,
    p_activity_id text,
    p_event_type text,
    p_origin_device_id uuid,
    p_occurred_at timestamptz,
    p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := private.study_science_request_user();
    v_payload_hash bytea;
    v_created_at timestamptz;
begin
    if p_id is null or p_origin_device_id is null
        or p_course_id <> 'PHY111'
        or p_course_version is null
        or p_activity_id is null
        or p_event_type not in ('started', 'saved', 'submitted', 'completed', 'mastered')
        or p_occurred_at is null
        or p_occurred_at > statement_timestamp() + interval '1 day'
        or p_occurred_at < timestamptz '2020-01-01 00:00:00+00'
        or p_payload is null
        or jsonb_typeof(p_payload) <> 'object'
        or octet_length(pg_catalog.convert_to(p_payload::text, 'UTF8')) > 524288
        or not private.study_science_payload_is_safe(p_payload)
    then
        raise exception using errcode = '22023', message = 'Invalid science progress payload.';
    end if;

    if not exists (
        select 1
        from public.study_science_memberships as membership
        where membership.user_id = v_user_id
          and membership.course_id = p_course_id
          and membership.revoked_at is null
    ) or not exists (
        select 1
        from private.study_science_activity_catalog as activity
        where activity.course_id = p_course_id
          and activity.course_version = p_course_version
          and activity.activity_id = p_activity_id
          and activity.allows_progress
    ) then
        raise exception using errcode = '42501', message = 'Science course access is unavailable.';
    end if;

    v_payload_hash := private.study_science_payload_hash(
        'progress', p_id, v_user_id, p_course_id, p_course_version,
        p_activity_id, p_event_type, p_origin_device_id, p_occurred_at, p_payload
    );

    insert into public.study_science_progress_events (
        id, user_id, course_id, course_version, activity_id, event_type,
        origin_device_id, occurred_at, payload, payload_hash
    ) values (
        p_id, v_user_id, p_course_id, p_course_version, p_activity_id, p_event_type,
        p_origin_device_id, p_occurred_at, p_payload, v_payload_hash
    ) on conflict (id) do nothing
      returning server_created_at into v_created_at;

    if v_created_at is null then
        select event.server_created_at
          into v_created_at
          from public.study_science_progress_events as event
         where event.id = p_id
           and event.user_id = v_user_id
           and event.payload_hash = v_payload_hash;

        if not found then
            raise exception using errcode = '23505', message = 'Science event idempotency conflict.';
        end if;

        return jsonb_build_object('id', p_id, 'inserted', false, 'server_created_at', v_created_at);
    end if;

    return jsonb_build_object('id', p_id, 'inserted', true, 'server_created_at', v_created_at);
end;
$$;

create or replace function public.append_study_science_attempt(
    p_id uuid,
    p_course_id text,
    p_course_version text,
    p_activity_id text,
    p_attempt_kind text,
    p_origin_device_id uuid,
    p_occurred_at timestamptz,
    p_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
    v_user_id uuid := private.study_science_request_user();
    v_payload_hash bytea;
    v_created_at timestamptz;
begin
    if p_id is null or p_origin_device_id is null
        or p_course_id <> 'PHY111'
        or p_course_version is null
        or p_activity_id is null
        or p_attempt_kind not in ('activity', 'assessment')
        or p_occurred_at is null
        or p_occurred_at > statement_timestamp() + interval '1 day'
        or p_occurred_at < timestamptz '2020-01-01 00:00:00+00'
        or p_payload is null
        or jsonb_typeof(p_payload) <> 'object'
        or octet_length(pg_catalog.convert_to(p_payload::text, 'UTF8')) > 524288
        or not private.study_science_payload_is_safe(p_payload)
    then
        raise exception using errcode = '22023', message = 'Invalid science attempt payload.';
    end if;

    if not exists (
        select 1
        from public.study_science_memberships as membership
        where membership.user_id = v_user_id
          and membership.course_id = p_course_id
          and membership.revoked_at is null
    ) or not exists (
        select 1
        from private.study_science_activity_catalog as activity
        where activity.course_id = p_course_id
          and activity.course_version = p_course_version
          and activity.activity_id = p_activity_id
          and activity.allows_attempt
    ) then
        raise exception using errcode = '42501', message = 'Science course access is unavailable.';
    end if;

    v_payload_hash := private.study_science_payload_hash(
        'attempt', p_id, v_user_id, p_course_id, p_course_version,
        p_activity_id, p_attempt_kind, p_origin_device_id, p_occurred_at, p_payload
    );

    insert into public.study_science_attempts (
        id, user_id, course_id, course_version, activity_id, attempt_kind,
        origin_device_id, occurred_at, payload, payload_hash
    ) values (
        p_id, v_user_id, p_course_id, p_course_version, p_activity_id, p_attempt_kind,
        p_origin_device_id, p_occurred_at, p_payload, v_payload_hash
    ) on conflict (id) do nothing
      returning server_created_at into v_created_at;

    if v_created_at is null then
        select attempt.server_created_at
          into v_created_at
          from public.study_science_attempts as attempt
         where attempt.id = p_id
           and attempt.user_id = v_user_id
           and attempt.payload_hash = v_payload_hash;

        if not found then
            raise exception using errcode = '23505', message = 'Science attempt idempotency conflict.';
        end if;

        return jsonb_build_object('id', p_id, 'inserted', false, 'server_created_at', v_created_at);
    end if;

    return jsonb_build_object('id', p_id, 'inserted', true, 'server_created_at', v_created_at);
end;
$$;

revoke execute on function public.create_study_science_invite(timestamptz) from public, anon, authenticated;
revoke execute on function public.redeem_study_science_invite(text) from public, anon;
revoke execute on function public.append_study_science_progress_event(uuid, text, text, text, text, uuid, timestamptz, jsonb) from public, anon;
revoke execute on function public.append_study_science_attempt(uuid, text, text, text, text, uuid, timestamptz, jsonb) from public, anon;

grant execute on function public.redeem_study_science_invite(text) to authenticated;
grant execute on function public.append_study_science_progress_event(uuid, text, text, text, text, uuid, timestamptz, jsonb) to authenticated;
grant execute on function public.append_study_science_attempt(uuid, text, text, text, text, uuid, timestamptz, jsonb) to authenticated;

grant execute on function public.create_study_science_invite(timestamptz) to service_role;
grant execute on function public.redeem_study_science_invite(text) to service_role;
grant execute on function public.append_study_science_progress_event(uuid, text, text, text, text, uuid, timestamptz, jsonb) to service_role;
grant execute on function public.append_study_science_attempt(uuid, text, text, text, text, uuid, timestamptz, jsonb) to service_role;

-- Retire the legacy plaintext global invite-code endpoint without deleting its
-- audit history or changing the historical account-trigger behavior.
drop policy if exists "Anyone can validate codes" on public.invite_codes;
revoke all on table public.invite_codes from public, anon, authenticated;
grant all on table public.invite_codes to service_role;
revoke execute on function public.use_invite_code(text, uuid) from public, anon, authenticated;
grant execute on function public.use_invite_code(text, uuid) to service_role;
