begin;

update cooking_sessions
set
    user_id = coalesce(user_id, 'local-user-1'),
    state = coalesce(state, 'active'),
    current_phase = coalesce(current_phase, 'prep'),
    current_step_number = coalesce(current_step_number, 1),
    guidance_mode = coalesce(guidance_mode, 'listen_only'),
    session_locale = coalesce(session_locale, 'en-KE'),
    ambience_enabled = coalesce(ambience_enabled, true),
    ambience_mood_tag = coalesce(ambience_mood_tag, 'calm_dining'),
    audio_muted = coalesce(audio_muted, false),
    audio_ducking_active = coalesce(audio_ducking_active, true),
    audio_requested_volume = coalesce(audio_requested_volume, 0.35),
    completed = coalesce(completed, case when state = 'completed' then true else false end, false),
    started_at = coalesce(started_at, created_at, now()),
    last_active_at = coalesce(last_active_at, updated_at, created_at, now()),
    updated_at = coalesce(updated_at, created_at, now()),
    completed_at = case
        when state = 'completed' and completed_at is null then coalesce(updated_at, now())
        else completed_at
    end;

alter table cooking_sessions
    alter column user_id set default 'local-user-1';

alter table cooking_sessions
    alter column state set default 'active';

alter table cooking_sessions
    alter column current_phase set default 'prep';

alter table cooking_sessions
    alter column current_step_number set default 1;

alter table cooking_sessions
    alter column guidance_mode set default 'listen_only';

alter table cooking_sessions
    alter column session_locale set default 'en-KE';

alter table cooking_sessions
    alter column ambience_enabled set default true;

alter table cooking_sessions
    alter column ambience_mood_tag set default 'calm_dining';

alter table cooking_sessions
    alter column audio_muted set default false;

alter table cooking_sessions
    alter column audio_ducking_active set default true;

alter table cooking_sessions
    alter column audio_requested_volume set default 0.35;

alter table cooking_sessions
    alter column completed set default false;

alter table cooking_sessions
    alter column created_at set default now();

alter table cooking_sessions
    alter column updated_at set default now();

alter table cooking_sessions
    alter column last_active_at set default now();

comment on column cooking_sessions.ambience_enabled is
'Legacy compatibility column. session_audio_state.ambient_enabled is the intended source of truth.';

comment on column cooking_sessions.audio_muted is
'Legacy compatibility column. session_audio_state.muted is the intended source of truth.';

comment on column cooking_sessions.audio_ducking_active is
'Legacy compatibility column. session_audio_state.ducking_active is the intended source of truth.';

comment on column cooking_sessions.audio_requested_volume is
'Legacy compatibility column. session_audio_state.requested_volume is the intended source of truth.';

comment on column cooking_sessions.completed is
'Legacy compatibility column. state = ''completed'' is the intended source of truth.';

commit;
