-- Local/staging authorization regression, synthetic Auth sessions and JWT
-- settings only. No provider exchange; empty database required; full rollback.
begin;
do $$ begin
  if exists(select 1 from auth.users) or exists(select 1 from public.events) then
    raise exception 'session_security_refused_on_populated_database'; end if;
end $$;
create temporary table session_fixture (
  host_id uuid default gen_random_uuid(),player_id uuid default gen_random_uuid(),stranger_id uuid default gen_random_uuid(),
  host_session uuid default gen_random_uuid(),player_session uuid default gen_random_uuid(),stranger_session uuid default gen_random_uuid(),
  replacement_session uuid default gen_random_uuid(),private_event uuid default gen_random_uuid(),public_event uuid default gen_random_uuid(),
  foreign_event uuid default gen_random_uuid(),pin_id uuid default gen_random_uuid(),claims jsonb
) on commit drop;
insert into session_fixture default values;
grant select on session_fixture to authenticated,anon,service_role;
select set_config('request.jwt.claim.sub','',true);
select set_config('request.jwt.claim.role','',true);
select set_config('request.jwt.claims','{}',true);
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select uid,'session-'||uid||'@example.invalid',now(),' {"provider":"email"}'::jsonb,
  jsonb_build_object('username','qa_session_'||left(replace(uid::text,'-',''),8),
    'role',case when uid=f.player_id then 'sportivo' else 'host' end,
    'age_confirmed','true','terms_accepted','true','terms_version','regression','privacy_notice_version','regression')
from session_fixture f cross join lateral(values(f.host_id),(f.player_id),(f.stranger_id)) users(uid);
insert into auth.identities(provider_id,user_id,identity_data,provider)
select uid::text,uid,jsonb_build_object('sub',uid,'email_verified',true),'google'
from session_fixture f cross join lateral(values(f.host_id),(f.player_id),(f.stranger_id)) users(uid);
-- UUIDs and claims are independent explicit fixtures. auth.jwt() returns the
-- settings verbatim, including missing/malformed/revoked IDs in negative cases.
insert into auth.sessions(id,user_id,aal,not_after)
select sid,uid,'aal1',now()+interval '1 hour' from session_fixture f
  cross join lateral(values(f.host_session,f.host_id),(f.player_session,f.player_id),
    (f.stranger_session,f.stranger_id)) sessions(sid,uid);
update public.profiles set phone_verified_at=now();
insert into public.subscriptions(user_id,plan,status) select id,'free','active' from public.profiles;
insert into public.events(id,creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission)
select eid,owner_id,title,5,'Amichevole',now()+interval '2 days',venue,'Roma',10,visibility,'approval'
from session_fixture f cross join lateral(values
  (f.private_event,f.host_id,'Private session match','Exact private venue','private'),
  (f.public_event,f.host_id,'Public session match','Public venue','public'),
  (f.foreign_event,f.stranger_id,'Foreign private match','Foreign secret venue','private')
) events(eid,owner_id,title,venue,visibility);
insert into public.event_members(event_id,user_id,state)
select private_event,player_id,'approved' from session_fixture;
insert into public.event_invites(event_id,token_hash,expires_at)
select private_event,extensions.digest(convert_to(repeat('a',64),'UTF8'),'sha256'),now()+interval '3 days' from session_fixture;
insert into public.verified_phones(user_id,phone_hash) select host_id,repeat('b',64) from session_fixture;
insert into public.event_host_contacts(event_id,whatsapp_phone,share_with_approved,phone_binding_hash)
select private_event,'+393331234567',true,repeat('b',64) from session_fixture;
insert into public.pin_suggestions(id,event_id,user_id,latitude,longitude)
select pin_id,private_event,player_id,41.9,12.5 from session_fixture;
insert into public.player_reports(event_id,reporter_id,subject_id,reason,details)
select private_event,host_id,player_id,'Altro problema di sicurezza','Synthetic session boundary report' from session_fixture;
insert into public.notification_preferences(user_id) select id from public.profiles;
insert into public.push_subscriptions(user_id,endpoint,p256dh,auth)
select id,'https://fcm.googleapis.com/fcm/send/session-'||id,repeat('a',87),repeat('b',22) from public.profiles;
insert into public.app_notifications(user_id,event_id,type,title,body,dedupe_key)
select host_id,private_event,'event_updated','Private notice','Private event notice','session-host' from session_fixture
union all select player_id,private_event,'event_updated','Player notice','Player event notice','session-player' from session_fixture;
update session_fixture set claims=jsonb_build_object('sub',host_id,'role','authenticated','session_id',host_session,
  'exp',extract(epoch from now()+interval '1 hour'));

-- 1. Helpers are narrow booleans, not an Auth-table access grant. All affected
-- client tables have an AND/restrictive guard with both row predicates.
do $$ declare t text; begin
  if has_function_privilege('anon','public.has_live_session()','execute')
    or has_table_privilege('authenticated','auth.sessions','select')
    or has_table_privilege('authenticated','auth.sessions','insert')
    or has_table_privilege('authenticated','auth.sessions','delete') then
    raise exception 'live_session_privilege_leak'; end if;
  foreach t in array array['profiles','subscriptions','event_members','event_host_contacts','event_invites',
    'pin_suggestions','player_reports','notification_preferences','push_subscriptions','app_notifications'] loop
    if not exists(select 1 from pg_policy p where p.polrelid=('public.'||t)::regclass
      and p.polname='require_live_session' and not p.polpermissive and p.polcmd='*'
      and p.polqual is not null and p.polwithcheck is not null) then
      raise exception 'missing_restrictive_session_policy: %',t; end if;
  end loop;
end $$;

-- Assertion helpers do not change claims or create sessions. They check the
-- exact incoming fixture state, so a missing session_id remains missing.
create function pg_temp.expect_session_denied(p_sql text) returns void language plpgsql as $$
begin
  begin execute p_sql;
  exception when insufficient_privilege then return; end;
  raise exception 'revoked_session_rpc_or_insert_accepted: %',p_sql;
end $$;
create function pg_temp.assert_blocked(p_case text) returns void language plpgsql as $$
declare t text; n integer; eid uuid:=(select private_event from session_fixture);
  player uuid:=(select player_id from session_fixture); pid uuid:=(select pin_id from session_fixture);
begin
  if public.has_live_session() or public.is_email_confirmed() or public.is_google_verified()
    or public.is_phone_verified() or public.is_play_verified() or public.is_event_owner(eid)
    or public.is_event_member(eid) or public.host_contact_is_current(eid)
    or public.event_history_accessible(eid) then raise exception 'session_helper_bypass: %',p_case; end if;
  foreach t in array array['profiles','subscriptions','event_members','event_host_contacts','event_invites',
    'pin_suggestions','player_reports','notification_preferences','push_subscriptions','app_notifications'] loop
    -- Some child tables (for example invite hashes) already have no client
    -- SELECT grant at all. Both zero visible rows and ACL denial are safe.
    begin execute format('select count(*) from public.%I',t) into n;
    exception when insufficient_privilege then n:=0; end;
    if n<>0 then raise exception 'revoked_rls_read: % %',p_case,t; end if;
  end loop;
  if exists(select 1 from public.event_feed()) then raise exception 'revoked_private_feed: %',p_case; end if;
  update public.profiles set username='revoked_name';
  get diagnostics n=row_count;
  if n<>0 then raise exception 'revoked_profile_update: %',p_case; end if;
  update public.notification_preferences set activity_enabled=false;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'revoked_preferences_update: %',p_case; end if;
  update public.push_subscriptions set endpoint=endpoint||'/changed';
  get diagnostics n=row_count;
  if n<>0 then raise exception 'revoked_push_update: %',p_case; end if;
  delete from public.push_subscriptions;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'revoked_push_delete: %',p_case; end if;
  update public.app_notifications set read_at=now();
  get diagnostics n=row_count;
  if n<>0 then raise exception 'revoked_notification_update: %',p_case; end if;
  delete from public.event_host_contacts;
  get diagnostics n=row_count;
  if n<>0 then raise exception 'revoked_host_consent_delete: %',p_case; end if;
  update public.pin_suggestions set state='approved';
  get diagnostics n=row_count;
  if n<>0 then raise exception 'revoked_pin_update: %',p_case; end if;
  perform pg_temp.expect_session_denied(format('insert into public.notification_preferences(user_id) values(%L)',auth.uid()));
  perform pg_temp.expect_session_denied(format('insert into public.push_subscriptions(user_id,endpoint,p256dh,auth) values(%L,%L,%L,%L)',
    auth.uid(),'https://fcm.googleapis.com/fcm/send/revoked',repeat('a',87),repeat('b',22)));
  perform pg_temp.expect_session_denied(format('insert into public.pin_suggestions(event_id,user_id,latitude,longitude) values(%L,%L,41.9,12.5)',eid,auth.uid()));
  perform pg_temp.expect_session_denied('select public.complete_my_profile(''revoked_name'',''host'',true,true,true)');
  perform pg_temp.expect_session_denied('select public.create_event_with_policy(''Revoked match'',5::smallint,''Amichevole'',now()+interval ''1 day'',''Venue'',''Roma'',10::smallint,''public'',''approval'')');
  perform pg_temp.expect_session_denied(format('select public.update_event_with_policy(%L,''Changed match'',5::smallint,''Amichevole'',now()+interval ''2 days'',''Venue'',''Roma'',10::smallint,''private'',''approval'')',eid));
  perform pg_temp.expect_session_denied(format('select public.update_event_pin(%L,41.9,12.5)',eid));
  perform pg_temp.expect_session_denied(format('select public.update_event_status(%L,''in_progress'')',eid));
  perform pg_temp.expect_session_denied(format('select public.create_event_invite(%L,decode(repeat(''c'',64),''hex''))',eid));
  perform pg_temp.expect_session_denied(format('select public.request_event_join(%L,repeat(''a'',64))',eid));
  perform pg_temp.expect_session_denied(format('select public.manage_event_member(%L,%L,''removed'')',eid,player));
  perform pg_temp.expect_session_denied(format('select public.leave_event(%L)',eid));
  perform pg_temp.expect_session_denied(format('select * from public.event_roster(%L)',eid));
  perform pg_temp.expect_session_denied(format('select * from public.event_pin_suggestions(%L)',eid));
  perform pg_temp.expect_session_denied(format('select public.approve_event_pin(%L,%L)',eid,pid));
  perform pg_temp.expect_session_denied(format('select public.submit_player_report(%L,%L,''Altro problema di sicurezza'',''Synthetic revoked session report'')',eid,player));
end $$;

-- 2. A live owner sees their own data, private venue and consented contact;
-- normal account status/role remains unchanged by the new boundary.
select set_config('request.jwt.claims',(select claims::text from session_fixture),true);
set local role authenticated;
do $$ begin
  if not public.has_live_session() or not public.is_email_confirmed() or not public.is_google_verified()
    or not public.is_phone_verified() or not public.is_event_owner((select private_event from session_fixture))
    or (select count(*) from public.profiles)<>1 or (select count(*) from public.subscriptions)<>1
    or (select count(*) from public.notification_preferences)<>1 or (select count(*) from public.push_subscriptions)<>1
    or (select count(whatsapp_phone) from public.event_host_contacts)<>1
    or (select count(*) from public.player_reports)<>1
    or not exists(select 1 from public.event_feed() where id=(select private_event from session_fixture) and venue='Exact private venue')
    or exists(select 1 from public.event_feed() where id=(select foreign_event from session_fixture)) then
    raise exception 'live_owner_flow_regressed'; end if;
  update public.profiles set username=username;
  update public.notification_preferences set reminders_enabled=false;
  update public.app_notifications set read_at=now();
end $$;
reset role;

-- 3-6. Missing, malformed, nonexistent and another user's real session fail
-- closed despite confirmed email, valid future exp and spoofed metadata.
select set_config('request.jwt.claims',(select (claims-'session_id')::text from session_fixture),true);
set local role authenticated;
select pg_temp.assert_blocked('missing session_id');
reset role;
select set_config('request.jwt.claims',(select (claims||'{"session_id":"not-a-uuid"}'::jsonb)::text from session_fixture),true);
set local role authenticated;
select pg_temp.assert_blocked('malformed session_id');
reset role;
select set_config('request.jwt.claims',(select (claims||jsonb_build_object('session_id',gen_random_uuid()))::text from session_fixture),true);
set local role authenticated;
select pg_temp.assert_blocked('nonexistent session_id');
reset role;
select set_config('request.jwt.claims',(select (claims||jsonb_build_object('session_id',stranger_session,
  'user_metadata',jsonb_build_object('role','admin','session_id',host_session),'app_metadata',jsonb_build_object('role','admin')))::text from session_fixture),true);
set local role authenticated;
select pg_temp.assert_blocked('session owned by another user plus metadata spoof');
reset role;

-- 7. A time-boxed session expires independently from the JWT's future exp.
select set_config('request.jwt.claims',(select claims::text from session_fixture),true);
update auth.sessions set not_after=now()-interval '1 second' where id=(select host_session from session_fixture);
set local role authenticated;
select pg_temp.assert_blocked('expired Auth session');
reset role;
update auth.sessions set not_after=now()+interval '1 hour' where id=(select host_session from session_fixture);

-- 8-10. Live-session checks retain bans/deletion/anonymous account safeguards.
update auth.users set banned_until=now()+interval '1 hour' where id=(select host_id from session_fixture);
set local role authenticated;
select pg_temp.assert_blocked('banned Auth user');
reset role;
update auth.users set banned_until=null,deleted_at=now() where id=(select host_id from session_fixture);
set local role authenticated;
select pg_temp.assert_blocked('soft-deleted Auth user');
reset role;
update auth.users set deleted_at=null,is_anonymous=true where id=(select host_id from session_fixture);
set local role authenticated;
select pg_temp.assert_blocked('anonymous Auth user with authenticated role');
reset role;
update auth.users set is_anonymous=false,email_confirmed_at=null where id=(select host_id from session_fixture);
-- 11. Do not gate all self data on email confirmation. An existing real
-- session can read its own profile; it still cannot use confirmed-play RPCs.
set local role authenticated;
do $$ begin
  if not public.has_live_session() or public.is_email_confirmed() or public.is_google_verified()
    or (select count(*) from public.profiles)<>1 then raise exception 'unconfirmed_self_flow_regressed'; end if;
end $$;
reset role;
update auth.users set email_confirmed_at=now() where id=(select host_id from session_fixture);

-- 12. Logout deletes only this session. Keep identical old JWT claims and
-- demonstrate that another/new session of the same user cannot revive it.
delete from auth.sessions where id=(select host_session from session_fixture);
insert into auth.sessions(id,user_id,aal,not_after)
select replacement_session,host_id,'aal1',now()+interval '1 hour' from session_fixture;
set local role authenticated;
select pg_temp.assert_blocked('deleted session with unchanged unexpired JWT and another live session');
-- Bearer invitation preview remains intentionally available and masked;
-- assert_blocked already proved the same old token cannot join or read roster.
do $$ begin
  if (select count(*) from public.get_event_invitation(repeat('a',64)))<>1
    or exists(select 1 from public.get_event_invitation(repeat('a',64)) where venue='Exact private venue') then
    raise exception 'masked_invitation_preview_regressed'; end if;
end $$;
reset role;
select set_config('request.jwt.claims',(select (claims||jsonb_build_object('session_id',replacement_session))::text from session_fixture),true);
set local role authenticated;
do $$ begin if not public.has_live_session() or not public.is_event_owner((select private_event from session_fixture))
  or (select count(*) from public.profiles)<>1 then raise exception 'new_legitimate_session_blocked'; end if; end $$;
reset role;

-- 13. An approved player's separate live session reads the explicit contact
-- and exact private venue; revoking it hides both and every own-row shortcut.
select set_config('request.jwt.claims',(select jsonb_build_object('sub',player_id,'role','authenticated',
  'session_id',player_session,'exp',extract(epoch from now()+interval '1 hour'))::text from session_fixture),true);
set local role authenticated;
do $$ begin if not public.is_event_member((select private_event from session_fixture))
  or (select count(whatsapp_phone) from public.event_host_contacts)<>1
  or not exists(select 1 from public.event_feed() where id=(select private_event from session_fixture) and venue='Exact private venue') then
  raise exception 'live_player_flow_regressed'; end if; end $$;
reset role;
delete from auth.sessions where id=(select player_session from session_fixture);
set local role authenticated;
select pg_temp.assert_blocked('revoked approved participant');
reset role;

-- 14. Real anonymous discovery and a saved bearer preview are still usable;
-- neither discloses the private feed/venue, users or contact phone.
select set_config('request.jwt.claims','{"role":"anon"}',true);
set local role anon;
do $$ begin
  if (select count(*) from public.event_feed())<>1
    or not exists(select 1 from public.event_feed() where id=(select public_event from session_fixture))
    or (select count(*) from public.get_event_invitation(repeat('a',64)))<>1
    or exists(select 1 from public.get_event_invitation(repeat('a',64)) where venue='Exact private venue') then
    raise exception 'anonymous_discovery_or_masked_invite_regressed'; end if;
end $$;
reset role;

-- 15. Service maintenance does not acquire a user-session dependency. Existing
-- separate tests cover its locked quotas/leases/retention outcomes in depth.
select set_config('request.jwt.claims','{"role":"service_role"}',true);
set local role service_role;
do $$ begin if (select count(*) from public.notification_preferences)<>3 then
  raise exception 'service_rls_bypass_regressed'; end if; end $$;
select public.cleanup_write_quotas();
select public.run_event_retention(1);
select public.run_account_retention(1);
reset role;
-- Reminder queuing intentionally belongs to the trusted Cron/database owner,
-- not to service_role; the session hardening does not broaden that grant.
select public.queue_event_reminders();
rollback;
