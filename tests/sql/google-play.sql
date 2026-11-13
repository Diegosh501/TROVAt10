-- Extends the profile fixtures and assertions; still staging-only and entirely rolled back.
-- Pre-launch/staging regression. No real Google exchange: identities are test
-- fixtures in a rollback transaction. Refuses any populated Auth/event database.
begin;
do $$ begin
  if exists(select 1 from auth.users) or exists(select 1 from public.events) then
    raise exception 'oauth_regression_refused_on_populated_database';
  end if;
end $$;
create temporary table oauth_fixture (
  first_id uuid default gen_random_uuid(),second_id uuid default gen_random_uuid(),legacy_id uuid default gen_random_uuid(),
  first_name text default 'qa_google_'||substr(replace(gen_random_uuid()::text,'-',''),1,8),
  second_name text default 'qa_player_'||substr(replace(gen_random_uuid()::text,'-',''),1,8)
) on commit drop;
insert into oauth_fixture default values;
grant select on oauth_fixture to authenticated;
select set_config('request.jwt.claim.sub','',true);
-- 1. Auth accepts Google metadata without fabricating a profile or consent.
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select first_id,'oauth-'||first_id||'@example.invalid',now(),'{"provider":"google","providers":["google"]}'::jsonb,
  '{"name":"Synthetic name","username":"spoofed_admin","role":"admin","terms_accepted":"true"}'::jsonb from oauth_fixture
union all select second_id,'oauth-'||second_id||'@example.invalid',null,'{"provider":"google","providers":["google"]}'::jsonb,'{}'::jsonb from oauth_fixture;
do $$ begin if exists(select 1 from public.profiles) then raise exception 'Google metadata created an unauthorized profile'; end if; end $$;
-- 2. Existing email signup metadata remains compatible.
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select legacy_id,'legacy-'||legacy_id||'@example.invalid',now(),'{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username','qa_legacy_'||left(replace(legacy_id::text,'-',''),8),'role','sportivo',
    'age_confirmed','true','terms_accepted','true','terms_version','regression','privacy_notice_version','regression') from oauth_fixture;
do $$ begin if (select count(*) from public.profiles)<>1 then raise exception 'Legacy email signup regressed'; end if; end $$;
-- Each synthetic user has an explicit live Auth session; JWT fixtures below
-- supply its ID directly. auth.jwt() never manufactures missing claims.
insert into auth.sessions(id,user_id,aal,not_after)
select uid,uid,'aal1',now()+interval '1 hour' from oauth_fixture f
  cross join lateral(values(f.first_id),(f.second_id),(f.legacy_id)) users(uid);
-- 3. Anonymous callers cannot execute profile completion.
do $$ begin if has_function_privilege('anon','public.complete_my_profile(text,text,boolean,boolean,boolean)','execute') then
  raise exception 'Anonymous completion privilege'; end if; end $$;
create function pg_temp.expect_profile_error(p_reason text,p_role text default 'host',p_adult boolean default true,p_terms boolean default true,p_privacy boolean default true)
returns void language plpgsql as $$ begin
  begin perform public.complete_my_profile((select first_name from oauth_fixture),p_role,p_adult,p_terms,p_privacy);
  exception when others then if sqlerrm<>p_reason then raise exception 'Expected %, got %',p_reason,sqlerrm; end if; return; end;
  raise exception 'Profile completion bypass: %',p_reason;
end $$;
-- 4. A Google claim alone, without a server-created identity, is insufficient.
select set_config('request.jwt.claims',(select jsonb_build_object('sub',first_id,'session_id',first_id,'role','authenticated','app_metadata',jsonb_build_object('provider','google'))::text from oauth_fixture),true);
set local role authenticated;
select pg_temp.expect_profile_error('google_identity_required');
reset role;
insert into auth.identities(provider_id,user_id,identity_data,provider,created_at,updated_at)
select user_id::text,user_id,jsonb_build_object('sub',user_id,'email_verified',true,'email','synthetic@example.invalid'),'google',now(),now()
from oauth_fixture f cross join lateral (values(f.first_id),(f.second_id)) users(user_id);
-- 5-8. Role and every profile confirmation are validated independently.
set local role authenticated;
select pg_temp.expect_profile_error('invalid_profile','admin');
select pg_temp.expect_profile_error('profile_confirmations_required','host',false,true,true);
select pg_temp.expect_profile_error('profile_confirmations_required','host',true,false,true);
select pg_temp.expect_profile_error('profile_confirmations_required','host',true,true,false);
-- 9. A valid completion owns only the authenticated user's profile and is Free.
select public.complete_my_profile(first_name,'host',true,true,true) from oauth_fixture;
do $$ begin
  if (select count(*) from public.profiles)<>1 or (select role from public.profiles)<>'host'
    or (select username from public.profiles)<>(select first_name from oauth_fixture) then
    raise exception 'Wrong profile ownership or role'; end if;
  if (select plan from public.subscriptions)<>'free' then raise exception 'Signup is not Free'; end if;
end $$;
-- 10. Retrying cannot rename the account, change role or create another row.
select public.complete_my_profile('different_name','sportivo',true,true,true);
do $$ begin if (select role from public.profiles)<>'host' or (select count(*) from public.profiles)<>1 then
  raise exception 'Completion retry changed existing profile'; end if; end $$;
-- 11. Direct client privilege cannot change verification or subscription.
do $$ begin
  begin update public.profiles set phone_verified_at=now(); raise exception 'Phone privilege bypass'; exception when insufficient_privilege then null; end;
  begin update public.subscriptions set plan='premium'; raise exception 'Premium privilege bypass'; exception when insufficient_privilege then null; end;
end $$;
reset role;
-- 12. Unconfirmed Google email remains insufficient.
select set_config('request.jwt.claims',(select jsonb_build_object('sub',second_id,'session_id',second_id,'role','authenticated')::text from oauth_fixture),true);
set local role authenticated;
select pg_temp.expect_profile_error('google_identity_required');
reset role;
update auth.users set email_confirmed_at=now() where id=(select second_id from oauth_fixture);
-- 13. A provider identity whose email isn't verified cannot grant access.
update auth.identities set identity_data=identity_data||'{"email_verified":false}'::jsonb where user_id=(select second_id from oauth_fixture);
set local role authenticated;
select pg_temp.expect_profile_error('google_identity_required');
reset role;
update auth.identities set identity_data=identity_data||'{"email_verified":true}'::jsonb where user_id=(select second_id from oauth_fixture);
-- 14. Case-insensitive username uniqueness is enforced by the database.
set local role authenticated;
do $$ begin
  begin perform public.complete_my_profile(upper((select first_name from oauth_fixture)),'sportivo',true,true,true);raise exception 'Casefold uniqueness bypass';
  exception when unique_violation then null; end;
end $$;
-- 15. Another Google account gets a separate Free Sportivo profile.
select public.complete_my_profile(second_name,'sportivo',true,true,true) from oauth_fixture;
do $$ begin if (select count(*) from public.profiles)<>1 or (select role from public.profiles)<>'sportivo'
  or (select plan from public.subscriptions)<>'free' then raise exception 'Second profile isolation failed'; end if; end $$;
reset role;
-- 16. Blocking an account stops further privileged completion calls.
update auth.users set banned_until=now()+interval '1 day' where id=(select second_id from oauth_fixture);
set local role authenticated;
select pg_temp.expect_profile_error('google_identity_required');
reset role;
-- 17. All application roles remain non-admin; no platform grant was created.
set local role authenticated;
do $$ begin if public.is_email_confirmed() then raise exception 'Banned account still passes mutation gate'; end if; end $$;
reset role;
do $$ begin if exists(select 1 from private.platform_admins) or (select count(*) from public.profiles)<>3 then
  raise exception 'Unexpected platform permission/profile count'; end if; end $$;
-- Extend the 17 profile assertions with 10 public/private play groups.
update auth.users set banned_until=null where id=(select second_id from oauth_fixture);
update public.profiles set role='host' where id=(select legacy_id from oauth_fixture);
alter table oauth_fixture add column public_event uuid,add column private_event uuid;
grant update on oauth_fixture to authenticated;
select set_config('request.jwt.claims',(select jsonb_build_object('sub',first_id,'session_id',first_id,'role','authenticated')::text from oauth_fixture),true);
set local role authenticated;
-- 1. A completed Google identity enables public play without phone verification.
do $$ begin if not public.is_play_verified() or public.is_phone_verified() then raise exception 'Google/phone distinction failed';end if;end $$;
update oauth_fixture set public_event=public.create_event_with_policy('Google public match',5::smallint,'Amichevole',now()+interval '2 days','Synthetic field','Test city',10::smallint,'public','open');
-- 2. Google verification is not proof of an arbitrary contact phone number.
do $$ begin
 begin insert into public.event_host_contacts(event_id,whatsapp_phone,share_with_approved) select public_event,'+390000000000',true from oauth_fixture;raise exception 'Unverified contact phone bypass';
 exception when insufficient_privilege then null;end;
end $$;
-- 3. Free retains the two-active-created-event cap.
select public.create_event_with_policy('Second Google match',8::smallint,'Amichevole',now()+interval '3 days','Synthetic field','Test city',16::smallint,'public','approval');
do $$ begin
 begin perform public.create_event_with_policy('Third Google match',5::smallint,'Amichevole',now()+interval '4 days','Synthetic field','Test city',10::smallint,'public','approval');raise exception 'Free cap bypass';
 exception when check_violation then if sqlerrm<>'active_event_limit' then raise;end if;end;
end $$;
reset role;
select set_config('request.jwt.claims',(select jsonb_build_object('sub',second_id,'session_id',second_id,'role','authenticated')::text from oauth_fixture),true);
set local role authenticated;
-- 4. A Google Sportivo joins a public open event without an SMS.
do $$ begin if (select public.request_event_join(public_event,null) from oauth_fixture)<>'approved' then raise exception 'Google public join failed';end if;end $$;
-- 5. Google does not grant another organizer's permissions.
do $$ begin
 begin perform public.update_event_status((select public_event from oauth_fixture),'cancelled');raise exception 'Event ownership bypass';
 exception when insufficient_privilege then null;end;
end $$;
-- 6. A member may suggest a pin but cannot mark its suggestion approved.
insert into public.pin_suggestions(event_id,user_id,latitude,longitude) select public_event,second_id,45.0,9.0 from oauth_fixture;
do $$ begin
 begin insert into public.pin_suggestions(event_id,user_id,latitude,longitude,state) select public_event,second_id,45.0,9.0,'approved' from oauth_fixture;raise exception 'Pin moderation bypass';
 exception when insufficient_privilege then null;end;
end $$;
-- 7. A verified Google member can submit a private report about a real peer.
select public.submit_player_report(public_event,first_id,'Comportamento scorretto','Synthetic conduct report with no real user data.') from oauth_fixture;
reset role;
select set_config('request.jwt.claims',(select jsonb_build_object('sub',legacy_id,'session_id',legacy_id,'role','authenticated','user_metadata',jsonb_build_object('googleVerified',true))::text from oauth_fixture),true);
set local role authenticated;
-- 8. Editable metadata cannot impersonate a verified provider identity.
do $$ begin
 if public.is_play_verified() then raise exception 'Provider metadata bypass';end if;
 begin perform public.request_event_join((select public_event from oauth_fixture),null);raise exception 'Unverified public join bypass';
 exception when insufficient_privilege then if sqlerrm<>'phone_verification_required' then raise;end if;end;
end $$;
-- 9. Existing confirmed-email private play remains available with its quota.
update oauth_fixture set private_event=public.create_event_with_policy('Private legacy match',5::smallint,'Amichevole',now()+interval '2 days','Synthetic private field','Test city',10::smallint,'private','open','','Misto','',null,null,decode(repeat('00',32),'hex'));
do $$ begin
 begin perform public.create_event_with_policy('Second private match',5::smallint,'Amichevole',now()+interval '3 days','Synthetic field','Test city',10::smallint,'private','open','','Misto','',null,null,decode(repeat('11',32),'hex'));raise exception 'Weekly cap bypass';
 exception when check_violation then if sqlerrm<>'weekly_private_event_limit' then raise;end if;end;
end $$;
reset role;
-- Replace only the synthetic token hash with the digest of a known fixture.
update public.event_invites set token_hash=extensions.digest(convert_to(repeat('f',64),'UTF8'),'sha256') where event_id=(select private_event from oauth_fixture);
select set_config('request.jwt.claims',(select jsonb_build_object('sub',second_id,'session_id',second_id,'role','authenticated')::text from oauth_fixture),true);
set local role authenticated;
-- 10. Google still needs a valid private invitation.
do $$ begin
 begin perform public.request_event_join((select private_event from oauth_fixture),null);raise exception 'Private invitation bypass';
 exception when insufficient_privilege then if sqlerrm<>'invite_required' then raise;end if;end;
 if (select public.request_event_join(private_event,repeat('f',64)) from oauth_fixture)<>'approved' then raise exception 'Valid private invitation failed';end if;
end $$;
reset role;
rollback;
