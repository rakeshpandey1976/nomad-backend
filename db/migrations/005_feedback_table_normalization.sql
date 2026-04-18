begin;

create extension if not exists pgcrypto;

alter table user_feedback
    alter column category drop not null;

alter table user_feedback
    alter column category set default 'general';

alter table user_feedback
    alter column note set default '';

update user_feedback
set
    feedback_id = coalesce(feedback_id, gen_random_uuid()),
    user_id = coalesce(user_id, 'local-user-1'),
    feedback_category = coalesce(feedback_category, category, 'general'),
    feedback_text = coalesce(feedback_text, note, ''),
    device_context_json = coalesce(device_context_json, '{}'::jsonb),
    category = coalesce(category, feedback_category, 'general'),
    note = coalesce(note, feedback_text, '');

alter table user_feedback
    alter column feedback_id set default gen_random_uuid();

alter table user_feedback
    alter column feedback_category set default 'general';

alter table user_feedback
    alter column feedback_text set default '';

alter table user_feedback
    alter column device_context_json set default '{}'::jsonb;

alter table user_feedback
    alter column feedback_id set not null;

alter table user_feedback
    alter column feedback_category set not null;

alter table user_feedback
    alter column device_context_json set not null;

create index if not exists idx_user_feedback_user_id
    on user_feedback(user_id);

commit;
