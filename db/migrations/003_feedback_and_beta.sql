begin;

create extension if not exists pgcrypto;

create table if not exists tester_profiles (
    tester_profile_id uuid primary key default gen_random_uuid(),
    user_id text not null unique references users(user_id) on delete cascade,
    cohort_name text,
    device_type text,
    country_code text,
    tester_notes text,
    active boolean not null default true,
    created_at timestamptz not null default now()
);

create table if not exists beta_invites (
    beta_invite_id uuid primary key default gen_random_uuid(),
    email_or_phone text not null,
    invite_status text not null default 'invited',
    invite_code text not null unique,
    notes text,
    created_at timestamptz not null default now()
);

create table if not exists user_feedback (
    feedback_id uuid primary key default gen_random_uuid(),
    user_id text references users(user_id) on delete set null,
    session_id text,
    feedback_category text not null default 'general',
    feedback_text text,
    device_context_json jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

alter table user_feedback
    add column if not exists feedback_id uuid;

alter table user_feedback
    add column if not exists user_id text;

alter table user_feedback
    add column if not exists feedback_category text;

alter table user_feedback
    add column if not exists feedback_text text;

alter table user_feedback
    add column if not exists device_context_json jsonb;

update user_feedback
set
    feedback_id = coalesce(feedback_id, gen_random_uuid()),
    user_id = coalesce(user_id, 'local-user-1'),
    feedback_category = coalesce(feedback_category, category, 'general'),
    feedback_text = coalesce(feedback_text, note, ''),
    device_context_json = coalesce(device_context_json, '{}'::jsonb);

create unique index if not exists uq_user_feedback_feedback_id
    on user_feedback(feedback_id);

create index if not exists idx_user_feedback_session
    on user_feedback(session_id);

create index if not exists idx_user_feedback_category
    on user_feedback(feedback_category);

create index if not exists idx_user_feedback_created_at
    on user_feedback(created_at desc);

insert into tester_profiles (
    user_id,
    cohort_name,
    device_type,
    country_code,
    tester_notes,
    active
)
values (
    'local-user-1',
    'founder-beta',
    'android',
    'KE',
    'bootstrap tester profile',
    true
)
on conflict (user_id) do nothing;

commit;
