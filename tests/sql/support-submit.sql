-- Local, synthetic and rolled back. Never run on a populated Auth database.
begin;
do $$ begin if exists(select 1 from auth.users) or exists(select 1 from public.events) then
 raise exception 'support_regression_refused_on_populated_database';end if;end $$;
create temporary table support_fixture(a uuid default gen_random_uuid(),b uuid default gen_random_uuid(),sa uuid default gen_random_uuid(),sb uuid default gen_random_uuid(),request_id uuid default gen_random_uuid(),ticket uuid) on commit drop;
insert into support_fixture default values;
grant select,update on support_fixture to authenticated,service_role;
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
 select uid,uid||'@example.invalid',now(),'{"provider":"email"}'::jsonb,
 jsonb_build_object('username','support_'||left(replace(uid::text,'-',''),9),'role','sportivo',
 'age_confirmed','true','terms_accepted','true','terms_version','regression','privacy_notice_version','regression')
 from support_fixture f cross join lateral(values(f.a),(f.b)) users(uid);
insert into auth.sessions(id,user_id,aal,not_after)
 select sid,uid,'aal1',now()+interval '1 hour' from support_fixture f cross join lateral(values(f.a,f.sa),(f.b,f.sb)) users(uid,sid);
create function pg_temp.submit_qa(p_request uuid,p_hash text,p_contact boolean default false,p_attach boolean default false,p_subject text default 'Synthetic support request',p_user uuid default null,p_session uuid default null)
 returns jsonb language sql as $$
 select public.submit_verified_support_request(coalesce(p_user,a),coalesce(p_session,sa),p_request,p_hash,'bug',p_subject,
  'Synthetic support description with enough characters.',p_contact,'  Synthetic tester  ',' QA@EXAMPLE.INVALID ',p_attach) from support_fixture
$$;
create function pg_temp.expect_support_error(p_sql text,p_state text,p_reason text default null)
returns void language plpgsql as $$ begin
 begin execute p_sql;exception when others then
  if sqlstate<>p_state or p_reason is not null and sqlerrm<>p_reason then raise exception 'Expected % %, got % %',p_state,p_reason,sqlstate,sqlerrm;end if;return;
 end;raise exception 'Expected support failure did not occur: %',p_state;
end $$;
-- 1. Narrow RPC ACL and no direct read/write of the private ledgers.
do $$ declare role_name text;table_name text; begin
 if has_function_privilege('anon','public.authorize_support_submission()','execute') then raise exception 'anonymous_authorization';end if;
 foreach role_name in array array['anon','authenticated'] loop
  if has_function_privilege(role_name,'public.submit_verified_support_request(uuid,uuid,uuid,text,text,text,text,boolean,text,text,boolean)','execute') then raise exception 'client_captcha_bypass';end if;
 end loop;
 foreach role_name in array array['anon','authenticated','service_role'] loop
  foreach table_name in array array['private.support_submission_receipts','private.support_captcha_redemptions'] loop
   if has_table_privilege(role_name,table_name,'select') or has_table_privilege(role_name,table_name,'insert') or has_table_privilege(role_name,table_name,'update') or has_table_privilege(role_name,table_name,'delete') then raise exception 'direct_ledger_privilege';end if;
  end loop;
 end loop;
end $$;
select set_config('request.jwt.claims',(select jsonb_build_object('sub',a,'session_id',sa,'role','authenticated')::text from support_fixture),true);
set local role authenticated;
do $$ declare result jsonb;begin result:=public.authorize_support_submission();if result->>'user_id'<>(select a::text from support_fixture) or result->>'session_id'<>(select sa::text from support_fixture) then raise exception 'caller_identity_mismatch';end if;end $$;
select pg_temp.expect_support_error('select pg_temp.submit_qa(gen_random_uuid(),repeat(''a'',64))','42501');
reset role;
-- 2. The service transaction owns privacy defaults, not the caller-supplied contact strings.
set local role service_role;
update support_fixture set ticket=(pg_temp.submit_qa(request_id,repeat('a',64))->>'ticketId')::uuid;
reset role;
do $$ begin
 if (select count(*) from public.support_requests)<>1 or not exists(select 1 from public.support_requests where id=(select ticket from support_fixture) and requester_user_id is null and not contact_allowed and contact_name is null and contact_email is null) then raise exception 'privacy_default_bypass';end if;
 if (select submission_count from public.support_submit_quota where user_id=(select a from support_fixture))<>1 then raise exception 'quota_not_consumed_once';end if;
end $$;
-- 3. Same request/payload returns the same ID, without consuming another slot.
set local role service_role;
do $$ declare r jsonb;begin r:=pg_temp.submit_qa((select request_id from support_fixture),repeat('a',64));if r->>'reused'<>'true' or r->>'ticketId'<>(select ticket::text from support_fixture) then raise exception 'retry_duplicate_ticket';end if;end $$;
-- A retry with a fresh verified token also records its redemption.
select pg_temp.submit_qa(request_id,repeat('b',64)) from support_fixture;
select pg_temp.expect_support_error('select pg_temp.submit_qa((select request_id from support_fixture),repeat(''c'',64),false,false,''Changed subject'')','PT409','idempotency_conflict');
select pg_temp.expect_support_error('select pg_temp.submit_qa(gen_random_uuid(),repeat(''a'',64))','PT409','captcha_reused');
select pg_temp.expect_support_error('select pg_temp.submit_qa(gen_random_uuid(),repeat(''b'',64),false,false,''Synthetic support request'',(select b from support_fixture),(select sb from support_fixture))','PT409','captcha_reused');
reset role;
do $$ begin
 if (select count(*) from public.support_requests)<>1 or (select submission_count from public.support_submit_quota where user_id=(select a from support_fixture))<>1 then raise exception 'retry_or_replay_changed_quota';end if;
 if (select count(*) from private.support_captcha_redemptions)<>2 then raise exception 'fresh_retry_token_not_bound';end if;
end $$;
-- 4. Explicit opt-ins are stored after normalization. No silent truncation.
set local role service_role;
select pg_temp.submit_qa(gen_random_uuid(),repeat('d',64),true,true);
reset role;
do $$ begin if not exists(select 1 from public.support_requests where requester_user_id=(select a from support_fixture) and contact_allowed and contact_name='Synthetic tester' and contact_email='qa@example.invalid') then raise exception 'explicit_contact_not_saved';end if;end $$;
-- 5. Invalid payload is checked again inside SQL, before any quota or ticket write.
set local role service_role;
select pg_temp.expect_support_error('select public.submit_verified_support_request((select a from support_fixture),(select sa from support_fixture),gen_random_uuid(),repeat(''f'',64),''bug'',''Good subject'',''Synthetic description long enough.'',true,''name'',''invalid'',false)','22023','invalid_request');
select pg_temp.expect_support_error('select pg_temp.submit_qa(gen_random_uuid(),''bad'')','22023','invalid_request');
select pg_temp.expect_support_error('select pg_temp.submit_qa(gen_random_uuid(),repeat(''f'',64),false,false,''bad'')','22023','invalid_request');
select pg_temp.expect_support_error('select public.submit_verified_support_request((select a from support_fixture),(select sa from support_fixture),gen_random_uuid(),repeat(''f'',64),''admin'',''Good subject'',''Synthetic description long enough.'',false,null,null,false)','22023','invalid_request');
select pg_temp.expect_support_error('select public.submit_verified_support_request((select a from support_fixture),(select sa from support_fixture),gen_random_uuid(),repeat(''f'',64),''bug'',''Good subject'',''Synthetic description long enough.'',null,null,null,false)','22023','invalid_request');
-- 6. Five new tickets/day; idempotent retries still work at the ceiling.
select pg_temp.submit_qa(gen_random_uuid(),repeat(n::text,64)) from generate_series(1,3) n;
select pg_temp.expect_support_error('select pg_temp.submit_qa(gen_random_uuid(),repeat(''e'',64))','PT429','rate_limited');
select pg_temp.submit_qa(request_id,repeat('a',64)) from support_fixture;
reset role;
do $$ begin if (select count(*) from public.support_requests)<>5 or (select submission_count from public.support_submit_quota where user_id=(select a from support_fixture))<>5 then raise exception 'daily_quota_wrong';end if;end $$;
-- 7. UTC rollover resets only new-ticket quota; old valid receipt stays idempotent.
update public.support_submit_quota set window_day=current_date-1 where user_id=(select a from support_fixture);
set local role service_role;
select pg_temp.submit_qa(request_id,repeat('a',64)) from support_fixture;
select pg_temp.submit_qa(gen_random_uuid(),repeat('e',64));
reset role;
do $$ begin if (select submission_count from public.support_submit_quota where user_id=(select a from support_fixture))<>1 then raise exception 'rollover_quota_wrong';end if;end $$;
-- 8. Service authorization rechecks the exact user/session after the earlier read.
update auth.sessions set not_after=now()-interval '1 second' where id=(select sa from support_fixture);
set local role service_role;
select pg_temp.expect_support_error('select pg_temp.submit_qa(gen_random_uuid(),repeat(''f'',64))','PT401','unauthorized');
select pg_temp.expect_support_error('select pg_temp.submit_qa(gen_random_uuid(),repeat(''f'',64),false,false,''Synthetic support request'',null,(select sb from support_fixture))','PT401','unauthorized');
reset role;
update auth.sessions set not_after=now()+interval '1 hour' where id=(select sa from support_fixture);
update auth.users set banned_until=now()+interval '1 day' where id=(select a from support_fixture);
set local role service_role;
select pg_temp.expect_support_error('select pg_temp.submit_qa(gen_random_uuid(),repeat(''f'',64))','PT401','unauthorized');
reset role;
update auth.users set banned_until=null,email_confirmed_at=null where id=(select a from support_fixture);
set local role authenticated;
select pg_temp.expect_support_error('select public.authorize_support_submission()','PT401','unauthorized');
reset role;
set local role service_role;
select pg_temp.expect_support_error('select pg_temp.submit_qa(gen_random_uuid(),repeat(''f'',64))','PT401','unauthorized');
reset role;
update auth.users set email_confirmed_at=now() where id=(select a from support_fixture);
-- 9. Expired Free usage never removes the support route.
insert into private.account_lifecycle(user_id,acknowledged_at,policy_version,first_match_at)
 select a,now()-interval '8 days','trovat1o-account-2026-11-11-v1',now()-interval '8 days' from support_fixture on conflict(user_id) do update set first_match_at=excluded.first_match_at,acknowledged_at=excluded.acknowledged_at,policy_version=excluded.policy_version;
update private.account_lifecycle_settings set enabled=true;
set local role authenticated;
select public.authorize_support_submission();
reset role;
set local role service_role;
select pg_temp.submit_qa(gen_random_uuid(),repeat('f',64));
reset role;
-- 10. A rejected ticket insert rolls back both the nonce claim and the quota.
create function pg_temp.fail_support_insert() returns trigger language plpgsql as $$ begin if new.subject='Force insert failure' then raise exception 'synthetic_insert_failure';end if;return new;end $$;
create trigger regression_support_insert before insert on public.support_requests for each row execute function pg_temp.fail_support_insert();
set local role service_role;
select pg_temp.expect_support_error('select pg_temp.submit_qa(gen_random_uuid(),repeat(''4'',64),false,false,''Force insert failure'')','P0001','synthetic_insert_failure');
reset role;
drop trigger regression_support_insert on public.support_requests;
do $$ begin if exists(select 1 from private.support_captcha_redemptions where token_hash=decode(repeat('4',64),'hex')) or (select submission_count from public.support_submit_quota where user_id=(select a from support_fixture))<>2 then raise exception 'failed_insert_left_side_effects';end if;end $$;
-- 11. New Auth dependencies are recognized, while unknown cascades still block purge.
do $$ begin if not private.account_deletion_dependencies_known() then raise exception 'support_lifecycle_dependency_missing';end if;end $$;
create table private.unsupported_support_dependency(user_id uuid references auth.users(id) on delete cascade);
do $$ begin if private.account_deletion_dependencies_known() then raise exception 'unknown_dependency_ignored';end if;end $$;
drop table private.unsupported_support_dependency;
-- 12. Deleting a fixture account clears receipts but preserves CAPTCHA replay
-- hashes for the short window (SET NULL), without deleting its support tickets.
set local role service_role;
select pg_temp.submit_qa(gen_random_uuid(),repeat('5',64),false,false,'Synthetic support request',(select b from support_fixture),(select sb from support_fixture));
reset role;
delete from auth.users where id=(select b from support_fixture);
do $$ begin if exists(select 1 from private.support_submission_receipts where user_id=(select b from support_fixture)) or not exists(select 1 from private.support_captcha_redemptions where token_hash=decode(repeat('5',64),'hex') and user_id is null) then raise exception 'deletion_replay_guard_wrong';end if;end $$;
set local role service_role;
select pg_temp.expect_support_error('select pg_temp.submit_qa(gen_random_uuid(),repeat(''5'',64))','PT409','captcha_reused');
reset role;
-- 13. Cleanup only removes expired guard rows and is capped at 100 per table.
insert into private.support_captcha_redemptions(token_hash,user_id,request_id,created_at,expires_at)
 select extensions.digest(n::text,'sha256'),null,gen_random_uuid(),now()-interval '2 days',now()-interval '1 day' from generate_series(1,105) n;
insert into private.support_submission_receipts(user_id,request_id,payload_hash,ticket_id,created_at,expires_at)
 select f.a,gen_random_uuid(),decode(repeat('a',64),'hex'),f.ticket,now()-interval '2 days',now()-interval '1 day' from support_fixture f cross join generate_series(1,105) n;
set local role service_role;
select pg_temp.submit_qa(gen_random_uuid(),repeat('6',64));
reset role;
do $$ begin if (select count(*) from private.support_captcha_redemptions where expires_at<now())<>5 then raise exception 'cleanup_limit_wrong';end if;if (select count(*) from private.support_submission_receipts where expires_at<now())<>5 then raise exception 'receipt_cleanup_limit_wrong';end if;if not exists(select 1 from private.support_captcha_redemptions where token_hash=decode(repeat('a',64),'hex')) then raise exception 'cleanup_removed_live_guard';end if;end $$;
rollback;
