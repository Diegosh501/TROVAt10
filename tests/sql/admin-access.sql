-- Pre-launch/staging only. Refuses a populated database, uses synthetic users
-- and session/factor fixtures, sends no email/SMS, then rolls back every row.
-- Tests database authorization, not a real Google login or a real MFA exchange.
begin;
do $$ begin
  if exists(select 1 from auth.users) or exists(select 1 from public.events) then
    raise exception 'admin_regression_refused_on_populated_database';
  end if;
end $$;
create temporary table admin_fixture (
  admin_id uuid default gen_random_uuid(),player_id uuid default gen_random_uuid(),host_id uuid default gen_random_uuid(),
  session_id uuid default gen_random_uuid(),factor_id uuid default gen_random_uuid(),ticket_id uuid default gen_random_uuid(),
  claims jsonb
) on commit drop;
insert into admin_fixture default values;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claim.role','',true);
grant select on admin_fixture to authenticated,anon,service_role;
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select user_id,'admin-regression-'||user_id::text||'@example.invalid',now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username','qa_'||left(replace(user_id::text,'-',''),12),'role',role,
    'age_confirmed','true','terms_accepted','true','terms_version','regression','privacy_notice_version','regression')
from admin_fixture f cross join lateral (values(f.admin_id,'host'),(f.player_id,'sportivo'),(f.host_id,'host')) as users(user_id,role);
insert into auth.mfa_factors(id,user_id,factor_type,status,created_at,updated_at)
select factor_id,admin_id,'totp','verified',now(),now() from admin_fixture;
insert into auth.sessions(id,user_id,created_at,updated_at,factor_id,aal,not_after)
select session_id,admin_id,now(),now(),factor_id,'aal2',now()+interval '1 hour' from admin_fixture;
update admin_fixture set claims=jsonb_build_object('sub',admin_id,'role','authenticated',
  'session_id',session_id,'aal','aal2','amr',jsonb_build_array(jsonb_build_object('method','totp','timestamp',extract(epoch from now()))));
insert into public.support_requests(id,category,subject,details)
select ticket_id,'bug','Synthetic regression ticket','A synthetic support request used only inside this rollback transaction.' from admin_fixture;

create function pg_temp.expect_admin_denied(p_reason text) returns void language plpgsql as $$
begin
  begin
    perform public.admin_dashboard();
  exception when others then
    if sqlerrm<>p_reason then raise exception 'Expected %, got % (%)',p_reason,sqlerrm,sqlstate; end if;
    return;
  end;
  raise exception 'Unexpected admin authorization: %',p_reason;
end $$;

-- 1. Anonymous clients cannot execute administrative endpoints.
set local role anon;
do $$ begin
  begin perform public.admin_dashboard(); raise exception 'anonymous RPC bypass';
  exception when insufficient_privilege then null; end;
end $$;
reset role;

-- 2. A normal Sportivo cannot self-promote through editable user metadata.
select set_config('request.jwt.claims',(select (claims||jsonb_build_object('sub',player_id,'user_metadata',jsonb_build_object('role','admin')))::text from admin_fixture),true);
set local role authenticated;
select pg_temp.expect_admin_denied('admin_required');
-- 3. Neither a forged/stale app_metadata hint nor an aal2 hint is a permission.
select set_config('request.jwt.claims',((current_setting('request.jwt.claims')::jsonb)||'{"app_metadata":{"role":"admin"}}'::jsonb)::text,true);
select pg_temp.expect_admin_denied('admin_required');
-- 4. Host permissions do not imply platform administration either.
select set_config('request.jwt.claims',(select (claims||jsonb_build_object('sub',host_id,'app_metadata',jsonb_build_object('role','support')))::text from admin_fixture),true);
select pg_temp.expect_admin_denied('admin_required');
do $$ begin if public.is_support() then raise exception 'support metadata bypass'; end if; end $$;
-- 5. Direct writes to the allowlist and provisioning RPC are denied.
do $$ begin
  begin execute 'update private.platform_admins set enabled=true'; raise exception 'private allowlist write bypass';
  exception when insufficient_privilege then null; end;
  begin perform public.provision_platform_admin((select host_id from admin_fixture),true); raise exception 'self provisioning bypass';
  exception when insufficient_privilege then null; end;
end $$;
reset role;
-- Only the service provisioning grant is used to establish the fixture admin.
set local role service_role;
select public.provision_platform_admin(admin_id,true) from admin_fixture;
reset role;

-- 6. Even an allowlisted administrator must have a second factor.
select set_config('request.jwt.claims',(select (claims||'{"aal":"aal1"}'::jsonb)::text from admin_fixture),true);
set local role authenticated;
select pg_temp.expect_admin_denied('mfa_required');
-- 7-9. Old, future-dated and malformed MFA timestamps are refused.
select set_config('request.jwt.claims',(select (claims||jsonb_build_object('amr',jsonb_build_array(jsonb_build_object('method','totp','timestamp',extract(epoch from now())-901))))::text from admin_fixture),true);
select pg_temp.expect_admin_denied('mfa_required');
select set_config('request.jwt.claims',(select (claims||jsonb_build_object('amr',jsonb_build_array(jsonb_build_object('method','totp','timestamp',extract(epoch from now())+90))))::text from admin_fixture),true);
select pg_temp.expect_admin_denied('mfa_required');
select set_config('request.jwt.claims',(select (claims||'{"amr":{"method":"totp"}}'::jsonb)::text from admin_fixture),true);
select pg_temp.expect_admin_denied('mfa_required');
-- 10. A missing session id cannot authorize a request.
select set_config('request.jwt.claims',(select (claims-'session_id')::text from admin_fixture),true);
select pg_temp.expect_admin_denied('session_revoked');
reset role;

-- 11. A valid allowlist/session/MFA combination returns actual aggregate counts.
select set_config('request.jwt.claims',(select claims::text from admin_fixture),true);
set local role authenticated;
do $$ declare data jsonb; begin
  data:=public.admin_dashboard();
  if (data->'metrics'->>'totalUsers')::int<>3 or (data->'metrics'->>'hosts')::int<>2
    or (data->'metrics'->>'sportivi')::int<>1 then raise exception 'incorrect real dashboard counts'; end if;
  if not public.is_support() then raise exception 'valid admin cannot moderate'; end if;
end $$;
reset role;

-- 12. Session expiry is enforced even if an access token is still unexpired.
update auth.sessions set not_after=now()-interval '1 second' where id=(select session_id from admin_fixture);
set local role authenticated;
select pg_temp.expect_admin_denied('session_revoked');
reset role;
update auth.sessions set not_after=now()+interval '1 hour' where id=(select session_id from admin_fixture);
-- 13. A session id belonging to a different user cannot be borrowed.
update auth.sessions set user_id=(select host_id from admin_fixture) where id=(select session_id from admin_fixture);
set local role authenticated;
select pg_temp.expect_admin_denied('session_revoked');
reset role;
update auth.sessions set user_id=(select admin_id from admin_fixture) where id=(select session_id from admin_fixture);
-- 14. Removal/unverification of the MFA factor immediately ends admin access.
update auth.mfa_factors set status='unverified' where id=(select factor_id from admin_fixture);
set local role authenticated;
select pg_temp.expect_admin_denied('mfa_required');
reset role;
update auth.mfa_factors set status='verified' where id=(select factor_id from admin_fixture);
-- 15. A banned account cannot keep using the console.
update auth.users set banned_until=now()+interval '1 hour' where id=(select admin_id from admin_fixture);
set local role authenticated;
select pg_temp.expect_admin_denied('authentication_required');
reset role;
update auth.users set banned_until=null where id=(select admin_id from admin_fixture);
-- 16. Revocation in the database is effective with the exact same old claims.
set local role service_role;
select public.provision_platform_admin(admin_id,false) from admin_fixture;
reset role;
set local role authenticated;
select pg_temp.expect_admin_denied('admin_required');
do $$ begin if public.is_support() then raise exception 'revoked admin still moderates'; end if; end $$;
reset role;
set local role service_role;
select public.provision_platform_admin(admin_id,true) from admin_fixture;
reset role;

-- 17. Search is bounded and no contact details appear without a submitted contact.
set local role authenticated;
do $$ declare data jsonb; begin
  data:=public.admin_support_tickets('synthetic','new','bug','date');
  if (data->>'total')::int<>1 or jsonb_array_length(data->'tickets')<>1
    or (data->'tickets'->0->>'contact_email') is not null then raise exception 'ticket search privacy failure'; end if;
end $$;
-- 18. The ticket and both audit entries are saved together.
select public.admin_update_support_ticket(ticket_id,'resolved','Synthetic internal note') from admin_fixture;
reset role;
do $$ begin
  if (select status from public.support_requests where id=(select ticket_id from admin_fixture))<>'resolved'
    or (select count(*) from public.support_request_audit where ticket_id=(select ticket_id from admin_fixture))<>2 then
    raise exception 'ticket update/audit was not atomic'; end if;
end $$;
-- 19. If audit insertion fails, the ticket mutation must also roll back.
create function pg_temp.reject_audit() returns trigger language plpgsql as $$ begin raise exception 'synthetic_audit_failure'; end $$;
create trigger admin_regression_audit_failure before insert on public.support_request_audit
  for each row execute function pg_temp.reject_audit();
set local role authenticated;
do $$ begin
  begin
    perform public.admin_update_support_ticket((select ticket_id from admin_fixture),'closed','Must be rolled back');
    raise exception 'audit failure was ignored';
  exception when others then if sqlerrm<>'synthetic_audit_failure' then raise; end if; end;
end $$;
reset role;
drop trigger admin_regression_audit_failure on public.support_request_audit;
do $$ begin
  if (select status from public.support_requests where id=(select ticket_id from admin_fixture))<>'resolved' then
    raise exception 'audit error left unaudited ticket update'; end if;
end $$;
-- 20. Quota limits repeated authorized requests at the database boundary.
update private.admin_action_quota set window_start=date_trunc('minute',now()),request_count=60 where user_id=(select admin_id from admin_fixture);
set local role authenticated;
select pg_temp.expect_admin_denied('admin_rate_limited');
reset role;
delete from private.admin_action_quota where user_id=(select admin_id from admin_fixture);
-- 21. Logout/deleting the session invalidates the same otherwise-valid claims.
delete from auth.sessions where id=(select session_id from admin_fixture);
set local role authenticated;
select pg_temp.expect_admin_denied('session_revoked');
reset role;
rollback;
