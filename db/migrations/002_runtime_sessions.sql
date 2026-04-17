begin;

alter table cooking_sessions
    add column if not exists user_id text;

alter table cooking_sessions
    add column if not exists generation_request_id uuid;

alter table cooking_sessions
    add column if not exists started_at timestamptz;

alter table cooking_sessions
    add column if not exists last_active_at timestamptz;

alter table cooking_sessions
    add column if not exists completed_at timestamptz;

update cooking_sessions
set
    user_id = coalesce(user_id, 'local-user-1'),
    last_active_at = coalesce(last_active_at, updated_at, created_at, now()),
    started_at = coalesce(started_at, created_at),
    completed_at = case
        when completed = true and completed_at is null then coalesce(updated_at, now())
        else completed_at
    end;

create table if not exists session_audio_state (
    session_id text primary key references cooking_sessions(session_id) on delete cascade,
    ambient_enabled boolean not null default true,
    muted boolean not null default false,
    ducking_active boolean not null default true,
    current_track_ref text,
    requested_volume numeric(4,2) not null default 0.35,
    last_changed_at timestamptz not null default now()
);

insert into session_audio_state (
    session_id,
    ambient_enabled,
    muted,
    ducking_active,
    current_track_ref,
    requested_volume,
    last_changed_at
)
select
    session_id,
    coalesce(ambience_enabled, true),
    coalesce(audio_muted, false),
    coalesce(audio_ducking_active, true),
    null,
    coalesce(audio_requested_volume, 0.35),
    now()
from cooking_sessions
on conflict (session_id) do nothing;

create table if not exists session_step_events (
    session_step_event_id uuid primary key default gen_random_uuid(),
    session_id text not null references cooking_sessions(session_id) on delete cascade,
    recipe_step_ref text,
    event_type text not null,
    event_payload_json jsonb not null default '{}'::jsonb,
    created_at timestamptz not null default now()
);

create table if not exists session_issue_reports (
    session_issue_report_id uuid primary key default gen_random_uuid(),
    session_id text not null references cooking_sessions(session_id) on delete cascade,
    issue_type text not null,
    user_note text,
    recovery_text_served text not null,
    step_number integer,
    created_at timestamptz not null default now()
);

create unique index if not exists uq_session_issue_reports_dedupe
    on session_issue_reports(session_id, issue_type, created_at);

create index if not exists idx_cooking_sessions_user_state
    on cooking_sessions(user_id, state);

create index if not exists idx_cooking_sessions_updated_at
    on cooking_sessions(updated_at desc);

create index if not exists idx_session_step_events_session_created
    on session_step_events(session_id, created_at);

create index if not exists idx_session_issue_reports_session
    on session_issue_reports(session_id);

do $$
begin
    if exists (
        select 1
        from information_schema.tables
        where table_schema = 'public'
          and table_name = 'session_issues'
    ) then
        insert into session_issue_reports (
            session_issue_report_id,
            session_id,
            issue_type,
            user_note,
            recovery_text_served,
            step_number,
            created_at
        )
        select
            gen_random_uuid(),
            session_id,
            issue_type,
            null,
            recovery_text,
            null,
            created_at
        from session_issues
        on conflict do nothing;
    end if;
end
$$;

commit;
