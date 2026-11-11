-- Destructive behaviour is exercised ONLY inside this empty synthetic fixture.
-- Always rollback. Never run against populated or live-user data.
begin;
do $$ begin
  if exists(select 1 from auth.users) or exists(select 1 from public.events) then
    raise exception 'account_lifecycle_test_requires_empty_database'; end if;
end $$;
create temporary table lifecycle_fixture(name text primary key,id uuid default gen_random_uuid(),sid uuid default gen_random_uuid(),event_id uuid,first_stamp timestamptz) on commit drop;
insert into lifecycle_fixture(name) values('host'),('sportivo'),('purge'),('premium'),('admin'),('reported'),('billing'),('active'),('storage'),('unknown');
grant select on lifecycle_fixture to authenticated,anon;
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data)
  select id,name||'@example.invalid',now(),'{"provider":"google"}' from lifecycle_fixture;
insert into public.profiles(id,username,role,age_confirmed_at,terms_accepted_at,privacy_notice_ack_at,terms_version,privacy_notice_version)
  select id,'qa_life_'||name,case when name='sportivo' then 'sportivo' else 'host' end,now(),now(),now(),'regression','regression' from lifecycle_fixture;
insert into public.subscriptions(user_id,plan,status) select id,'free','active' from lifecycle_fixture;
insert into auth.sessions(id,user_id) select sid,id from lifecycle_fixture;
create function pg_temp.claim(who text) returns void language sql as $$
  select set_config('request.jwt.claims',jsonb_build_object('sub',id,'role','authenticated','session_id',sid)::text,true)
    from lifecycle_fixture where name=who
$$;
create function pg_temp.make_match(who text) returns uuid language plpgsql as $$
declare e uuid;
begin
  insert into public.events(creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission)
    select id,'Partita QA ciclo account',5,'Amichevole',now()+interval '1 day','Campo QA','Roma',10,'public','approval'
      from lifecycle_fixture where name=who returning id into e;
  return e;
end $$;

-- 1. Off by default, narrow caller API, service-only controls and private state.
do $$ begin
  if (select enabled or purge_enabled from private.account_lifecycle_settings) then raise exception 'unsafe_default'; end if;
  if public.run_account_retention()->>'skipped'<>'disabled' then raise exception 'disabled_worker_not_noop'; end if;
  if has_table_privilege('authenticated','private.account_lifecycle','select')
    or has_table_privilege('authenticated','private.account_lifecycle_settings','update')
    or has_function_privilege('authenticated','public.run_account_retention(integer)','execute')
    or has_function_privilege('anon','public.my_account_lifecycle()','execute')
    or has_function_privilege('authenticated','public.set_account_lifecycle_enabled(boolean,boolean,text)','execute')
    or has_function_privilege('authenticated','public.set_account_retention_hold(uuid,text,timestamptz)','execute')
    or has_function_privilege('authenticated','public.configure_account_retention_cron(boolean)','execute') then raise exception 'client_control_leak'; end if;
  if not private.account_deletion_dependencies_known() then raise exception 'known_dependency_graph_rejected'; end if;
end $$;

-- 2. Explicit acknowledgement, live session, idempotent timestamp, no timer yet.
select pg_temp.claim('host');
set local role authenticated;
select public.acknowledge_account_lifecycle('trovat1o-account-2026-11-11-v1');
select public.acknowledge_account_lifecycle('trovat1o-account-2026-11-11-v1');
do $$ begin
  if (public.my_account_lifecycle()->>'firstMatchAt') is not null then raise exception 'ack_started_clock'; end if;
  begin perform public.acknowledge_account_lifecycle('wrong-policy');raise exception 'stale_policy_accepted';
  exception when invalid_parameter_value then null; end;
end $$;
reset role;
update auth.sessions set not_after=now()-interval '1 second' where user_id=(select id from lifecycle_fixture where name='host');
set local role authenticated;
do $$ begin
  begin perform public.my_account_lifecycle();raise exception 'revoked_session_accepted';
  exception when sqlstate 'PT401' then null; end;
end $$;
reset role;
update auth.sessions set not_after=null;

-- 3. Joining does not start any clock. Creation stamps now; cancellation,
-- deleting the event, repeated acknowledgements and role switches cannot reset it.
-- Model an ACK committed after the creation transaction began. This proves the
-- timestamp boundary on one connection, not a real concurrent RPC exchange.
select pg_sleep(0.01);
update private.account_lifecycle set acknowledged_at=clock_timestamp() where user_id=(select id from lifecycle_fixture where name='host');
update lifecycle_fixture set event_id=pg_temp.make_match('host') where name='host';
update lifecycle_fixture f set first_stamp=l.first_match_at from private.account_lifecycle l where l.user_id=f.id;
insert into public.event_members(event_id,user_id,state)
  select h.event_id,s.id,'approved' from lifecycle_fixture h cross join lifecycle_fixture s where h.name='host' and s.name='sportivo';
do $$ begin
  if exists(select 1 from private.account_lifecycle where user_id=(select id from lifecycle_fixture where name='sportivo')) then raise exception 'join_started_clock'; end if;
  if exists(select 1 from private.account_lifecycle where user_id=(select id from lifecycle_fixture where name='host')
    and (first_match_at<acknowledged_at or first_match_at<now() or first_match_at>clock_timestamp())) then raise exception 'clock_not_server_time'; end if;
end $$;
update public.events set status='cancelled' where creator_id=(select id from lifecycle_fixture where name='host');
delete from public.events where creator_id=(select id from lifecycle_fixture where name='host');
update public.profiles set role='sportivo' where id=(select id from lifecycle_fixture where name='host');
update public.profiles set role='host' where id=(select id from lifecycle_fixture where name='host');
select pg_temp.claim('host');
select public.acknowledge_account_lifecycle('trovat1o-account-2026-11-11-v1');
do $$ begin
  if (select first_match_at from private.account_lifecycle where user_id=(select id from lifecycle_fixture where name='host')) is distinct from (select first_stamp from lifecycle_fixture where name='host') then raise exception 'clock_reset'; end if;
  if (public.export_my_data('profile')->'rows'->0->'accountLifecycle'->>'firstMatchAt')::timestamptz is distinct from (select first_stamp from lifecycle_fixture where name='host') then
    raise exception 'lifecycle_not_in_subject_export'; end if;
end $$;

-- 4. Activation requires an acknowledgement even through direct server RPC paths.
select public.set_account_lifecycle_enabled(true,false,'trovat1o-account-2026-11-11-v1');
do $$ begin
  begin perform pg_temp.make_match('unknown');raise exception 'missing_ack_bypassed';
  exception when sqlstate 'PT403' then null; end;
  if exists(select 1 from private.account_lifecycle where user_id=(select id from lifecycle_fixture where name='unknown')) then raise exception 'failed_creation_started_clock'; end if;
end $$;

-- Prepare expiry fixtures as an operator, not through public account fields.
insert into private.account_lifecycle(user_id,acknowledged_at,policy_version,first_match_at,first_notice_at)
  select id,now()-interval '10 days','trovat1o-account-2026-11-11-v1',now()-interval '9 days',now()-interval '9 days'
    from lifecycle_fixture where name not in ('host','sportivo');

-- 5. Exact boundary: no expiry just before seven days, expiry at seven days;
-- creating/asking again is blocked, while withdrawal and closing stay available.
update private.account_lifecycle set acknowledged_at=now()-interval '8 days',first_match_at=now()-interval '7 days'+interval '1 second'
  where user_id=(select id from lifecycle_fixture where name='host');
do $$ begin if private.account_lifecycle_expired((select id from lifecycle_fixture where name='host')) then raise exception 'early_expiry'; end if; end $$;
update private.account_lifecycle set first_match_at=now()-interval '7 days' where user_id=(select id from lifecycle_fixture where name='host');
do $$ begin
  if not private.account_lifecycle_expired((select id from lifecycle_fixture where name='host')) then raise exception 'boundary_not_expired'; end if;
  begin perform pg_temp.make_match('host');raise exception 'expired_created_match';exception when sqlstate 'PT403' then null;end;
end $$;
-- Temporarily protect the active fixture only to construct its actual event.
update public.subscriptions set plan='premium',current_period_end=now()+interval '1 day' where user_id=(select id from lifecycle_fixture where name='active');
update lifecycle_fixture set event_id=pg_temp.make_match('active') where name='active';
update public.subscriptions set plan='free',current_period_end=null where user_id=(select id from lifecycle_fixture where name='active');
select pg_temp.claim('host');
do $$ begin
  begin insert into public.event_members(event_id,user_id,state) select a.event_id,h.id,'pending' from lifecycle_fixture a cross join lifecycle_fixture h where a.name='active' and h.name='host';
    raise exception 'expired_joined';exception when sqlstate 'PT403' then null;end;
end $$;
insert into public.event_members(event_id,user_id,state) select a.event_id,h.id,'removed' from lifecycle_fixture a cross join lifecycle_fixture h where a.name='active' and h.name='host';
update public.event_members set state='removed' where user_id=(select id from lifecycle_fixture where name='host');

-- 6. Verified future Premium and private Admin allowlist exclude expiry.
update public.subscriptions set plan='premium',current_period_end=now()+interval '1 year' where user_id=(select id from lifecycle_fixture where name='premium');
insert into private.platform_admins(user_id,enabled) select id,false from lifecycle_fixture where name='admin';
do $$ begin
  if private.account_lifecycle_expired((select id from lifecycle_fixture where name='premium'))
    or private.account_lifecycle_expired((select id from lifecycle_fixture where name='admin')) then raise exception 'protected_account_expired';end if;
end $$;

-- 7. Warning is server-generated and idempotent; no immediate physical purge.
select public.run_account_retention(100);
do $$ begin
  if (select count(*) from auth.users)<>10 then raise exception 'warning_deleted_user';end if;
  if not exists(select 1 from public.app_notifications where user_id=(select id from lifecycle_fixture where name='purge') and type='account_deletion') then raise exception 'warning_missing';end if;
end $$;
select public.run_account_retention(100);
do $$ begin
  if (select count(*) from public.app_notifications where user_id=(select id from lifecycle_fixture where name='purge') and type='account_deletion')<>1 then raise exception 'duplicate_warning';end if;
end $$;
select public.set_account_lifecycle_enabled(true,true,'trovat1o-account-2026-11-11-v1');
update private.account_lifecycle set next_check_at=now();
select public.run_account_retention(100);
do $$ begin if (select count(*) from auth.users)<>10 then raise exception 'grace_bypassed';end if;end $$;

-- 8. Preserve paid-account mappings, events, active participation, reports,
-- unknown plans, legal/support holds and storage ownership, not just Auth FKs.
insert into private.billing_accounts(user_id,mode,customer_id) select id,'live','cus_QALifecycle' from lifecycle_fixture where name='billing';
select pg_temp.claim('sportivo');
insert into public.event_members(event_id,user_id,state) select a.event_id,u.id,'approved' from lifecycle_fixture a cross join lifecycle_fixture u where a.name='active' and u.name='reported';
insert into public.player_reports(event_id,reporter_id,subject_id,reason,details)
  select a.event_id,r.id,s.id,'Altro problema di sicurezza','Fixture sintetico per conservazione necessaria.'
    from lifecycle_fixture a cross join lifecycle_fixture r cross join lifecycle_fixture s where a.name='active' and r.name='reported' and s.name='sportivo';
delete from public.subscriptions where user_id=(select id from lifecycle_fixture where name='unknown');
create schema storage;
create table storage.objects(id uuid primary key default gen_random_uuid(),owner_id text);
insert into storage.objects(owner_id) select id::text from lifecycle_fixture where name='storage';
select public.set_account_retention_hold((select id from lifecycle_fixture where name='host'),'legal_preservation',now()+interval '1 day');
-- Renewal of an expired existing hold uses the same path and must preserve it.
update private.account_retention_holds set hold_until=now()-interval '1 second';
select public.set_account_retention_hold((select id from lifecycle_fixture where name='host'),'legal_preservation',now()+interval '2 days');
do $$ begin
  if private.account_deletion_hold((select id from lifecycle_fixture where name='billing'))<>'billing'
    or private.account_deletion_hold((select id from lifecycle_fixture where name='active'))<>'owned_match'
    or private.account_deletion_hold((select id from lifecycle_fixture where name='reported'))<>'safety_report'
    or private.account_deletion_hold((select id from lifecycle_fixture where name='unknown'))<>'unknown_plan'
    or private.account_deletion_hold((select id from lifecycle_fixture where name='host'))<>'preservation'
    or private.account_deletion_hold((select id from lifecycle_fixture where name='storage'))<>'storage' then raise exception 'dependency_hold_missing';end if;
end $$;

-- 9. An unknown CASCADE, including a transitively linked dependency, fails closed.
create table private.unknown_account_child(id uuid references public.profiles(id) on delete cascade);
update private.account_lifecycle set deletion_notice_at=now()-interval '49 hours',next_check_at=now();
select public.run_account_retention(100);
do $$ begin
  if private.account_deletion_dependencies_known() then raise exception 'unknown_cascade_accepted';end if;
  if (select count(*) from auth.users)<>10 then raise exception 'unknown_dependency_deleted_user';end if;
end $$;
drop table private.unknown_account_child;

-- 10. Atomic deletion after notice+grace removes Auth/session/profile together.
-- It neither removes active/shared records nor resurrects a deleted account via JWT.
update private.account_lifecycle set next_check_at=now();
select public.run_account_retention(100);
do $$ begin
  if exists(select 1 from auth.users where id=(select id from lifecycle_fixture where name='purge'))
    or exists(select 1 from auth.sessions where user_id=(select id from lifecycle_fixture where name='purge'))
    or exists(select 1 from public.profiles where id=(select id from lifecycle_fixture where name='purge')) then raise exception 'auth_delete_not_complete';end if;
  if (select count(*) from auth.users)<>9 then raise exception 'protected_account_deleted';end if;
  if (select count(*) from public.events)<>1 then raise exception 'shared_event_changed';end if;
end $$;
select pg_temp.claim('purge');
do $$ begin if public.is_email_confirmed() then raise exception 'old_deleted_jwt_accepted';end if;end $$;

-- 11. Known-but-held oldest accounts rotate, avoiding starvation of later rows.
update private.account_lifecycle set next_check_at=now()-interval '1 hour';
select public.run_account_retention(1);
do $$ begin
  if (select count(*) from private.account_lifecycle where first_match_at<=now()-interval '7 days' and next_check_at>now())<>1 then raise exception 'held_row_not_rotated';end if;
end $$;

-- 12. No start date for join-only Sportivo, no silent expiry of undisclosed
-- legacy records, no null-Premium bypass, bounded configuration and batches.
do $$ begin
  if exists(select 1 from private.account_lifecycle where user_id=(select id from lifecycle_fixture where name='sportivo')) then raise exception 'participant_has_timer';end if;
  if exists(select 1 from private.account_lifecycle where user_id=(select id from lifecycle_fixture where name='premium') and deletion_notice_at is not null) then raise exception 'premium_warned';end if;
  begin perform public.run_account_retention(0);raise exception 'invalid_limit_accepted';exception when invalid_parameter_value then null;end;
  begin perform public.set_account_lifecycle_enabled(false,true,'trovat1o-account-2026-11-11-v1');raise exception 'unsafe_config_accepted';exception when invalid_parameter_value then null;end;
  begin perform public.configure_account_retention_cron(true);raise exception 'missing_cron_accepted';exception when sqlstate '55000' then null;end;
  begin perform public.set_account_retention_hold(gen_random_uuid(),'legal_preservation',now()+interval '1 day');raise exception 'missing_account_hold_accepted';exception when no_data_found then null;end;
end $$;
select public.set_account_lifecycle_enabled(false,false,'trovat1o-account-2026-11-11-v1');
do $$ begin if public.run_account_retention()->>'skipped'<>'disabled' then raise exception 'disable_did_not_stop_worker';end if;end $$;
rollback;
