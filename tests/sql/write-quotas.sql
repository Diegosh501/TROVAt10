-- Local/staging only. Synthetic identities, real triggers/UPSERT, full rollback.
begin;
do $$ begin if exists(select 1 from auth.users) or exists(select 1 from public.events) then
  raise exception 'write_quota_regression_refused_on_populated_database'; end if; end $$;
create temporary table quota_fixture(host_id uuid default gen_random_uuid(),player_id uuid default gen_random_uuid(),
  admin_id uuid default gen_random_uuid(),event_id uuid default gen_random_uuid(),session_id uuid default gen_random_uuid(),
  factor_id uuid default gen_random_uuid(),admin_claims jsonb) on commit drop;
insert into quota_fixture default values;
grant select on quota_fixture to authenticated,anon,service_role;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claims','{}',true);
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select uid,'quota-'||uid||'@example.invalid',now(),'{"provider":"google","providers":["google"]}','{}'
from quota_fixture f cross join lateral(values(f.host_id),(f.player_id),(f.admin_id)) users(uid);
insert into auth.identities(provider_id,user_id,identity_data,provider,created_at,updated_at)
select uid::text,uid,jsonb_build_object('sub',uid,'email_verified',true),'google',now(),now()
from quota_fixture f cross join lateral(values(f.host_id),(f.player_id),(f.admin_id)) users(uid);
insert into public.profiles(id,username,role,age_confirmed_at,terms_accepted_at,privacy_notice_ack_at,terms_version,privacy_notice_version)
select uid,'qa_quota_'||left(replace(uid::text,'-',''),8),case when uid=f.player_id then 'sportivo' else 'host' end,
  now(),now(),now(),'regression','regression' from quota_fixture f cross join lateral(values(f.host_id),(f.player_id),(f.admin_id)) users(uid);
insert into public.subscriptions(user_id,plan,status)
select uid,'free','active' from quota_fixture f cross join lateral(values(f.host_id),(f.player_id),(f.admin_id)) users(uid);
insert into auth.mfa_factors(id,user_id,factor_type,status) select factor_id,admin_id,'totp','verified' from quota_fixture;
insert into auth.sessions(id,user_id,factor_id,aal,not_after) select session_id,admin_id,factor_id,'aal2',now()+interval '1 hour' from quota_fixture;
update quota_fixture set admin_claims=jsonb_build_object('sub',admin_id,'role','authenticated','session_id',session_id,'aal','aal2',
  'amr',jsonb_build_array(jsonb_build_object('method','totp','timestamp',extract(epoch from now()))));
set local role service_role;
select public.provision_platform_admin(admin_id,true) from quota_fixture;
reset role;
-- 1. Trusted no-UID setup/maintenance is not counted.
insert into public.events(id,creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission)
select event_id,host_id,'Quota shared match',5,'Amichevole',now()+interval '2 days','Synthetic venue','Roma',10,'public','open' from quota_fixture;
insert into public.event_members(event_id,user_id,state) select event_id,player_id,'pending' from quota_fixture;
do $$ begin if exists(select 1 from private.write_action_quotas) then raise exception 'null_uid_counted'; end if; end $$;
-- 2. The only callable helper is narrow cleanup for service-role; clients may
-- not choose action/user, write counters or invoke private trigger functions.
do $$ begin
  if has_table_privilege('authenticated','private.write_action_quotas','select') or
    has_table_privilege('authenticated','private.write_action_quotas','update') or
    has_function_privilege('authenticated','private.consume_write_quota(text)','execute') or
    has_function_privilege('anon','private.consume_write_quota(text)','execute') or
    has_function_privilege('authenticated','public.cleanup_write_quotas()','execute') or
    not has_function_privilege('service_role','public.cleanup_write_quotas()','execute') then raise exception 'quota_privilege_bypass'; end if;
end $$;
create function pg_temp.create_cancel_cycle() returns void language plpgsql as $$
declare event uuid; begin
  event:=public.create_event_with_policy('Quota cycle match',5::smallint,'Amichevole',now()+interval '2 days','Synthetic field','Roma',10::smallint,'public','open');
  perform public.update_event_status(event,'cancelled');
end $$;
create function pg_temp.expect_rate(p_sql text) returns void language plpgsql as $$
begin
  begin execute p_sql;
  exception when sqlstate 'PT429' then if sqlerrm<>'write_rate_limited' then raise; end if; return; end;
  raise exception 'write_quota_bypass';
end $$;
select set_config('request.jwt.claims',(select jsonb_build_object('sub',host_id,'role','authenticated')::text from quota_fixture),true);
-- 3. Ten creates/cancels through the actual SECURITY DEFINER RPC succeed;
-- the eleventh is limited even though no created event remains active.
set local role authenticated;
do $$ begin for n in 1..10 loop perform pg_temp.create_cancel_cycle(); end loop;
  perform pg_temp.expect_rate('select pg_temp.create_cancel_cycle()'); end $$;
reset role;
do $$ begin if not exists(select 1 from private.write_action_quotas where user_id=(select host_id from quota_fixture)
  and action='event_create' and minute_count=10 and hour_count=10) then raise exception 'caller_uid_or_create_count_wrong'; end if; end $$;
-- 4. Deleting the cancelled fixture events cannot reset the separate counter.
delete from public.events where creator_id=(select host_id from quota_fixture) and status='cancelled';
set local role authenticated;
select pg_temp.expect_rate('select pg_temp.create_cancel_cycle()');
reset role;
-- 5. A new minute resets only minute count; request 60/hour succeeds and 61
-- fails atomically without consuming another minute/hour increment.
update private.write_action_quotas set minute_bucket=date_trunc('minute',now())-interval '1 minute',minute_count=10,
  hour_bucket=date_trunc('hour',now()),hour_count=59 where user_id=(select host_id from quota_fixture) and action='event_create';
set local role authenticated;
select pg_temp.create_cancel_cycle();
select pg_temp.expect_rate('select pg_temp.create_cancel_cycle()');
reset role;
do $$ begin if not exists(select 1 from private.write_action_quotas where user_id=(select host_id from quota_fixture)
  and action='event_create' and minute_count=1 and hour_count=60) then raise exception 'hour_limit_or_atomic_rejection_wrong'; end if; end $$;
-- 6. Advancing both server buckets starts both counters at one.
update private.write_action_quotas set minute_bucket=date_trunc('minute',now())-interval '1 hour',
  hour_bucket=date_trunc('hour',now())-interval '1 hour' where user_id=(select host_id from quota_fixture) and action='event_create';
set local role authenticated;
select pg_temp.create_cancel_cycle();
reset role;
do $$ begin if not exists(select 1 from private.write_action_quotas where user_id=(select host_id from quota_fixture)
  and action='event_create' and minute_count=1 and hour_count=1) then raise exception 'window_rollover_wrong'; end if; end $$;
-- 7. An error after BEFORE INSERT rolls the counter back with the event.
set local role authenticated;
do $$ begin begin perform public.create_event_with_policy('',5::smallint,'Amichevole',now()+interval '2 days','Synthetic field','Roma',10::smallint,'public','open');
  raise exception 'invalid_title_accepted'; exception when check_violation then null; end; end $$;
reset role;
do $$ begin if not exists(select 1 from private.write_action_quotas where user_id=(select host_id from quota_fixture)
  and action='event_create' and minute_count=1 and hour_count=1) then raise exception 'failed_event_consumed_quota'; end if; end $$;
-- 8. Sixty new requests reach the ceiling, attributed to the actual caller.
-- Withdrawal always remains available and does not consume a new-request slot.
select set_config('request.jwt.claims',(select jsonb_build_object('sub',player_id,'role','authenticated')::text from quota_fixture),true);
set local role authenticated;
do $$ declare event uuid:=(select event_id from quota_fixture); begin
  for n in 1..60 loop perform public.leave_event(event); perform public.request_event_join(event,null); end loop;
  perform public.leave_event(event);
  perform pg_temp.expect_rate('select public.request_event_join(event_id,null) from quota_fixture');
end $$;
reset role;
do $$ begin if not exists(select 1 from private.write_action_quotas where user_id=(select player_id from quota_fixture)
  and action='join' and minute_count=60 and hour_count=60) or exists(select 1 from private.write_action_quotas where action='manage')
  then raise exception 'join_identity_or_action_wrong'; end if; end $$;
-- 9. Same-state updates remain harmless at the ceiling; hour 600 is allowed
-- after a minute rollover, then 601 is refused without changing the row.
update public.event_members set state=state where event_id=(select event_id from quota_fixture);
update private.write_action_quotas set minute_bucket=date_trunc('minute',now())-interval '1 minute',minute_count=60,
  hour_count=599 where user_id=(select player_id from quota_fixture) and action='join';
set local role authenticated;
select public.request_event_join(event_id,null) from quota_fixture;
select public.leave_event(event_id) from quota_fixture;
select pg_temp.expect_rate('select public.request_event_join(event_id,null) from quota_fixture');
reset role;
do $$ begin if not exists(select 1 from private.write_action_quotas where user_id=(select player_id from quota_fixture)
  and action='join' and minute_count=1 and hour_count=600) then raise exception 'join_hour_limit_wrong'; end if; end $$;
-- 10. Organizer management has its own 60/minute ceiling and no-op retry.
select set_config('request.jwt.claims',(select jsonb_build_object('sub',host_id,'role','authenticated')::text from quota_fixture),true);
set local role authenticated;
do $$ declare event uuid:=(select event_id from quota_fixture); player uuid:=(select player_id from quota_fixture); begin
  for n in 1..60 loop perform public.manage_event_member(event,player,case when n%2=1 then 'approved' else 'removed' end); end loop;
  perform pg_temp.expect_rate('select public.manage_event_member(event_id,player_id,''approved'') from quota_fixture');
  perform public.manage_event_member(event,player,'removed');
end $$;
reset role;
do $$ begin if not exists(select 1 from private.write_action_quotas where user_id=(select host_id from quota_fixture)
  and action='manage' and minute_count=60 and hour_count=60) then raise exception 'manage_counter_wrong'; end if; end $$;
-- 11. Management's hourly bucket is independently capped at 600.
update private.write_action_quotas set minute_bucket=date_trunc('minute',now())-interval '1 minute',minute_count=60,
  hour_count=599 where user_id=(select host_id from quota_fixture) and action='manage';
set local role authenticated;
select public.manage_event_member(event_id,player_id,'approved') from quota_fixture;
select pg_temp.expect_rate('select public.manage_event_member(event_id,player_id,''removed'') from quota_fixture');
reset role;
-- 12. Only a real recent-MFA Admin moderating OTHER participants bypasses
-- management ceilings. A forged/old AAL hint is insufficient.
insert into private.write_action_quotas(user_id,action,minute_bucket,minute_count,hour_bucket,hour_count)
select admin_id,'manage',date_trunc('minute',now()),60,date_trunc('hour',now()),600 from quota_fixture;
select set_config('request.jwt.claims',(select admin_claims::text from quota_fixture),true);
update public.event_members set state='removed' where event_id=(select event_id from quota_fixture) and user_id=(select player_id from quota_fixture);
do $$ begin if not exists(select 1 from private.write_action_quotas where user_id=(select admin_id from quota_fixture)
  and action='manage' and minute_count=60 and hour_count=600) then raise exception 'valid_admin_bulk_counted'; end if; end $$;
select set_config('request.jwt.claims',(select (admin_claims||'{"aal":"aal1"}'::jsonb)::text from quota_fixture),true);
select pg_temp.expect_rate('update public.event_members set state=''approved'' where event_id=(select event_id from quota_fixture)');
-- 13. The same Admin's own creates/joins still count, and another user's
-- filled buckets cannot affect that Admin's separate counter rows.
insert into private.write_action_quotas(user_id,action,minute_bucket,minute_count,hour_bucket,hour_count)
select admin_id,action,date_trunc('minute',now()),n,date_trunc('hour',now()),h from quota_fixture
cross join (values('event_create',10,60),('join',60,600)) actions(action,n,h);
select set_config('request.jwt.claims',(select admin_claims::text from quota_fixture),true);
set local role authenticated;
select pg_temp.expect_rate('select pg_temp.create_cancel_cycle()');
select pg_temp.expect_rate('select public.request_event_join(event_id,null) from quota_fixture');
reset role;
-- 14. Cleanup is fixed to inactive 48h counters and is never scheduled here.
update private.write_action_quotas set minute_bucket=now()-interval '3 days',hour_bucket=now()-interval '3 days'
  where user_id=(select admin_id from quota_fixture) and action='join';
select set_config('request.jwt.claims','{}',true);
set local role service_role;
do $$ begin if public.cleanup_write_quotas()<>1 then raise exception 'quota_cleanup_wrong'; end if; end $$;
reset role;
do $$ begin if exists(select 1 from private.write_action_quotas where user_id=(select admin_id from quota_fixture) and action='join')
  or not exists(select 1 from private.write_action_quotas where user_id=(select host_id from quota_fixture) and action='event_create')
  then raise exception 'cleanup_deleted_active_or_kept_expired'; end if; end $$;
rollback;
