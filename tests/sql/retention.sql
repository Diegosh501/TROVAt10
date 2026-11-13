-- Actual PostgreSQL regression. Local/staging only; always ROLLBACK.
-- No production data may be present. No real identity or payment is created.
begin;
do $$ begin
  if exists(select 1 from auth.users) or exists(select 1 from public.events) then
    raise exception 'retention_regression_refused_on_populated_database'; end if;
end $$;
create temporary table retention_fixture(
  host_id uuid default gen_random_uuid(),free_id uuid default gen_random_uuid(),premium_id uuid default gen_random_uuid(),
  fresh uuid default gen_random_uuid(),purgeable uuid default gen_random_uuid(),needs_archive uuid default gen_random_uuid(),
  kept uuid default gen_random_uuid(),removed uuid default gen_random_uuid(),reported uuid default gen_random_uuid(),
  held uuid default gen_random_uuid(),unknown_plan uuid default gen_random_uuid(),active uuid default gen_random_uuid(),
  notice_id uuid default gen_random_uuid(),public_future uuid default gen_random_uuid(),claims jsonb,result jsonb
) on commit drop;
insert into retention_fixture default values;
grant select on retention_fixture to authenticated,anon,service_role;
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select uid,'retention-'||uid||'@example.invalid',now(),'{"provider":"google","providers":["google"]}','{}'
from retention_fixture f cross join lateral(values(f.host_id),(f.free_id),(f.premium_id)) users(uid);
insert into public.profiles(id,username,role,age_confirmed_at,terms_accepted_at,privacy_notice_ack_at,terms_version,privacy_notice_version)
select uid,'qa_retention_'||left(replace(uid::text,'-',''),8),case when uid=f.host_id then 'host' else 'sportivo' end,
  now(),now(),now(),'regression','regression'
from retention_fixture f cross join lateral(values(f.host_id),(f.free_id),(f.premium_id)) users(uid);
insert into public.subscriptions(user_id,plan,status,current_period_end)
select uid,case when uid=f.premium_id then 'premium' else 'free' end,'active',
  case when uid=f.premium_id then now()+interval '1 year' else null end
from retention_fixture f cross join lateral(values(f.host_id),(f.free_id),(f.premium_id)) users(uid);
-- Live sessions are explicit and survive service-only maintenance tests.
insert into auth.sessions(id,user_id,aal,not_after)
select uid,uid,'aal1',now()+interval '1 hour' from retention_fixture f
  cross join lateral(values(f.host_id),(f.free_id),(f.premium_id)) users(uid);
update retention_fixture set claims=jsonb_build_object('sub',host_id,'session_id',host_id,'role','authenticated');
select set_config('request.jwt.claims',(select claims::text from retention_fixture),true);
-- 1. Every maintenance/control function is denied to ordinary public roles.
do $$ begin
  if has_function_privilege('anon','public.run_event_retention(integer)','execute') or
    has_function_privilege('authenticated','public.run_event_retention(integer)','execute') or
    has_function_privilege('authenticated','public.configure_event_retention_cron(boolean)','execute') or
    has_function_privilege('authenticated','public.set_event_retention_hold(uuid,text,timestamptz)','execute') or
    has_table_privilege('authenticated','private.event_retention_holds','select') then raise exception 'retention_privilege_bypass'; end if;
end $$;
-- 2. Closure is actual server time, regardless of creation/planned-start time.
insert into public.events(id,creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission,created_at)
select fresh,host_id,'Fixture newly closed',5,'Amichevole',now()+interval '1 day','Campo privato','Roma',10,'private','approval',now()-interval '90 days' from retention_fixture;
set local role authenticated;
select public.update_event_status(fresh,'in_progress') from retention_fixture;
select public.update_event_status(fresh,'completed') from retention_fixture;
reset role;
do $$ begin if (select closed_at from public.events where id=(select fresh from retention_fixture)) is distinct from now()
  then raise exception 'closure_not_server_time'; end if; end $$;
-- 3. Closure timestamps are immutable and terminal events cannot be reopened.
do $$ begin
  begin update public.events set closed_at=now()+interval '100 days' where id=(select fresh from retention_fixture);
    raise exception 'closure_clock_spoofed'; exception when insufficient_privilege then null; end;
  begin update public.events set status='scheduled' where id=(select fresh from retention_fixture);
    raise exception 'terminal_event_reopened'; exception when invalid_parameter_value then null; end;
end $$;
-- Privileged temporal fixtures only, within this rollback transaction. Disable
-- ONLY this migration's stamp while seeding historic dates, then restore it.
alter table public.events disable trigger a_event_lifecycle_stamp;
insert into public.events(id,creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission,status,closed_at,archived_at)
select event_id,owner_id,label,5,'Amichevole',now()-interval '10 days','Campo storico','Roma',10,'private','approval','completed',
  now()-interval '9 days',case when already_archived then now()-interval '25 hours' else null end
from retention_fixture f cross join lateral(values
  (f.purgeable,f.host_id,'Fixture physical purge',true),
  (f.needs_archive,f.host_id,'Fixture first archive',false),
  (f.kept,f.host_id,'Fixture premium keeper',false),
  (f.removed,f.host_id,'Fixture removed premium',true),
  (f.reported,f.host_id,'Fixture retained report',true),
  (f.held,f.host_id,'Fixture retained legal hold',true),
  (f.unknown_plan,f.free_id,'Fixture unknown legacy plan',true)
) rows(event_id,owner_id,label,already_archived);
insert into public.events(id,creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission,status,created_at)
select active,host_id,'Fixture still in progress',5,'Amichevole',now()-interval '30 days','Campo attivo','Roma',10,'private','approval','in_progress',now()-interval '35 days' from retention_fixture;
alter table public.events enable trigger a_event_lifecycle_stamp;
insert into public.event_members(event_id,user_id,state)
select kept,free_id,'approved' from retention_fixture union all select kept,premium_id,'approved' from retention_fixture
union all select removed,premium_id,'removed' from retention_fixture;
insert into public.player_reports(event_id,reporter_id,subject_id,reason,details)
select reported,host_id,free_id,'Altro problema di sicurezza','Synthetic report retained for a rollback regression.' from retention_fixture;
select public.set_event_retention_hold(held,'legal_preservation',now()+interval '30 days') from retention_fixture;
insert into public.app_notifications(id,user_id,event_id,type,title,body,dedupe_key)
select notice_id,free_id,kept,'event_updated','Synthetic history','Synthetic retained notification','retention-fixture' from retention_fixture;
insert into public.event_invites(event_id,token_hash,expires_at)
select purgeable,extensions.digest(convert_to(repeat('a',64),'UTF8'),'sha256'),now()+interval '1 day' from retention_fixture;
-- Missing legacy billing state must pause physical purge rather than guess.
delete from public.subscriptions where user_id=(select free_id from retention_fixture);
-- 4. Free owner/member cannot see expired history even while Premium retains it.
set local role authenticated;
do $$ begin if exists(select 1 from public.event_feed() where id=(select kept from retention_fixture)) then
  raise exception 'free_host_old_history_visible'; end if;
  if not exists(select 1 from public.event_feed() where id=(select fresh from retention_fixture)) then
    raise exception 'new_closure_hidden_based_on_old_creation'; end if;
end $$;
reset role;
select set_config('request.jwt.claims',(select jsonb_build_object('sub',free_id,'session_id',free_id,'role','authenticated')::text from retention_fixture),true);
set local role authenticated;
do $$ begin
  if exists(select 1 from public.event_members where event_id=(select kept from retention_fixture)) then raise exception 'expired_roster_side_channel'; end if;
  if exists(select 1 from public.app_notifications where id=(select notice_id from retention_fixture)) then raise exception 'expired_notice_side_channel'; end if;
end $$;
reset role;
-- 5. An admitted Premium player retains history even with a Free organizer.
select set_config('request.jwt.claims',(select jsonb_build_object('sub',premium_id,'session_id',premium_id,'role','authenticated')::text from retention_fixture),true);
set local role authenticated;
do $$ begin
  if not exists(select 1 from public.event_feed() where id=(select kept from retention_fixture) and venue='Campo storico') then
    raise exception 'premium_admitted_history_missing'; end if;
  if exists(select 1 from public.event_feed() where id=(select removed from retention_fixture)) then
    raise exception 'removed_premium_extended_unadmitted_history'; end if;
end $$;
reset role;
-- 6. An unexpired bearer token cannot revive expired match history.
set local role anon;
do $$ begin if exists(select 1 from public.get_event_invitation(repeat('a',64))) then raise exception 'invite_revived_expired_event'; end if; end $$;
reset role;
-- 7. Unknown future FK dependencies block physical deletion, including cascades.
create table private.qa_unknown_retention_dependency(event_id uuid references public.events(id) on delete cascade);
alter table private.qa_unknown_retention_dependency enable row level security;
update retention_fixture set result=public.run_event_retention();
do $$ begin
  if not ((select result from retention_fixture)->>'dependencyBlocked')::boolean then raise exception 'unknown_dependency_ignored'; end if;
  if not exists(select 1 from public.events where id=(select purgeable from retention_fixture)) then raise exception 'purged_despite_unknown_dependency'; end if;
  if (select archived_at from public.events where id=(select needs_archive from retention_fixture)) is null then raise exception 'archive_job_did_not_run'; end if;
end $$;
drop table private.qa_unknown_retention_dependency;
-- 8. Physical purge observes grace, paid ownership, reports, explicit hold and unknown plan.
update retention_fixture set result=public.run_event_retention();
do $$ begin
  if exists(select 1 from public.events where id=(select purgeable from retention_fixture)) then raise exception 'eligible_event_not_purged'; end if;
  if exists(select 1 from public.events where id=(select removed from retention_fixture)) then raise exception 'removed_premium_wrongly_preserved'; end if;
  if exists(select 1 from public.event_invites where event_id=(select purgeable from retention_fixture)) then raise exception 'dependent_invite_not_cascaded'; end if;
  if (select count(*) from public.events where id in(select needs_archive from retention_fixture union all select kept from retention_fixture
    union all select reported from retention_fixture union all select held from retention_fixture union all select unknown_plan from retention_fixture
    union all select active from retention_fixture union all select fresh from retention_fixture))<>7 then raise exception 'protected_event_was_removed'; end if;
  if (select count(*) from auth.users)<>3 or (select count(*) from public.profiles)<>3 then raise exception 'retention_expired_accounts'; end if;
end $$;
-- 9. Repeated maintenance does not erase a newly archived event during its grace.
update retention_fixture set result=public.run_event_retention();
do $$ begin if ((select result from retention_fixture)->>'purged')::integer<>0 or
  not exists(select 1 from public.events where id=(select needs_archive from retention_fixture)) then raise exception 'grace_or_idempotency_failed'; end if; end $$;
-- 10. Expired Premium cannot retain history; a new archive gets its own grace.
update public.subscriptions set current_period_end=now()-interval '1 second' where user_id=(select premium_id from retention_fixture);
set local role authenticated;
do $$ begin if exists(select 1 from public.event_feed() where id=(select kept from retention_fixture)) then raise exception 'expired_premium_retained_view'; end if; end $$;
reset role;
select public.run_event_retention();
do $$ begin if (select archived_at from public.events where id=(select kept from retention_fixture)) is null then raise exception 'expired_premium_not_archived'; end if; end $$;
-- 11. Renewal during archival grace restores access and prevents deletion.
update public.subscriptions set current_period_end=now()+interval '365 days' where user_id=(select premium_id from retention_fixture);
set local role authenticated;
do $$ begin if not exists(select 1 from public.event_feed() where id=(select kept from retention_fixture)) then raise exception 'renewed_premium_grace_unavailable'; end if; end $$;
reset role;
select public.run_event_retention();
do $$ begin if (select archived_at from public.events where id=(select kept from retention_fixture)) is not null then raise exception 'renewed_premium_not_restored'; end if; end $$;
-- 12. Malformed batch/hold values fail before work; no Cron claim without extension.
do $$ begin
  begin perform public.run_event_retention(0); raise exception 'zero_batch_accepted'; exception when invalid_parameter_value then null; end;
  begin perform public.set_event_retention_hold((select held from retention_fixture),'legal_preservation',now()-interval '1 day');
    raise exception 'expired_hold_accepted'; exception when invalid_parameter_value then null; end;
  if to_regnamespace('cron') is null then
    begin perform public.configure_event_retention_cron(true); raise exception 'cron_activation_reported_without_extension';
    exception when object_not_in_prerequisite_state then null; end;
  end if;
end $$;
-- 13. A banned account cannot keep private history through an old valid JWT.
update auth.users set banned_until=now()+interval '1 hour' where id=(select host_id from retention_fixture);
select set_config('request.jwt.claims',(select jsonb_build_object('sub',host_id,'session_id',host_id,'role','authenticated')::text from retention_fixture),true);
set local role authenticated;
do $$ begin if exists(select 1 from public.event_feed()) then raise exception 'banned_jwt_feed_access'; end if; end $$;
reset role;
update auth.users set banned_until=null where id=(select host_id from retention_fixture);
-- 14. Genuine anonymous discovery of upcoming public events stays available.
insert into public.events(id,creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission)
select public_future,host_id,'Fixture public discovery',5,'Amichevole',now()+interval '1 day','Campo pubblico','Roma',10,'public','approval' from retention_fixture;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claims','{"role":"anon"}',true);
set local role anon;
do $$ begin if not exists(select 1 from public.event_feed() where id=(select public_future from retention_fixture)) then
  raise exception 'anonymous_public_discovery_blocked'; end if; end $$;
reset role;
rollback;
