begin;

create extension if not exists pgcrypto;

create table if not exists locales (
    locale_code text primary key,
    language_name text not null,
    region_name text,
    script_name text,
    is_active boolean not null default true,
    created_at timestamptz not null default now()
);

insert into locales (locale_code, language_name, region_name, script_name, is_active)
values
    ('en-KE', 'English', 'Kenya', 'Latin', true),
    ('sw-KE', 'Swahili', 'Kenya', 'Latin', true),
    ('hi-IN', 'Hindi', 'India', 'Devanagari', true),
    ('en-US', 'English', 'United States', 'Latin', true)
on conflict (locale_code) do nothing;

create table if not exists users (
    user_id text primary key,
    email text unique,
    phone text unique,
    display_name text,
    account_status text not null default 'active',
    signup_source text not null default 'manual',
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table if not exists user_profiles (
    profile_id uuid primary key default gen_random_uuid(),
    user_id text not null unique references users(user_id) on delete cascade,
    primary_locale_code text not null references locales(locale_code),
    country_code text,
    region_text text,
    cooking_confidence_level text not null default 'beginner',
    literacy_mode text not null default 'full_text',
    guidance_mode text not null default 'listen_only',
    dietary_flags_json jsonb not null default '{}'::jsonb,
    allergen_flags_json jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

insert into users (user_id, display_name, account_status, signup_source)
values ('local-user-1', 'Nomad Beta User', 'active', 'beta_invite')
on conflict (user_id) do nothing;

insert into user_profiles (
    user_id,
    primary_locale_code,
    country_code,
    region_text,
    cooking_confidence_level,
    literacy_mode,
    guidance_mode
)
values (
    'local-user-1',
    'en-KE',
    'KE',
    'Mombasa',
    'beginner',
    'full_text',
    'listen_only'
)
on conflict (user_id) do nothing;

create table if not exists user_preferences (
    user_id text primary key,
    primary_locale text not null default 'en-KE',
    guidance_mode text not null default 'listen_only',
    ambience_enabled boolean not null default true,
    ambience_mood text not null default 'calm_dining',
    ambient_sound_default_level numeric(4,2) not null default 0.35,
    voice_enabled boolean not null default true,
    auto_resume_session boolean not null default true,
    measurement_system text not null default 'metric',
    default_servings integer,
    updated_at timestamptz not null default now()
);

alter table user_preferences
    add column if not exists primary_locale text;

alter table user_preferences
    add column if not exists guidance_mode text;

alter table user_preferences
    add column if not exists ambience_enabled boolean;

alter table user_preferences
    add column if not exists ambience_mood text;

alter table user_preferences
    add column if not exists ambient_sound_default_level numeric(4,2);

alter table user_preferences
    add column if not exists voice_enabled boolean;

alter table user_preferences
    add column if not exists auto_resume_session boolean;

alter table user_preferences
    add column if not exists measurement_system text;

alter table user_preferences
    add column if not exists default_servings integer;

update user_preferences
set
    primary_locale = coalesce(primary_locale, 'en-KE'),
    guidance_mode = coalesce(guidance_mode, 'listen_only'),
    ambience_enabled = coalesce(ambience_enabled, true),
    ambience_mood = coalesce(ambience_mood, 'calm_dining'),
    ambient_sound_default_level = coalesce(ambient_sound_default_level, 0.35),
    voice_enabled = coalesce(voice_enabled, true),
    auto_resume_session = coalesce(auto_resume_session, true),
    measurement_system = coalesce(measurement_system, 'metric');

insert into user_preferences (
    user_id,
    primary_locale,
    guidance_mode,
    ambience_enabled,
    ambience_mood,
    ambient_sound_default_level,
    voice_enabled,
    auto_resume_session,
    measurement_system,
    default_servings
)
values (
    'local-user-1',
    'en-KE',
    'listen_only',
    true,
    'calm_dining',
    0.35,
    true,
    true,
    'metric',
    2
)
on conflict (user_id) do nothing;

create index if not exists idx_users_account_status
    on users(account_status);

create index if not exists idx_user_profiles_locale
    on user_profiles(primary_locale_code);

commit;
