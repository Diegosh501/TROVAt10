-- Synthetic isolated fixture only. All users, sessions, DDL and deletes roll back.
begin;
do $$ begin if exists(select 1 from auth.users) or exists(select 1 from public.events) then
  raise exception 'erasure_execution_refused_on_populated_database';end if;end $$;
create temporary table erase_exec_fixture(n integer primary key,u uuid default gen_random_uuid(),sid uuid default gen_random_uuid(),factor uuid default gen_random_uuid(),request_id uuid,token text,old_token text) on commit drop;
insert into erase_exec_fixture(n) select generate_series(1,5);
grant select,update on erase_exec_fixture to authenticated,service_role;
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select u,'erasure-fixture-'||n||'@example.invalid',now(),'{"provider":"email"}',jsonb_build_object('username','erase_fixture_'||n,
 'role',case when n<=2 then 'host' else 'sportivo' end,'age_confirmed',true,'terms_accepted',true,'terms_version','fixture','privacy_notice_version','fixture') from erase_exec_fixture;
insert into public.subscriptions(user_id,plan,status) select u,'free','active' from erase_exec_fixture on conflict(user_id) do nothing;
insert into auth.identities(provider_id,user_id,provider,identity_data) select u::text,u,'google','{"email_verified":true}' from erase_exec_fixture;
insert into auth.mfa_factors(id,user_id,factor_type,status) select factor,u,'totp','verified' from erase_exec_fixture where n<=2;
insert into auth.sessions(id,user_id,aal,factor_id,not_after) select sid,u,case when n<=2 then 'aal2' else 'aal1' end,case when n<=2 then factor else null end,now()+interval '1 hour' from erase_exec_fixture;
insert into private.platform_admins(user_id) select u from erase_exec_fixture where n<=2;
create function pg_temp.erase_claim(p_n integer,p_recent boolean default true) returns void language plpgsql as $$
declare f erase_exec_fixture%rowtype;begin
 select * into f from erase_exec_fixture where n=p_n;
 perform set_config('request.jwt.claim.sub','',true);perform set_config('request.jwt.claim.role','',true);
 perform set_config('request.jwt.claims',jsonb_build_object('sub',f.u,'session_id',f.sid,'role','authenticated','aal',case when p_n<=2 then 'aal2' else 'aal1' end,
   'amr',case when p_n<=2 then jsonb_build_array(jsonb_build_object('method','totp','timestamp',extract(epoch from clock_timestamp())-case when p_recent then 0 else 901 end)) else '[]'::jsonb end)::text,true);
end $$;
create function pg_temp.expect_erase_error(p_sql text,p_code text) returns void language plpgsql as $$
begin
 begin execute p_sql;exception when others then if sqlstate=p_code then return;else raise exception 'expected %, received % (%)',p_code,sqlstate,sqlerrm;end if;end;
 raise exception 'expected denial: %',p_code;
end $$;
create function pg_temp.erase_preview() returns jsonb language plpgsql as $$
declare x jsonb;begin x:=public.admin_preview_account_erasure((select request_id from erase_exec_fixture where n=3));
 if x->>'status'<>'ready' or x->>'reviewToken' !~ '^[a-f0-9]{64}$' then raise exception 'expected ready preview: %',x;end if;
 update erase_exec_fixture set old_token=token,token=x->>'reviewToken' where n=3;return x;end $$;
create function pg_temp.erase_execute() returns jsonb language sql as $$
 select public.admin_execute_account_erasure(request_id,token,'CANCELLA ACCOUNT') from erase_exec_fixture where n=3
$$;

-- Default disabled, private tables, minimal grants and dependency compatibility.
do $$ begin
 if (select enabled from private.account_erasure_execution_settings) then raise exception 'execution_default_enabled';end if;
 if not private.account_deletion_dependencies_known() then raise exception 'new_module_changed_existing_cascade_graph';end if;
 if has_function_privilege('anon','public.admin_execute_account_erasure(uuid,text,text)','execute')
  or has_function_privilege('anon','public.confirm_my_account_erasure(uuid,boolean)','execute')
  or has_function_privilege('authenticated','public.set_account_erasure_execution_enabled(boolean,text)','execute')
  or has_table_privilege('authenticated','private.account_erasure_execution_receipts','select') then raise exception 'erasure_grant_leak';end if;
end $$;
select pg_temp.erase_claim(3);
set local role authenticated;
update erase_exec_fixture set request_id=(public.request_account_erasure(true)->>'id')::uuid where n=3;
select pg_temp.expect_erase_error('select public.admin_preview_account_erasure((select request_id from erase_exec_fixture where n=3))','PT403');
select pg_temp.expect_erase_error('select public.admin_execute_account_erasure((select request_id from erase_exec_fixture where n=3),repeat(''a'',64),''CANCELLA ACCOUNT'')','PT403');
select pg_temp.expect_erase_error('select public.confirm_my_account_erasure((select request_id from erase_exec_fixture where n=3),false)','22023');
select pg_temp.expect_erase_error('select public.confirm_my_account_erasure(gen_random_uuid(),true)','PT404');
select public.confirm_my_account_erasure((select request_id from erase_exec_fixture where n=3),true);
reset role;

-- Old actual session cannot be made fresh by a newly timestamped JWT.
update auth.sessions set created_at=now()-interval '16 minutes' where id=(select sid from erase_exec_fixture where n=3);
set local role authenticated;
select pg_temp.expect_erase_error('select public.confirm_my_account_erasure((select request_id from erase_exec_fixture where n=3),true)','PT401');
reset role;
update auth.sessions set created_at=now() where id=(select sid from erase_exec_fixture where n=3);
set local role authenticated;
select public.confirm_my_account_erasure((select request_id from erase_exec_fixture where n=3),true);
reset role;
select pg_temp.erase_claim(1);
set local role authenticated;
do $$ declare x jsonb;begin x:=public.admin_preview_account_erasure((select request_id from erase_exec_fixture where n=3));
 if x->>'reason'<>'execution_disabled' or (x->>'accountErased')::boolean then raise exception 'disabled_execution_lie';end if;end $$;
reset role;
set local role service_role;
select pg_temp.expect_erase_error('select public.set_account_erasure_execution_enabled(null,''trovat1o-erasure-2026-11-13-v1'')','22023');
select public.set_account_erasure_execution_enabled(true,'trovat1o-erasure-2026-11-13-v1');
reset role;
select pg_temp.erase_claim(1,false);
set local role authenticated;
select pg_temp.expect_erase_error('select public.admin_preview_account_erasure((select request_id from erase_exec_fixture where n=3))','PT403');
reset role;
select pg_temp.erase_claim(1);
set local role authenticated;
select pg_temp.erase_preview();
select pg_temp.expect_erase_error('select public.admin_execute_account_erasure((select request_id from erase_exec_fixture where n=3),(select token from erase_exec_fixture where n=3),''YES'')','22023');
reset role;

-- Review capabilities are short-lived, actor-bound and replaced on re-review.
select pg_temp.erase_claim(2);
set local role authenticated;
select pg_temp.expect_erase_error('select pg_temp.erase_execute()','PT403');
reset role;
select pg_temp.erase_claim(1);
update private.account_erasure_execution_receipts set review_expires_at=now()-interval '1 second';
set local role authenticated;
select pg_temp.expect_erase_error('select pg_temp.erase_execute()','PT403');
select pg_temp.erase_preview();select pg_temp.erase_preview();
select pg_temp.expect_erase_error('select public.admin_execute_account_erasure(request_id,old_token,''CANCELLA ACCOUNT'') from erase_exec_fixture where n=3','PT403');
reset role;

-- Recheck dependencies after preview; even a new empty CASCADE is a hold.
create table public.erase_unknown_dependency(user_id uuid references public.profiles(id) on delete cascade);
set local role authenticated;
do $$ declare x jsonb;begin x:=pg_temp.erase_execute();if x->>'reason'<>'unknown_dependencies' or (x->>'accessClosed')::boolean then raise exception 'dependency_change_ignored';end if;end $$;
reset role;
drop table public.erase_unknown_dependency;
do $$ begin if not exists(select 1 from auth.users where id=(select u from erase_exec_fixture where n=3)) then raise exception 'blocked_account_deleted';end if;end $$;

-- Shared match, paid plan, Billing mapping, preservation and other support
-- material each block independently. No policy is silently overridden.
insert into public.events(creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission)
 select u,'Synthetic retained match',5,'Amichevole',now()+interval '2 days','Synthetic','Synthetic',4,'public','approval' from erase_exec_fixture where n=3;
set local role authenticated;
do $$ declare x jsonb;begin x:=public.admin_preview_account_erasure((select request_id from erase_exec_fixture where n=3));if x->>'reason'<>'owned_match' then raise exception 'shared_match_hold_missing';end if;end $$;
reset role;
delete from public.events where creator_id=(select u from erase_exec_fixture where n=3);
update public.subscriptions set plan='premium',status='active',current_period_end=now()+interval '1 year' where user_id=(select u from erase_exec_fixture where n=3);
set local role authenticated;
do $$ declare x jsonb;begin x:=public.admin_preview_account_erasure((select request_id from erase_exec_fixture where n=3));if x->>'reason'<>'premium' then raise exception 'premium_hold_missing';end if;end $$;
reset role;
update public.subscriptions set plan='free',current_period_end=null where user_id=(select u from erase_exec_fixture where n=3);
insert into private.billing_accounts(user_id,mode,customer_id) select u,'test','cus_erasureSynthetic' from erase_exec_fixture where n=3;
set local role authenticated;
do $$ declare x jsonb;begin x:=public.admin_preview_account_erasure((select request_id from erase_exec_fixture where n=3));if x->>'reason'<>'billing' then raise exception 'billing_hold_missing';end if;end $$;
reset role;
delete from private.billing_accounts where user_id=(select u from erase_exec_fixture where n=3);
insert into public.events(creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission)
 select u,'Synthetic other organiser',5,'Amichevole',now()+interval '2 days','Synthetic','Synthetic',4,'public','approval' from erase_exec_fixture where n=5;
insert into public.event_members(event_id,user_id,state) select e.id,f.u,'approved' from public.events e cross join erase_exec_fixture f where f.n=3 and e.title='Synthetic other organiser';
set local role authenticated;
do $$ declare x jsonb;begin x:=public.admin_preview_account_erasure((select request_id from erase_exec_fixture where n=3));if x->>'reason'<>'active_participation' then raise exception 'active_participation_hold_missing';end if;end $$;
reset role;
delete from public.events where title='Synthetic other organiser';
insert into private.account_retention_holds(user_id,reason,hold_until) select u,'legal_preservation',now()+interval '1 day' from erase_exec_fixture where n=3;
set local role authenticated;
do $$ declare x jsonb;begin x:=public.admin_preview_account_erasure((select request_id from erase_exec_fixture where n=3));if x->>'reason'<>'preservation' then raise exception 'preservation_hold_missing';end if;end $$;
reset role;
delete from private.account_retention_holds where user_id=(select u from erase_exec_fixture where n=3);
insert into public.support_requests(requester_user_id,category,subject,details,status) select u,'account','Synthetic historical ticket','Review required, no real contacts.','closed' from erase_exec_fixture where n=3;
set local role authenticated;
do $$ declare x jsonb;begin x:=public.admin_preview_account_erasure((select request_id from erase_exec_fixture where n=3));if x->>'reason'<>'support_history_review' then raise exception 'closed_support_skipped';end if;end $$;
reset role;
delete from public.support_requests where requester_user_id=(select u from erase_exec_fixture where n=3) and request_kind='support';

create schema storage;
create table storage.objects(owner_id text);
insert into storage.objects select u::text from erase_exec_fixture where n=3;
set local role authenticated;
do $$ declare x jsonb;begin x:=public.admin_preview_account_erasure((select request_id from erase_exec_fixture where n=3));if x->>'reason'<>'storage' then raise exception 'storage_hold_missing';end if;end $$;
reset role;
drop table storage.objects;drop schema storage;

-- Revocation after a ready preview must defeat the old capabilities/JWTs.
set local role authenticated;select pg_temp.erase_preview();reset role;
delete from auth.sessions where id=(select sid from erase_exec_fixture where n=3);
set local role authenticated;
do $$ declare x jsonb;begin x:=pg_temp.erase_execute();if x->>'reason'<>'reauthentication_required' then raise exception 'target_session_revocation_ignored';end if;end $$;
reset role;
update erase_exec_fixture set sid=gen_random_uuid() where n=3;
insert into auth.sessions(id,user_id,aal,not_after) select sid,u,'aal1',now()+interval '1 hour' from erase_exec_fixture where n=3;
select pg_temp.erase_claim(3);
set local role authenticated;select public.confirm_my_account_erasure((select request_id from erase_exec_fixture where n=3),true);reset role;
select pg_temp.erase_claim(1);
set local role authenticated;select pg_temp.erase_preview();reset role;
update private.platform_admins set enabled=false where user_id=(select u from erase_exec_fixture where n=1);
set local role authenticated;select pg_temp.expect_erase_error('select pg_temp.erase_execute()','PT403');reset role;
update private.platform_admins set enabled=true where user_id=(select u from erase_exec_fixture where n=1);

-- Force a managed-side failure after session revocation; subtransaction must
-- restore sessions, receipt and ticket rather than report partial completion.
create function pg_temp.refuse_fixture_delete() returns trigger language plpgsql as $$begin
 if old.id=(select u from erase_exec_fixture where n=3) then raise exception 'synthetic managed dependency' using errcode='23503';end if;return old;end $$;
create trigger erase_fixture_delete_failure before delete on auth.users for each row execute function pg_temp.refuse_fixture_delete();
set local role authenticated;select pg_temp.erase_preview();
do $$ declare x jsonb;begin x:=pg_temp.erase_execute();if x->>'reason'<>'dependencies_changed' or (x->>'accountErased')::boolean then raise exception 'false_success_on_delete_failure';end if;end $$;
reset role;
do $$ begin
 if not exists(select 1 from auth.sessions where id=(select sid from erase_exec_fixture where n=3))
  or not exists(select 1 from auth.users where id=(select u from erase_exec_fixture where n=3))
  or exists(select 1 from private.account_erasure_execution_receipts where state='completed')
  or exists(select 1 from public.support_requests where id=(select request_id from erase_exec_fixture where n=3) and status='resolved') then raise exception 'partial_delete_not_rolled_back';end if;
end $$;
drop trigger erase_fixture_delete_failure on auth.users;

-- Actual synthetic erasure and idempotent retry, all within the final ROLLBACK.
set local role authenticated;select pg_temp.erase_preview();
do $$ declare x jsonb;begin
 x:=pg_temp.erase_execute();if x->>'status'<>'completed' or not (x->>'accountErased')::boolean or not (x->>'accessClosed')::boolean or (x->>'reused')::boolean then raise exception 'erase_not_completed';end if;
 x:=pg_temp.erase_execute();if not (x->>'reused')::boolean then raise exception 'erase_retry_not_idempotent';end if;
 x:=public.admin_preview_account_erasure((select request_id from erase_exec_fixture where n=3));if x->>'status'<>'completed' or x ? 'reviewToken' then raise exception 'completed_preview_minted_capability';end if;
end $$;
reset role;
do $$ begin
 if exists(select 1 from auth.users where id=(select u from erase_exec_fixture where n=3))
  or exists(select 1 from public.profiles where id=(select u from erase_exec_fixture where n=3))
  or exists(select 1 from auth.sessions where user_id=(select u from erase_exec_fixture where n=3))
  or exists(select 1 from auth.identities where user_id=(select u from erase_exec_fixture where n=3)) then raise exception 'erasure_residual_identity';end if;
 if exists(select 1 from private.account_erasure_execution_receipts where state='completed' and (user_id is not null or confirmed_session_id is not null or review_actor is not null or review_hash is not null or completed_at is null)) then raise exception 'receipt_identity_not_minimised';end if;
 if not exists(select 1 from public.support_requests where id=(select request_id from erase_exec_fixture where n=3) and requester_user_id is null and status='resolved' and contact_name is null and contact_email is null and not contact_allowed) then raise exception 'ticket_not_minimised';end if;
 if (select count(*) from auth.users)<>4 then raise exception 'other_accounts_changed';end if;
end $$;
select pg_temp.erase_claim(3);
set local role authenticated;
do $$ begin if public.has_live_session() or public.is_email_confirmed() then raise exception 'deleted_account_old_jwt_still_authorized';end if;end $$;
select pg_temp.expect_erase_error('select public.confirm_my_account_erasure((select request_id from erase_exec_fixture where n=3),true)','PT401');
reset role;

-- Admin account cannot erase itself and leave the app without its custodian.
select pg_temp.erase_claim(1);
set local role authenticated;
update erase_exec_fixture set request_id=(public.request_account_erasure(true)->>'id')::uuid where n=1;
select pg_temp.expect_erase_error('select public.confirm_my_account_erasure((select request_id from erase_exec_fixture where n=1),true)','PT403');
reset role;
-- Successful confirmations are independently rate limited; no budget is taken
-- from export, withdrawal or another account.
select pg_temp.erase_claim(4);
set local role authenticated;
update erase_exec_fixture set request_id=(public.request_account_erasure(true)->>'id')::uuid where n=4;
do $$ declare i integer;begin for i in 1..10 loop perform public.confirm_my_account_erasure((select request_id from erase_exec_fixture where n=4),true);end loop;end $$;
select pg_temp.expect_erase_error('select public.confirm_my_account_erasure((select request_id from erase_exec_fixture where n=4),true)','PT429');
reset role;
rollback;
