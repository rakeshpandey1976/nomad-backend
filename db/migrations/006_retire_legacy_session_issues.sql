begin;

create extension if not exists pgcrypto;

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
            si.session_id,
            si.issue_type,
            null,
            si.recovery_text,
            null,
            si.created_at
        from session_issues si
        where not exists (
            select 1
            from session_issue_reports sir
            where sir.session_id = si.session_id
              and sir.issue_type = si.issue_type
              and sir.created_at = si.created_at
        );
    end if;

    if exists (
        select 1
        from information_schema.tables
        where table_schema = 'public'
          and table_name = 'session_issues'
    ) and not exists (
        select 1
        from information_schema.tables
        where table_schema = 'public'
          and table_name = 'session_issues_legacy'
    ) then
        alter table session_issues rename to session_issues_legacy;
    end if;
end
$$;

commit;
