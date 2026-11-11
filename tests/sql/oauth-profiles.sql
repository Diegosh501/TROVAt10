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
select set_config('request.jwt.claims',(select jsonb_build_object('sub',first_id,'role','authenticated','app_metadata',jsonb_build_object('provider','google'))::text from oauth_fixture),true);
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
  if exists(select 1 from public.profiles where terms_version<>'trovat1o-2026-11-11-v2'
    or privacy_notice_version<>'trovat1o-2026-11-11-v2') then raise exception 'Outdated policy version recorded'; end if;
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
select set_config('request.jwt.claims',(select jsonb_build_object('sub',second_id,'role','authenticated')::text from oauth_fixture),true);
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
rollback;
