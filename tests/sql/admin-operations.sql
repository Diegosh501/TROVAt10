-- Local/staging regression with synthetic users and no provider calls.
-- Refuses populated Auth/event databases; all fixtures and DDL roll back.
begin;
do $$ begin
  if exists(select 1 from auth.users) or exists(select 1 from public.events) then
    raise exception 'admin_operations_refused_on_populated_database';
  end if;
end $$;
create temporary table ops_fixture (
  admin_id uuid default gen_random_uuid(),host_id uuid default gen_random_uuid(),player_id uuid default gen_random_uuid(),
  session_id uuid default gen_random_uuid(),factor_id uuid default gen_random_uuid(),
  event_id uuid default gen_random_uuid(),finished_id uuid default gen_random_uuid(),report_id uuid default gen_random_uuid(),
  claims jsonb,audit_count integer,quota_count integer
) on commit drop;
insert into ops_fixture default values;
grant select on ops_fixture to authenticated,anon,service_role;
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select uid,'ops-'||uid||'@example.invalid',now(),'{"provider":"google","providers":["google"]}','{}'
from ops_fixture f cross join lateral(values(f.admin_id),(f.host_id),(f.player_id)) users(uid);
insert into auth.identities(provider_id,user_id,identity_data,provider,created_at,updated_at)
select uid::text,uid,jsonb_build_object('sub',uid,'email_verified',true),'google',now(),now()
from ops_fixture f cross join lateral(values(f.admin_id),(f.host_id),(f.player_id)) users(uid);
insert into public.profiles(id,username,role,age_confirmed_at,terms_accepted_at,privacy_notice_ack_at,terms_version,privacy_notice_version)
select uid,'qa_ops_'||left(replace(uid::text,'-',''),8),case when uid=f.player_id then 'sportivo' else 'host' end,
  now(),now(),now(),'regression','regression'
from ops_fixture f cross join lateral(values(f.admin_id),(f.host_id),(f.player_id)) users(uid);
insert into public.subscriptions(user_id,plan,status)
select uid,'free','active' from ops_fixture f cross join lateral(values(f.admin_id),(f.host_id),(f.player_id)) users(uid);
insert into auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at)
select factor_id,admin_id,'totp','verified',now(),now() from ops_fixture;
insert into auth.sessions(id,user_id,created_at,updated_at,factor_id,aal,not_after)
select session_id,admin_id,now(),now(),factor_id,'aal2',now()+interval '1 hour' from ops_fixture;
update ops_fixture set claims=jsonb_build_object('sub',admin_id,'role','authenticated','session_id',session_id,
  'aal','aal2','amr',jsonb_build_array(jsonb_build_object('method','totp','timestamp',extract(epoch from now()))));
insert into public.events(id,creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission)
select eid,host_id,label,5,'Amichevole',now()+interval '2 days','Synthetic private exact venue','Synthetic city',10,'private','approval'
from ops_fixture f cross join lateral(values(f.event_id,'Moderation private match'),(f.finished_id,'Finished moderation match')) events(eid,label);
update public.events set status='in_progress' where id=(select finished_id from ops_fixture);
update public.events set status='completed' where id=(select finished_id from ops_fixture);
insert into public.player_reports(id,event_id,reporter_id,subject_id,reason,details)
select report_id,event_id,host_id,player_id,'Altro problema di sicurezza','Synthetic moderation report used only in rollback tests.' from ops_fixture;
set local role service_role;
select public.provision_platform_admin(admin_id,true) from ops_fixture;
reset role;

create function pg_temp.call_admin_operation(p_name text) returns void language plpgsql as $$
begin
  case p_name
    when 'users' then perform public.admin_users();
    when 'events' then perform public.admin_events();
    when 'reports' then perform public.admin_reports();
    when 'role' then perform public.admin_set_user_role((select host_id from ops_fixture),'sportivo');
    when 'review' then perform public.admin_review_report((select report_id from ops_fixture),'in_review','Synthetic review');
    when 'cancel' then perform public.admin_cancel_event((select event_id from ops_fixture));
    else raise exception 'invalid_test_operation';
  end case;
end $$;
create function pg_temp.expect_op_error(p_operation text,p_message text,p_code text) returns void language plpgsql as $$
begin
  begin perform pg_temp.call_admin_operation(p_operation);
  exception when others then
    if sqlerrm<>p_message or sqlstate<>p_code then raise exception 'Expected %/% for %, got %/%',p_message,p_code,p_operation,sqlerrm,sqlstate; end if;
    return;
  end;
  raise exception 'Administrative operation bypass: %',p_operation;
end $$;
-- 1. Each endpoint denies anonymous execution at the grant boundary.
set local role anon;
do $$ declare name text; begin
  foreach name in array array['users','events','reports','role','review','cancel'] loop
    begin perform pg_temp.call_admin_operation(name); raise exception 'anonymous_operation_bypass';
    exception when insufficient_privilege then null; end;
  end loop;
end $$;
reset role;
-- 2. A normal Host cannot acquire moderation access from forged metadata/AAL.
select set_config('request.jwt.claims',(select (claims||jsonb_build_object('sub',host_id,'app_metadata',jsonb_build_object('role','admin')))::text from ops_fixture),true);
set local role authenticated;
do $$ declare name text; begin foreach name in array array['users','events','reports','role','review','cancel'] loop
  perform pg_temp.expect_op_error(name,'admin_required','PT403'); end loop; end $$;
reset role;
-- 3-5. Every new operation also enforces session existence and recent TOTP.
select set_config('request.jwt.claims',(select (claims||'{"aal":"aal1"}'::jsonb)::text from ops_fixture),true);
set local role authenticated;
do $$ declare name text; begin foreach name in array array['users','events','reports','role','review','cancel'] loop
  perform pg_temp.expect_op_error(name,'mfa_required','PT403'); end loop; end $$;
reset role;
select set_config('request.jwt.claims',(select (claims||jsonb_build_object('amr',jsonb_build_array(jsonb_build_object('method','totp','timestamp',extract(epoch from now())-901))))::text from ops_fixture),true);
set local role authenticated;
select pg_temp.expect_op_error('role','mfa_required','PT403');
reset role;
select set_config('request.jwt.claims',(select claims::text from ops_fixture),true);
update auth.sessions set not_after=now()-interval '1 second' where id=(select session_id from ops_fixture);
set local role authenticated;
select pg_temp.expect_op_error('cancel','session_revoked','PT401');
reset role;
update auth.sessions set not_after=now()+interval '1 hour' where id=(select session_id from ops_fixture);
-- 6. User listing contains only operational fields, never Auth emails/phones.
set local role authenticated;
do $$ declare result jsonb; item jsonb; key text; begin
  result:=public.admin_users();
  if (result->>'total')::integer<>3 or (result->>'limit')::integer<>25 then raise exception 'wrong_users_envelope'; end if;
  for item in select value from jsonb_array_elements(result->'rows') loop
    for key in select jsonb_object_keys(item) loop
      if key not in ('id','username','role','createdAt','plan','activeEvents') then raise exception 'unexpected_user_field: %',key; end if;
    end loop;
    if item->>'plan'<>'free' then raise exception 'unexpected_fixture_plan'; end if;
  end loop;
  if (public.admin_users('','sportivo')->>'total')::integer<>1 then raise exception 'role_filter_failed'; end if;
end $$;
-- 7. Private event oversight omits exact location/contact, filters correctly.
do $$ declare result jsonb; item jsonb; key text; begin
  result:=public.admin_events('Moderation private','scheduled');
  if (result->>'total')::integer<>1 then raise exception 'event_filter_failed'; end if;
  for item in select value from jsonb_array_elements(result->'rows') loop
    for key in select jsonb_object_keys(item) loop
      if key not in ('id','title','startsAt','format','status','visibility','creatorUsername') then raise exception 'unexpected_event_field: %',key; end if;
    end loop;
  end loop;
end $$;
-- 8. Reports expose only the moderation contract, excluding Auth details.
do $$ declare result jsonb; item jsonb; key text; begin
  result:=public.admin_reports('','received');
  if (result->>'total')::integer<>1 then raise exception 'report_filter_failed'; end if;
  for item in select value from jsonb_array_elements(result->'rows') loop
    for key in select jsonb_object_keys(item) loop
      if key not in ('id','eventId','subjectUsername','reporterUsername','reason','details','state','createdAt','reviewNote') then raise exception 'unexpected_report_field: %',key; end if;
    end loop;
  end loop;
end $$;
reset role;
-- 9. Invalid role input cannot promote Admin and rolls back audit/quota too.
update ops_fixture set audit_count=(select count(*) from private.admin_audit),quota_count=(select request_count from private.admin_action_quota where user_id=admin_id);
set local role authenticated;
do $$ begin
  begin perform public.admin_set_user_role((select host_id from ops_fixture),'admin'); raise exception 'admin_role_selectable';
  exception when invalid_parameter_value then null; end;
  begin perform public.admin_users('', 'admin',0); raise exception 'admin_role_filter_accepted';
  exception when invalid_parameter_value then null; end;
  begin perform public.admin_events('', '',-1); raise exception 'negative_offset_accepted';
  exception when invalid_parameter_value then null; end;
end $$;
reset role;
do $$ begin
  if (select count(*) from private.admin_audit)<>(select audit_count from ops_fixture)
    or (select request_count from private.admin_action_quota where user_id=(select admin_id from ops_fixture))<>(select quota_count from ops_fixture)
    or (select count(*) from private.platform_admins)<>1 then raise exception 'failed_input_left_audit_or_permission'; end if;
end $$;
-- 10. A successful operational role change affects the target and audit only.
set local role authenticated;
select public.admin_set_user_role(host_id,'sportivo') from ops_fixture;
reset role;
do $$ begin
  if (select role from public.profiles where id=(select host_id from ops_fixture))<>'sportivo'
    or not exists(select 1 from private.admin_audit where actor_id=(select admin_id from ops_fixture)
      and action='user_role_updated' and target_id=(select host_id from ops_fixture)) then raise exception 'role_change_or_audit_missing'; end if;
end $$;
-- 11. Report decisions store the supplied moderation note and actual review time.
set local role authenticated;
select public.admin_review_report(report_id,'actioned','Synthetic resolution') from ops_fixture;
reset role;
do $$ begin if not exists(select 1 from public.player_reports where id=(select report_id from ops_fixture)
  and state='actioned' and review_note='Synthetic resolution' and reviewed_at=now()) then raise exception 'report_review_not_saved'; end if; end $$;
-- 12. A platform Admin may cancel an event owned by another Host, preserving
-- creator ownership; lifecycle retention stamps the actual closure server-side.
set local role authenticated;
select public.admin_cancel_event(event_id) from ops_fixture;
reset role;
do $$ begin if not exists(select 1 from public.events where id=(select event_id from ops_fixture)
  and creator_id=(select host_id from ops_fixture) and status='cancelled' and closed_at=now()) then raise exception 'admin_cancellation_or_closure_failed'; end if; end $$;
-- 13. Cancellation is retry-safe; a completed match cannot be rewritten.
set local role authenticated;
select public.admin_cancel_event(event_id) from ops_fixture;
do $$ begin begin perform public.admin_cancel_event((select finished_id from ops_fixture)); raise exception 'completed_event_rewritten';
exception when invalid_parameter_value then null; end; end $$;
reset role;
-- 14. Not-found mutation cannot leave a successful audit row or consume quota.
update ops_fixture set audit_count=(select count(*) from private.admin_audit),quota_count=(select request_count from private.admin_action_quota where user_id=admin_id);
set local role authenticated;
do $$ begin begin perform public.admin_review_report(gen_random_uuid(),'in_review','Synthetic missing'); raise exception 'missing_report_accepted';
exception when sqlstate 'PT404' then null; end; end $$;
reset role;
do $$ begin if (select count(*) from private.admin_audit)<>(select audit_count from ops_fixture)
  or (select request_count from private.admin_action_quota where user_id=(select admin_id from ops_fixture))<>(select quota_count from ops_fixture)
  then raise exception 'failed_mutation_left_audit_or_quota'; end if; end $$;
-- 15. Failure to append the mandatory audit denies the mutation atomically.
alter table private.admin_audit add constraint synthetic_ops_audit_failure check(action<>'user_role_updated') not valid;
set local role authenticated;
do $$ begin begin perform public.admin_set_user_role((select host_id from ops_fixture),'host'); raise exception 'mutation_bypassed_audit_failure';
exception when check_violation then null; end; end $$;
reset role;
alter table private.admin_audit drop constraint synthetic_ops_audit_failure;
do $$ begin if (select role from public.profiles where id=(select host_id from ops_fixture))<>'sportivo'
  or (select count(*) from private.admin_audit)<>(select audit_count from ops_fixture) then raise exception 'audit_failure_changed_state'; end if; end $$;
-- 16. Revoking the allowlist removes all newly introduced operations immediately.
update private.platform_admins set enabled=false where user_id=(select admin_id from ops_fixture);
set local role authenticated;
do $$ declare name text; begin foreach name in array array['users','events','reports','role','review','cancel'] loop
  perform pg_temp.expect_op_error(name,'admin_required','PT403'); end loop; end $$;
reset role;
rollback;
