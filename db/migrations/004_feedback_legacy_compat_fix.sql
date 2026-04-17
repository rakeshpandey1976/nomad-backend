begin;

alter table user_feedback
    alter column category drop not null;

alter table user_feedback
    alter column category set default 'general';

update user_feedback
set category = coalesce(category, feedback_category, 'general');

commit;
