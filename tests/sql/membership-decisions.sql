-- Staging-only integration regression for request_event_join/manage_event_member.
-- Run through a direct Postgres connection as postgres (or a test role allowed
-- to insert auth.users and SET ROLE authenticated), after schema.sql is applied.
-- Never run on production: although all fixtures are rolled back, this script
-- temporarily inserts three synthetic Auth users and exercises real triggers/RLS.
-- No email/SMS requests occur. A failed assertion aborts the transaction; use
-- ROLLBACK if the client stops before the final statement.

begin;
-- This pre-launch database must remain empty. Refuse to run if real rows exist.
do $$ begin
  if exists(select 1 from auth.users) or exists(select 1 from public.events) then
    raise exception 'regression_refused_on_populated_database';
  end if;
end $$;

create temporary table membership_regression (
  host_id uuid not null default gen_random_uuid(),
  player_id uuid not null default gen_random_uuid(),
  peer_id uuid not null default gen_random_uuid(),
  event_id uuid not null default gen_random_uuid()
) on commit drop;
insert into membership_regression default values;
grant select on membership_regression to authenticated;

insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select host_id,'host-'||host_id::text||'@example.invalid',now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username','test_host_'||left(replace(host_id::text,'-',''),8),
    'role','host','age_confirmed','true','terms_accepted','true',
    'terms_version','regression','privacy_notice_version','regression')
from membership_regression
union all
select player_id,'player-'||player_id::text||'@example.invalid',now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username','test_player_'||left(replace(player_id::text,'-',''),8),
    'role','sportivo','age_confirmed','true','terms_accepted','true',
    'terms_version','regression','privacy_notice_version','regression')
from membership_regression;

insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select peer_id,'peer-'||peer_id::text||'@example.invalid',now(),
  '{"provider":"email","providers":["email"]}'::jsonb,
  jsonb_build_object('username','test_peer_'||left(replace(peer_id::text,'-',''),8),
    'role','sportivo','age_confirmed','true','terms_accepted','true',
    'terms_version','regression','privacy_notice_version','regression')
from membership_regression;

-- Verification is fixture state, never a client-granted privilege.
update public.profiles set phone_verified_at=now()
where id in (select host_id from membership_regression union select player_id from membership_regression
  union select peer_id from membership_regression);
insert into public.events(id,creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission)
select event_id,host_id,'Regression match',5,'Amichevole',now()+interval '2 days',
  'Synthetic venue','Test city',4,'public','open'
from membership_regression;
insert into public.event_members(event_id,user_id,state)
select event_id,peer_id,'approved' from membership_regression;

-- 1. A new verified player can still enter an open-admission event.
select set_config('request.jwt.claim.sub',(select player_id::text from membership_regression),true);
set local role authenticated;
select public.request_event_join(event_id,null) from membership_regression;
reset role;
do $$ begin
  if (select state from public.event_members where event_id=(select event_id from membership_regression)
      and user_id=(select player_id from membership_regression)) is distinct from 'approved' then
    raise exception 'regression: first open admission must be approved';
  end if;
end $$;

-- 2. An organizer removes them; another request must remain pending.
select set_config('request.jwt.claim.sub',(select host_id::text from membership_regression),true);
set local role authenticated;
select public.manage_event_member(event_id,player_id,'removed') from membership_regression;
reset role;
-- Admitted peers must not see a removed membership through the base Data API.
select set_config('request.jwt.claim.sub',(select peer_id::text from membership_regression),true);
set local role authenticated;
do $$ begin
  if exists(select 1 from public.event_members where user_id=(select player_id from membership_regression)) then
    raise exception 'regression: peer can read a removed member';
  end if;
end $$;
reset role;
-- The removed user may still see their own result.
select set_config('request.jwt.claim.sub',(select player_id::text from membership_regression),true);
set local role authenticated;
do $$ begin
  if (select state from public.event_members where user_id=(select player_id from membership_regression)) is distinct from 'removed' then
    raise exception 'regression: own removed membership is inaccessible';
  end if;
end $$;
select public.request_event_join(event_id,null) from membership_regression;
reset role;
do $$ begin
  if (select state from public.event_members where event_id=(select event_id from membership_regression)
      and user_id=(select player_id from membership_regression)) is distinct from 'pending' then
    raise exception 'regression: removed player bypassed organizer approval';
  end if;
end $$;

-- Pending applicants remain private to themselves and the organizer.
select set_config('request.jwt.claim.sub',(select peer_id::text from membership_regression),true);
set local role authenticated;
do $$ begin
  if exists(select 1 from public.event_members where user_id=(select player_id from membership_regression)) then
    raise exception 'regression: peer can read a pending applicant';
  end if;
end $$;
reset role;

-- 3. A refusal also cannot be bypassed by the open-admission setting.
select set_config('request.jwt.claim.sub',(select host_id::text from membership_regression),true);
set local role authenticated;
do $$ begin
  if (select state from public.event_members where user_id=(select player_id from membership_regression)) is distinct from 'pending' then
    raise exception 'regression: organizer cannot see pending applicant';
  end if;
end $$;
select public.manage_event_member(event_id,player_id,'declined') from membership_regression;
reset role;
select set_config('request.jwt.claim.sub',(select peer_id::text from membership_regression),true);
set local role authenticated;
do $$ begin
  if exists(select 1 from public.event_members where user_id=(select player_id from membership_regression)) then
    raise exception 'regression: peer can read a declined applicant';
  end if;
end $$;
reset role;
select set_config('request.jwt.claim.sub',(select player_id::text from membership_regression),true);
set local role authenticated;
select public.request_event_join(event_id,null) from membership_regression;
reset role;
do $$ begin
  if (select state from public.event_members where event_id=(select event_id from membership_regression)
      and user_id=(select player_id from membership_regression)) is distinct from 'pending' then
    raise exception 'regression: declined player bypassed organizer approval';
  end if;
end $$;

-- 4. Only an explicit organizer approval restores the place.
select set_config('request.jwt.claim.sub',(select host_id::text from membership_regression),true);
set local role authenticated;
select public.manage_event_member(event_id,player_id,'approved') from membership_regression;
reset role;
do $$ begin
  if (select state from public.event_members where event_id=(select event_id from membership_regression)
      and user_id=(select player_id from membership_regression)) is distinct from 'approved' then
    raise exception 'regression: organizer approval did not restore membership';
  end if;
end $$;

-- Approved members are visible to their admitted peers after the host decides.
select set_config('request.jwt.claim.sub',(select peer_id::text from membership_regression),true);
set local role authenticated;
do $$ begin
  if (select state from public.event_members where user_id=(select player_id from membership_regression)) is distinct from 'approved' then
    raise exception 'regression: peer cannot see an approved participant';
  end if;
end $$;
reset role;

rollback;
