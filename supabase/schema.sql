-- TROVAT1O V2 Supabase baseline. Public writes stay disabled in the browser
-- until the auth, email delivery, CAPTCHA, SMS provider and UI RPC wiring are verified.
create extension if not exists pgcrypto with schema extensions;

create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  username text not null unique check (username ~ '^[A-Za-z0-9_.-]{3,24}$'),
  role text not null default 'sportivo' check (role in ('sportivo','host')),
  age_confirmed_at timestamptz not null,
  terms_accepted_at timestamptz not null,
  privacy_notice_ack_at timestamptz not null,
  terms_version text not null,
  privacy_notice_version text not null,
  phone_verified_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index if not exists profiles_username_casefold_idx on public.profiles(lower(username));


-- Profile is created server-side from signup metadata. Supabase Auth must have
-- Confirm email enabled; unconfirmed users cannot obtain an authenticated session.
create or replace function public.create_profile_for_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_username text; v_role text; v_age timestamptz; v_terms_version text; v_privacy_version text;
begin
  v_username := new.raw_user_meta_data->>'username';
  v_role := case when new.raw_user_meta_data->>'role'='host' then 'host' else 'sportivo' end;
  if v_username !~ '^[A-Za-z0-9_.-]{3,24}$' then raise exception 'invalid username'; end if;
  if coalesce(new.raw_user_meta_data->>'age_confirmed','') <> 'true' then raise exception 'adult confirmation required'; end if;
  v_terms_version := new.raw_user_meta_data->>'terms_version';
  v_privacy_version := new.raw_user_meta_data->>'privacy_notice_version';
  if coalesce(new.raw_user_meta_data->>'terms_accepted','') <> 'true' or v_terms_version is null or v_privacy_version is null then raise exception 'terms and privacy notice required'; end if;
  v_age := now();
  insert into public.profiles(id,username,role,age_confirmed_at,terms_accepted_at,privacy_notice_ack_at,terms_version,privacy_notice_version) values(new.id,v_username,v_role,v_age,v_age,v_age,v_terms_version,v_privacy_version);
  return new;
end $$;
drop trigger if exists on_auth_user_created_profile on auth.users;
create trigger on_auth_user_created_profile after insert on auth.users
for each row execute function public.create_profile_for_new_user();

create table if not exists public.verified_phones (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  phone_hash text not null unique,
  verified_at timestamptz not null default now()
);
alter table public.verified_phones enable row level security;

create or replace function public.is_phone_verified()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.profiles p where p.id=(select auth.uid()) and p.phone_verified_at is not null)
$$;
revoke all on function public.is_phone_verified() from public;
revoke all on function public.is_phone_verified() from anon;
grant execute on function public.is_phone_verified() to authenticated;

create table if not exists public.events (
  id uuid primary key default gen_random_uuid(),
  creator_id uuid not null references public.profiles(id),
  title text not null check (char_length(title) between 5 and 90),
  format smallint not null check (format in (5,8,11)),
  kind text not null check (kind in ('Amichevole','Torneo','Partita libera')),
  starts_at timestamptz not null,
  venue text not null check (char_length(venue) between 1 and 100),
  city text not null check (char_length(city) between 1 and 80),
  latitude double precision check (latitude between -90 and 90),
  longitude double precision check (longitude between -180 and 180),
  max_players smallint not null check (max_players between 4 and 30),
  cost_label text not null default '' check (char_length(cost_label) <= 40),
  skill text not null default 'Misto' check (skill in ('Misto','Amatoriale','Intermedio','Competitivo')),
  visibility text not null check (visibility in ('public','private')),
  admission text not null check (admission in ('approval','open')),
  description text not null default '' check (char_length(description) <= 1000),
  status text not null default 'scheduled' check (status in ('scheduled','in_progress','completed','cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((latitude is null) = (longitude is null))
);
create index if not exists events_public_start_idx on public.events(starts_at) where visibility='public' and status='scheduled';
create index if not exists events_creator_idx on public.events(creator_id, starts_at desc);
create or replace function public.guard_event_update()
returns trigger language plpgsql set search_path = '' as $$
begin
  if new.creator_id is distinct from old.creator_id or new.created_at is distinct from old.created_at then
    raise exception 'immutable_event_fields' using errcode='42501';
  end if;
  if new.status='scheduled' and new.starts_at<=pg_catalog.now() then
    raise exception 'event_must_be_future' using errcode='22023';
  end if;
  if new.max_players < 1 + (select pg_catalog.count(*) from public.event_members m where m.event_id=old.id and m.state='approved') then
    raise exception 'capacity_below_current_roster' using errcode='23514';
  end if;
  new.updated_at:=pg_catalog.now();
  return new;
end $$;
revoke all on function public.guard_event_update() from public,anon,authenticated;
drop trigger if exists guard_event_update_trigger on public.events;
create trigger guard_event_update_trigger before update on public.events
  for each row execute function public.guard_event_update();



-- Organizer WhatsApp is private by default and stored separately from public events.
-- Only the organizer or an admitted event member can read it, and only when
-- the organizer has explicitly opted in to sharing the number.
create table if not exists public.event_host_contacts (
  event_id uuid primary key references public.events(id) on delete cascade,
  whatsapp_phone text not null check (whatsapp_phone ~ '^\+[1-9][0-9]{7,14}$'),
  share_with_approved boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.event_host_contacts enable row level security;
create table if not exists public.event_members (
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  state text not null check (state in ('pending','approved','declined','removed')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key(event_id,user_id)
);
create index if not exists event_members_user_idx on public.event_members(user_id,event_id);

create table if not exists public.event_invites (
  event_id uuid primary key references public.events(id) on delete cascade,
  token_hash bytea not null unique,
  created_at timestamptz not null default now(),
  expires_at timestamptz
);

create table if not exists public.pin_suggestions (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id) on delete cascade,
  user_id uuid not null references public.profiles(id),
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  state text not null default 'pending' check (state in ('pending','approved','rejected')),
  created_at timestamptz not null default now()
);
create index if not exists pin_suggestions_event_idx on public.pin_suggestions(event_id,created_at desc);
create index if not exists pin_suggestions_user_idx on public.pin_suggestions(user_id,created_at desc);

create table if not exists public.player_reports (
  id uuid primary key default gen_random_uuid(),
  event_id uuid not null references public.events(id),
  reporter_id uuid not null references public.profiles(id),
  subject_id uuid not null references public.profiles(id),
  reason text not null check (reason in ('Comportamento scorretto','Molestie o minacce','Frode o falsa identità','Altro problema di sicurezza')),
  details text not null check (char_length(details) between 12 and 1500),
  state text not null default 'received' check (state in ('received','in_review','actioned','no_action','appealed')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  review_note text check (char_length(review_note) <= 2000)
);
create index if not exists player_reports_event_idx on public.player_reports(event_id,created_at desc);
create index if not exists player_reports_reporter_idx on public.player_reports(reporter_id,created_at desc);
create index if not exists player_reports_subject_idx on public.player_reports(subject_id,created_at desc);

-- Support submissions contain only information the user chooses to provide.
-- Do not expose this table through the client Data API; Edge Functions use the
-- service role only after verifying the caller's identity/authorization.
create table if not exists public.support_requests (
  id uuid primary key default gen_random_uuid(),
  requester_user_id uuid references public.profiles(id) on delete set null,
  category text not null check (category in ('bug','account','event','safety','other')),
  subject text not null check (char_length(subject) between 4 and 120),
  details text not null check (char_length(details) between 20 and 4000),
  contact_name text check (char_length(contact_name) <= 80),
  contact_email text check (char_length(contact_email) <= 254),
  contact_allowed boolean not null default false,
  status text not null default 'new' check (status in ('new','in_progress','waiting_user','resolved','closed')),
  admin_reply text check (char_length(admin_reply) <= 3000),
  search_document tsvector generated always as
    (to_tsvector('simple', coalesce(subject,'') || ' ' || coalesce(details,'') || ' ' || coalesce(contact_name,'') || ' ' || coalesce(contact_email,''))) stored,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (contact_allowed or (contact_name is null and contact_email is null))
);
create index if not exists support_requests_search_idx on public.support_requests using gin(search_document);
create index if not exists support_requests_queue_idx on public.support_requests(status,created_at desc);
create index if not exists support_requests_requester_idx on public.support_requests(requester_user_id,created_at desc);
alter table public.support_requests enable row level security;
revoke all on public.support_requests from anon,authenticated;

create table if not exists public.support_request_audit (
  id bigint generated always as identity primary key,
  ticket_id uuid not null references public.support_requests(id) on delete cascade,
  actor_id uuid not null references auth.users(id),
  action text not null check (action in ('status_changed','reply_saved')),
  old_status text,
  new_status text,
  created_at timestamptz not null default now()
);
create index if not exists support_request_audit_ticket_idx on public.support_request_audit(ticket_id,created_at desc);
create index if not exists support_request_audit_actor_idx on public.support_request_audit(actor_id,created_at desc);
alter table public.support_request_audit enable row level security;
revoke all on public.support_request_audit from anon,authenticated;

create table if not exists public.support_submit_quota (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_day date not null default current_date,
  submission_count integer not null default 0
);
alter table public.support_submit_quota enable row level security;
revoke all on public.support_submit_quota from anon,authenticated;
create or replace function public.consume_support_submit_quota(p_user_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare q public.support_submit_quota%rowtype;
begin
  insert into public.support_submit_quota(user_id) values(p_user_id) on conflict do nothing;
  select * into q from public.support_submit_quota where user_id=p_user_id for update;
  if q.window_day < current_date then q.window_day:=current_date; q.submission_count:=0; end if;
  if q.submission_count >= 5 then return false; end if;
  update public.support_submit_quota set window_day=current_date,submission_count=q.submission_count+1 where user_id=p_user_id;
  return true;
end $$;
revoke all on function public.consume_support_submit_quota(uuid) from public,anon,authenticated;
grant execute on function public.consume_support_submit_quota(uuid) to service_role;

create table if not exists public.subscriptions (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  plan text not null default 'free' check (plan in ('free','premium')),
  status text not null default 'inactive' check (status in ('inactive','active','past_due','cancelled')),
  current_period_end timestamptz,
  stripe_customer_id text unique,
  stripe_subscription_id text unique,
  updated_at timestamptz not null default now()
);

-- Unverified Free users can save one private event per rolling 7 days.
-- Public events and joining still require phone verification. Verified Free
-- users can keep 2 active events; active Premium users have no Free cap.
create or replace function public.create_event_with_policy(
  p_title text,p_format smallint,p_kind text,p_starts_at timestamptz,
  p_venue text,p_city text,p_max_players smallint,p_visibility text,
  p_admission text,p_cost_label text default '',p_skill text default 'Misto',
  p_description text default '',p_latitude double precision default null,
  p_longitude double precision default null,p_invite_token_hash bytea default null
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  v_user uuid := auth.uid(); v_role text; v_phone_verified boolean;
  v_plan text := 'free'; v_event uuid;
begin
  if v_user is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if not public.is_email_confirmed() then raise exception 'email_confirmation_required' using errcode='42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(8112026,pg_catalog.hashtext(v_user::text));
  select p.role,(p.phone_verified_at is not null) into v_role,v_phone_verified from public.profiles p where p.id=v_user;
  if v_role is distinct from 'host' then raise exception 'host_role_required' using errcode='42501'; end if;
  select s.plan into v_plan from public.subscriptions s where s.user_id=v_user and s.plan='premium' and s.status='active'
    and (s.current_period_end is null or s.current_period_end>pg_catalog.now()) limit 1;
  v_plan:=coalesce(v_plan,'free');
  if p_visibility is null or p_visibility not in ('public','private') then raise exception 'invalid_visibility' using errcode='22023'; end if;
  if p_visibility='private' and (p_invite_token_hash is null or pg_catalog.octet_length(p_invite_token_hash)<>32) then raise exception 'private_invite_required' using errcode='22023'; end if;
  if p_starts_at is null or p_starts_at<=pg_catalog.now() then raise exception 'event_must_be_future' using errcode='22023'; end if;
  if p_visibility='public' and not coalesce(v_phone_verified,false) then raise exception 'phone_verification_required' using errcode='42501'; end if;
  if not coalesce(v_phone_verified,false) then
    if p_visibility<>'private' then raise exception 'private_event_required' using errcode='42501'; end if;
    if v_plan<>'premium' and exists(select 1 from public.events e where e.creator_id=v_user and e.visibility='private' and e.created_at>=pg_catalog.now()-interval '7 days') then
      raise exception 'weekly_private_event_limit' using errcode='23514'; end if;
  elsif v_plan<>'premium' and (select count(*) from public.events e where e.creator_id=v_user and e.status in ('scheduled','in_progress'))>=2 then
    raise exception 'active_event_limit' using errcode='23514'; end if;
  insert into public.events(creator_id,title,format,kind,starts_at,venue,city,latitude,longitude,max_players,cost_label,skill,visibility,admission,description)
    values(v_user,p_title,p_format,p_kind,p_starts_at,p_venue,p_city,p_latitude,p_longitude,p_max_players,coalesce(p_cost_label,''),coalesce(p_skill,'Misto'),p_visibility,p_admission,coalesce(p_description,'')) returning id into v_event;
  if p_visibility='private' then
    insert into public.event_invites(event_id,token_hash,expires_at) values(v_event,p_invite_token_hash,p_starts_at+interval '1 day');
  end if;
  return v_event;
end $$;
revoke all on function public.create_event_with_policy(text,smallint,text,timestamptz,text,text,smallint,text,text,text,text,text,double precision,double precision,bytea) from public,anon;
grant execute on function public.create_event_with_policy(text,smallint,text,timestamptz,text,text,smallint,text,text,text,text,text,double precision,double precision,bytea) to authenticated;

create or replace function public.is_event_member(p_event uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.event_members m where m.event_id=p_event and m.user_id=(select auth.uid()) and m.state='approved')
$$;
create or replace function public.is_event_owner(p_event uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from public.events e where e.id=p_event and e.creator_id=(select auth.uid()))
$$;
create or replace function public.is_support()
returns boolean language sql stable set search_path = '' as $$
  select coalesce((select auth.jwt()->'app_metadata'->>'role')='support',false)
$$;
create or replace function public.is_email_confirmed()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(
    select 1 from auth.users u
    where u.id=(select auth.uid()) and u.email_confirmed_at is not null
  )
$$;
revoke all on function public.is_event_member(uuid) from public;
revoke all on function public.is_event_owner(uuid) from public;
revoke all on function public.is_event_member(uuid),public.is_event_owner(uuid) from anon;
revoke all on function public.is_email_confirmed() from public,anon;
grant execute on function public.is_event_member(uuid),public.is_event_owner(uuid) to authenticated;
grant execute on function public.is_email_confirmed() to authenticated;
create policy event_contact_select_owner_or_admitted on public.event_host_contacts for select to authenticated
  using (public.is_email_confirmed() and (public.is_event_owner(event_id) or (share_with_approved and public.is_event_member(event_id))));
create policy event_contact_insert_owner on public.event_host_contacts for insert to authenticated
  with check (public.is_email_confirmed() and public.is_event_owner(event_id) and public.is_phone_verified());
create policy event_contact_update_owner on public.event_host_contacts for update to authenticated
  using (public.is_email_confirmed() and public.is_event_owner(event_id)) with check (public.is_email_confirmed() and public.is_event_owner(event_id) and public.is_phone_verified());
create policy event_contact_delete_owner on public.event_host_contacts for delete to authenticated
  using (public.is_email_confirmed() and public.is_event_owner(event_id));

alter table public.profiles enable row level security;
alter table public.events enable row level security;
alter table public.event_members enable row level security;
alter table public.event_host_contacts enable row level security;
alter table public.event_invites enable row level security;
alter table public.pin_suggestions enable row level security;
alter table public.player_reports enable row level security;
alter table public.subscriptions enable row level security;
create policy events_deny_direct_client_access on public.events for all to anon,authenticated using (false) with check (false);

-- Phone numbers stay in Auth; profile rows are visible only to their owner.
-- Add a separate safe username-only view/RPC for rosters before connecting them.
create policy profiles_select_self on public.profiles for select to authenticated using (id=(select auth.uid()));
create policy profiles_insert_self on public.profiles for insert to authenticated with check (id=(select auth.uid()));
create policy profiles_update_self on public.profiles for update to authenticated using (id=(select auth.uid())) with check (id=(select auth.uid()));

-- All event creation is routed through the atomic policy function below.
drop policy if exists events_insert_self on public.events;
drop policy if exists events_select_public_or_allowed on public.events;
drop policy if exists events_update_owner on public.events;
-- Preserve event history, membership decisions and related moderation context;
-- cancel by updating status instead of physically deleting an event.

create policy members_select_self_or_owner on public.event_members for select to authenticated
  using (user_id=(select auth.uid()) or public.is_event_owner(event_id)
    or (state='approved' and public.is_event_member(event_id)));
create policy members_insert_self_pending on public.event_members for insert to authenticated
  with check (user_id=(select auth.uid()) and state='pending' and public.is_phone_verified());
create policy members_owner_update on public.event_members for update to authenticated
  using (public.is_event_owner(event_id)) with check (public.is_event_owner(event_id));
create policy members_owner_delete on public.event_members for delete to authenticated using (public.is_event_owner(event_id));

create policy invites_owner_only on public.event_invites for all to authenticated
  using (public.is_event_owner(event_id)) with check (public.is_event_owner(event_id));

create policy pins_select_event_access on public.pin_suggestions for select to authenticated
  using (public.is_email_confirmed() and (user_id=(select auth.uid()) or public.is_event_owner(event_id)));
create policy pins_insert_member on public.pin_suggestions for insert to authenticated
  with check (public.is_email_confirmed() and user_id=(select auth.uid()) and public.is_phone_verified() and (public.is_event_owner(event_id) or public.is_event_member(event_id)));
create policy pins_owner_update on public.pin_suggestions for update to authenticated
  using (public.is_email_confirmed() and public.is_event_owner(event_id)) with check (public.is_email_confirmed() and public.is_event_owner(event_id));

create policy reports_insert_self on public.player_reports for insert to authenticated
  with check (reporter_id=(select auth.uid()) and reporter_id<>subject_id and public.is_phone_verified());
create policy reports_select_reporter_or_support on public.player_reports for select to authenticated
  using (reporter_id=(select auth.uid()) or public.is_support());
create policy reports_update_support_only on public.player_reports for update to authenticated
  using (public.is_support()) with check (public.is_support());

create policy subscriptions_read_self on public.subscriptions for select to authenticated using (user_id=(select auth.uid()));
-- No client insert/update/delete policies. Only a trusted webhook/service role may write plan state.

revoke all on public.events from anon,authenticated;
grant select on public.profiles to authenticated;
grant update(username,role) on public.profiles to authenticated;
grant select,insert,update,delete on public.event_members to authenticated;
grant select,insert,update,delete on public.event_host_contacts to authenticated;
revoke all on public.verified_phones from anon,authenticated;
grant select,insert,update,delete on public.event_invites to authenticated;
grant select,insert,update on public.pin_suggestions to authenticated;
grant select,insert,update on public.player_reports to authenticated;
grant select on public.subscriptions to authenticated;

-- IMPORTANT: RLS alone is not enough for capacity-safe joins, private invite
-- exchange, per-event free limits, notification delivery, pin approval side-effects,
-- Stripe webhooks or support moderation. Implement narrow RPC/Edge Functions
-- with transactional validation before enabling any online write path.

-- Phone OTP anti-abuse quota. Edge Functions call this with service_role only.
create table if not exists public.phone_otp_quota (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  last_sent_at timestamptz,
  daily_window date not null default current_date,
  daily_count integer not null default 0,
  verify_window_started_at timestamptz,
  verify_attempts integer not null default 0 check (verify_attempts between 0 and 8)
);
alter table public.phone_otp_quota enable row level security;
revoke all on public.phone_otp_quota from anon,authenticated;
create or replace function public.consume_phone_otp_quota(p_user_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare q public.phone_otp_quota%rowtype;
begin
  insert into public.phone_otp_quota(user_id) values(p_user_id) on conflict do nothing;
  select * into q from public.phone_otp_quota where user_id=p_user_id for update;
  if q.daily_window < current_date then q.daily_window:=current_date; q.daily_count:=0; end if;
  if q.daily_count >= 5 or (q.last_sent_at is not null and q.last_sent_at > now()-interval '60 seconds') then return false; end if;
  update public.phone_otp_quota set daily_window=current_date,daily_count=q.daily_count+1,last_sent_at=now(),verify_window_started_at=now(),verify_attempts=0 where user_id=p_user_id;
  return true;
end $$;
revoke all on function public.consume_phone_otp_quota(uuid) from public,anon,authenticated;
grant execute on function public.consume_phone_otp_quota(uuid) to service_role;

create or replace function public.consume_phone_otp_check(p_user_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare q public.phone_otp_quota%rowtype;
begin
  select * into q from public.phone_otp_quota where user_id=p_user_id for update;
  if not found or q.last_sent_at is null or q.last_sent_at < pg_catalog.now()-interval '10 minutes' then return false; end if;
  if q.verify_window_started_at is null or q.verify_window_started_at < pg_catalog.now()-interval '10 minutes' then
    q.verify_window_started_at:=pg_catalog.now(); q.verify_attempts:=0;
  end if;
  if q.verify_attempts>=8 then return false; end if;
  update public.phone_otp_quota set verify_window_started_at=q.verify_window_started_at,verify_attempts=q.verify_attempts+1 where user_id=p_user_id;
  return true;
end $$;
revoke all on function public.consume_phone_otp_check(uuid) from public,anon,authenticated;
grant execute on function public.consume_phone_otp_check(uuid) to service_role;


-- Temporary server-only OTP destination; deleted after verification and expires quickly.
create table if not exists public.phone_otp_pending (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  phone text not null,
  expires_at timestamptz not null default now()+interval '10 minutes'
);
alter table public.phone_otp_pending enable row level security;
revoke all on public.phone_otp_pending from anon,authenticated;

-- Sensitive operational tables have no client grant and explicit deny policies.
-- Trusted Edge Functions use service_role, which bypasses RLS by design.
create policy verified_phones_deny_clients on public.verified_phones for all to anon,authenticated using (false) with check (false);
create policy support_requests_deny_clients on public.support_requests for all to anon,authenticated using (false) with check (false);
create policy support_request_audit_deny_clients on public.support_request_audit for all to anon,authenticated using (false) with check (false);
create policy support_submit_quota_deny_clients on public.support_submit_quota for all to anon,authenticated using (false) with check (false);
create policy phone_otp_quota_deny_clients on public.phone_otp_quota for all to anon,authenticated using (false) with check (false);
create policy phone_otp_pending_deny_clients on public.phone_otp_pending for all to anon,authenticated using (false) with check (false);

create or replace function public.complete_phone_verification(p_user_id uuid,p_phone_hash text)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_phone_hash !~ '^[a-f0-9]{64}$' then raise exception 'invalid_phone_hash' using errcode='22023'; end if;
  insert into public.verified_phones(user_id,phone_hash) values(p_user_id,p_phone_hash);
  update public.profiles set phone_verified_at=pg_catalog.now() where id=p_user_id;
  if not found then raise exception 'profile_not_found' using errcode='P0002'; end if;
  delete from public.phone_otp_pending where user_id=p_user_id;
  return true;
end $$;
revoke all on function public.complete_phone_verification(uuid,text) from public,anon,authenticated;
grant execute on function public.complete_phone_verification(uuid,text) to service_role;

-- V2: membership changes must go through transactional functions. Direct table
-- writes would let a verified user request access to a private event by guessing
-- its UUID, or overfill an event by racing the organizer's approvals.
drop policy if exists members_insert_self_pending on public.event_members;
drop policy if exists members_owner_update on public.event_members;
drop policy if exists members_owner_delete on public.event_members;
revoke insert,update,delete on public.event_members from anon,authenticated;
grant select on public.event_members to authenticated;

drop policy if exists reports_insert_self on public.player_reports;
revoke insert on public.player_reports from anon,authenticated;
grant select,update on public.player_reports to authenticated;

-- Single read path for the web UI. It returns only event fields, a public
-- username and counts; pending invitees do not receive the exact venue/pin.
create or replace function public.event_feed()
returns table(
  id uuid,creator_id uuid,creator_name text,title text,format smallint,kind text,
  starts_at timestamptz,venue text,city text,latitude double precision,longitude double precision,
  max_players smallint,cost_label text,skill text,visibility text,admission text,
  description text,status text,created_at timestamptz,updated_at timestamptz,
  participant_count integer,my_state text
)
language sql stable security definer set search_path = '' as $$
  select e.id,e.creator_id,p.username,e.title,e.format,e.kind,e.starts_at,
    case when e.visibility='private' and e.creator_id is distinct from (select auth.uid()) and mine.state is distinct from 'approved'
      then 'Luogo comunicato dopo l’ammissione' else e.venue end,
    e.city,
    case when e.visibility='private' and e.creator_id is distinct from (select auth.uid()) and mine.state is distinct from 'approved'
      then null else e.latitude end,
    case when e.visibility='private' and e.creator_id is distinct from (select auth.uid()) and mine.state is distinct from 'approved'
      then null else e.longitude end,
    e.max_players,e.cost_label,e.skill,e.visibility,e.admission,e.description,e.status,e.created_at,e.updated_at,
    (1+count(m.user_id) filter (where m.state='approved'))::integer,mine.state
  from public.events e
  join public.profiles p on p.id=e.creator_id
  left join public.event_members m on m.event_id=e.id
  left join public.event_members mine on mine.event_id=e.id and mine.user_id=(select auth.uid())
  where (e.visibility='public' and e.status='scheduled' and e.starts_at>pg_catalog.now())
    or e.creator_id=(select auth.uid())
    or exists(select 1 from public.event_members applies where applies.event_id=e.id and applies.user_id=(select auth.uid()) and applies.state in ('pending','approved'))
    or exists(select 1 from public.event_members prior where prior.event_id=e.id and prior.user_id=(select auth.uid()) and prior.state in ('declined','removed'))
  group by e.id,p.username,mine.state
  order by e.starts_at asc
$$;
revoke all on function public.event_feed() from public;
grant execute on function public.event_feed() to anon,authenticated;

drop policy if exists events_select_public_or_allowed on public.events;
drop policy if exists events_deny_direct_client_access on public.events;
create policy events_deny_direct_client_access on public.events for all to anon,authenticated using (false) with check (false);

create or replace function public.create_event_invite(p_event_id uuid,p_token_hash bytea)
returns void language plpgsql security definer set search_path = '' as $$
declare v_starts_at timestamptz;
begin
  if (select auth.uid()) is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if not public.is_email_confirmed() then raise exception 'email_confirmation_required' using errcode='42501'; end if;
  if p_token_hash is null or pg_catalog.octet_length(p_token_hash)<>32 then raise exception 'invalid_invite' using errcode='22023'; end if;
  select e.starts_at into v_starts_at from public.events e
    where e.id=p_event_id and e.creator_id=(select auth.uid()) and e.visibility='private' and e.status='scheduled';
  if not found or v_starts_at<=pg_catalog.now() then
    raise exception 'private_event_owner_required' using errcode='42501';
  end if;
  insert into public.event_invites(event_id,token_hash,created_at,expires_at)
    values(p_event_id,p_token_hash,pg_catalog.now(),v_starts_at+interval '1 day')
  on conflict(event_id) do update set token_hash=excluded.token_hash,created_at=excluded.created_at,expires_at=excluded.expires_at;
end $$;
revoke all on function public.create_event_invite(uuid,bytea) from public,anon;
grant execute on function public.create_event_invite(uuid,bytea) to authenticated;

-- Editing is transactional: private invite token rotation and event fields
-- update together. Direct reads of the base events table stay unavailable.
create or replace function public.update_event_with_policy(
  p_event_id uuid,p_title text,p_format smallint,p_kind text,p_starts_at timestamptz,
  p_venue text,p_city text,p_max_players smallint,p_visibility text,p_admission text,
  p_cost_label text default '',p_skill text default 'Misto',p_description text default '',
  p_latitude double precision default null,p_longitude double precision default null,
  p_invite_token_hash bytea default null
) returns boolean language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=(select auth.uid()); v_owner uuid; v_status text; v_old_start timestamptz; v_role text; v_phone_verified boolean;
begin
  if v_user is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if not public.is_email_confirmed() then raise exception 'email_confirmation_required' using errcode='42501'; end if;
  select e.creator_id,e.status,e.starts_at into v_owner,v_status,v_old_start from public.events e where e.id=p_event_id for update;
  if not found or v_owner<>v_user then raise exception 'event_owner_required' using errcode='42501'; end if;
  if v_status<>'scheduled' or v_old_start<=pg_catalog.now() then raise exception 'event_closed' using errcode='22023'; end if;
  if p_starts_at is null or p_starts_at<=pg_catalog.now() then raise exception 'event_must_be_future' using errcode='22023'; end if;
  if p_visibility not in ('public','private') then raise exception 'invalid_visibility' using errcode='22023'; end if;
  select p.role,(p.phone_verified_at is not null) into v_role,v_phone_verified from public.profiles p where p.id=v_user;
  if v_role is distinct from 'host' then raise exception 'host_role_required' using errcode='42501'; end if;
  if p_visibility='public' and not coalesce(v_phone_verified,false) then raise exception 'phone_verification_required' using errcode='42501'; end if;
  if p_visibility='private' and p_invite_token_hash is not null and pg_catalog.octet_length(p_invite_token_hash)<>32 then raise exception 'invalid_invite' using errcode='22023'; end if;
  update public.events set title=p_title,format=p_format,kind=p_kind,starts_at=p_starts_at,venue=p_venue,city=p_city,
    max_players=p_max_players,visibility=p_visibility,admission=p_admission,cost_label=coalesce(p_cost_label,''),
    skill=coalesce(p_skill,'Misto'),description=coalesce(p_description,''),latitude=p_latitude,longitude=p_longitude
    where id=p_event_id;
  if p_visibility='private' then
    if p_invite_token_hash is not null then
      insert into public.event_invites(event_id,token_hash,created_at,expires_at)
        values(p_event_id,p_invite_token_hash,pg_catalog.now(),p_starts_at+interval '1 day')
      on conflict(event_id) do update set token_hash=excluded.token_hash,created_at=excluded.created_at,expires_at=excluded.expires_at;
    else
      update public.event_invites set expires_at=p_starts_at+interval '1 day' where event_id=p_event_id;
      if not found then raise exception 'private_invite_required' using errcode='22023'; end if;
    end if;
  else
    delete from public.event_invites where event_id=p_event_id;
  end if;
  return true;
end $$;
revoke all on function public.update_event_with_policy(uuid,text,smallint,text,timestamptz,text,text,smallint,text,text,text,text,text,double precision,double precision,bytea) from public,anon;
grant execute on function public.update_event_with_policy(uuid,text,smallint,text,timestamptz,text,text,smallint,text,text,text,text,text,double precision,double precision,bytea) to authenticated;

create or replace function public.update_event_pin(p_event_id uuid,p_latitude double precision,p_longitude double precision)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null or not public.is_email_confirmed() or not public.is_event_owner(p_event_id) then
    raise exception 'event_owner_required' using errcode='42501';
  end if;
  if (p_latitude is null)<>(p_longitude is null) or p_latitude not between -90 and 90 or p_longitude not between -180 and 180 then
    raise exception 'invalid_pin' using errcode='22023';
  end if;
  update public.events set latitude=p_latitude,longitude=p_longitude where id=p_event_id;
  return found;
end $$;
revoke all on function public.update_event_pin(uuid,double precision,double precision) from public,anon;
grant execute on function public.update_event_pin(uuid,double precision,double precision) to authenticated;

create or replace function public.update_event_status(p_event_id uuid,p_status text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_old_status text;
begin
  if (select auth.uid()) is null or not public.is_email_confirmed() or not public.is_event_owner(p_event_id) then
    raise exception 'event_owner_required' using errcode='42501';
  end if;
  if p_status not in ('in_progress','completed','cancelled') then raise exception 'invalid_event_status' using errcode='22023'; end if;
  select e.status into v_old_status from public.events e where e.id=p_event_id for update;
  if not found then raise exception 'event_not_found' using errcode='P0002'; end if;
  if (v_old_status='scheduled' and p_status not in ('in_progress','cancelled'))
    or (v_old_status='in_progress' and p_status not in ('completed','cancelled'))
    or v_old_status in ('completed','cancelled') then raise exception 'invalid_event_transition' using errcode='22023'; end if;
  update public.events set status=p_status where id=p_event_id;
  return found;
end $$;
revoke all on function public.update_event_status(uuid,text) from public,anon;
grant execute on function public.update_event_status(uuid,text) to authenticated;

-- A private invite is a high-entropy bearer link. This RPC reveals only the
-- minimum event details needed to decide whether to register or request a place.
create or replace function public.get_event_invitation(p_token text)
returns table(event_id uuid,title text,format smallint,kind text,starts_at timestamptz,venue text,city text,
  max_players smallint,cost_label text,skill text,admission text,description text,status text,organizer_username text)
language sql stable security definer set search_path = '' as $$
  select e.id,e.title,e.format,e.kind,e.starts_at,'Luogo comunicato dopo l’ammissione',e.city,e.max_players,e.cost_label,e.skill,e.admission,
    e.description,e.status,p.username
  from public.event_invites i
  join public.events e on e.id=i.event_id and e.visibility='private'
  join public.profiles p on p.id=e.creator_id
  where p_token ~ '^[a-f0-9]{64}$'
    and i.token_hash=extensions.digest(pg_catalog.convert_to(p_token,'UTF8'),'sha256')
    and (i.expires_at is null or i.expires_at>pg_catalog.now())
$$;
revoke all on function public.get_event_invitation(text) from public;
grant execute on function public.get_event_invitation(text) to anon,authenticated;

create or replace function public.request_event_join(p_event_id uuid,p_invite_token text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=(select auth.uid()); v_event public.events%rowtype; v_phone_verified boolean; v_state text; v_active_count integer;
begin
  if v_user is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if not public.is_email_confirmed() then raise exception 'email_confirmation_required' using errcode='42501'; end if;
  select (p.phone_verified_at is not null) into v_phone_verified from public.profiles p where p.id=v_user;
  perform pg_catalog.pg_advisory_xact_lock(82022026,pg_catalog.hashtext(p_event_id::text));
  select * into v_event from public.events e where e.id=p_event_id for update;
  if not found then raise exception 'event_not_found' using errcode='P0002'; end if;
  if v_event.status<>'scheduled' or v_event.starts_at<=pg_catalog.now() then raise exception 'event_closed' using errcode='22023'; end if;
  if v_event.creator_id=v_user then return 'owner'; end if;
  if v_event.visibility='public' and not coalesce(v_phone_verified,false) then raise exception 'phone_verification_required' using errcode='42501'; end if;
  if v_event.visibility='private' and not exists(
    select 1 from public.event_invites i where i.event_id=v_event.id
      and p_invite_token ~ '^[a-f0-9]{64}$'
      and i.token_hash=extensions.digest(pg_catalog.convert_to(p_invite_token,'UTF8'),'sha256')
      and (i.expires_at is null or i.expires_at>pg_catalog.now())
  ) then raise exception 'invite_required' using errcode='42501'; end if;
  select m.state into v_state from public.event_members m where m.event_id=v_event.id and m.user_id=v_user for update;
  if v_state in ('pending','approved') then raise exception 'already_applied' using errcode='23505'; end if;
  -- A previous refusal/removal always requires a fresh organizer decision,
  -- including open-admission events. Voluntary departures also use 'removed',
  -- so they can request another place without bypassing an organizer's removal.
  v_state:=case when v_state in ('declined','removed') then 'pending'
    when v_event.admission='open' then 'approved' else 'pending' end;
  if v_state='approved' then
    select 1+pg_catalog.count(*) into v_active_count from public.event_members m where m.event_id=v_event.id and m.state='approved';
    if v_active_count>=v_event.max_players then raise exception 'event_full' using errcode='23514'; end if;
  end if;
  insert into public.event_members(event_id,user_id,state) values(v_event.id,v_user,v_state)
    on conflict(event_id,user_id) do update set state=excluded.state,updated_at=pg_catalog.now()
    where public.event_members.state in ('declined','removed');
  if not found then raise exception 'already_applied' using errcode='23505'; end if;
  return v_state;
end $$;
revoke all on function public.request_event_join(uuid,text) from public,anon;
grant execute on function public.request_event_join(uuid,text) to authenticated;

create or replace function public.manage_event_member(p_event_id uuid,p_user_id uuid,p_state text)
returns text language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=(select auth.uid()); v_event public.events%rowtype; v_old_state text; v_count integer;
begin
  if v_user is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if not public.is_email_confirmed() then raise exception 'email_confirmation_required' using errcode='42501'; end if;
  if p_state not in ('approved','declined','removed') or p_user_id=v_user then raise exception 'invalid_member_action' using errcode='22023'; end if;
  perform pg_catalog.pg_advisory_xact_lock(82022026,pg_catalog.hashtext(p_event_id::text));
  select * into v_event from public.events e where e.id=p_event_id for update;
  if not found or v_event.creator_id<>v_user then raise exception 'event_owner_required' using errcode='42501'; end if;
  if v_event.status<>'scheduled' or v_event.starts_at<=pg_catalog.now() then raise exception 'event_closed' using errcode='22023'; end if;
  select m.state into v_old_state from public.event_members m where m.event_id=p_event_id and m.user_id=p_user_id for update;
  if not found then raise exception 'member_not_found' using errcode='P0002'; end if;
  if p_state='approved' and v_old_state<>'approved' then
    select 1+pg_catalog.count(*) into v_count from public.event_members m where m.event_id=p_event_id and m.state='approved';
    if v_count>=v_event.max_players then raise exception 'event_full' using errcode='23514'; end if;
  end if;
  update public.event_members set state=p_state,updated_at=pg_catalog.now() where event_id=p_event_id and user_id=p_user_id;
  return p_state;
end $$;
revoke all on function public.manage_event_member(uuid,uuid,text) from public,anon;
grant execute on function public.manage_event_member(uuid,uuid,text) to authenticated;

create or replace function public.leave_event(p_event_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=(select auth.uid()); v_event public.events%rowtype;
begin
  if v_user is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if not public.is_email_confirmed() then raise exception 'email_confirmation_required' using errcode='42501'; end if;
  perform pg_catalog.pg_advisory_xact_lock(82022026,pg_catalog.hashtext(p_event_id::text));
  select * into v_event from public.events e where e.id=p_event_id for update;
  if not found or v_event.status<>'scheduled' or v_event.starts_at<=pg_catalog.now() then raise exception 'event_closed' using errcode='22023'; end if;
  update public.event_members set state='removed',updated_at=pg_catalog.now()
    where event_id=p_event_id and user_id=v_user and state in ('pending','approved');
  return found;
end $$;
revoke all on function public.leave_event(uuid) from public,anon;
grant execute on function public.leave_event(uuid) to authenticated;

create or replace function public.event_roster(p_event_id uuid)
returns table(user_id uuid,username text,state text,joined_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
declare v_user uuid:=(select auth.uid()); v_owner boolean; v_member boolean;
begin
  if v_user is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if not public.is_email_confirmed() then raise exception 'email_confirmation_required' using errcode='42501'; end if;
  v_owner:=public.is_event_owner(p_event_id); v_member:=public.is_event_member(p_event_id);
  if not v_owner and not v_member then raise exception 'event_roster_forbidden' using errcode='42501'; end if;
  return query select p.id,p.username,m.state,m.created_at from public.event_members m
    join public.profiles p on p.id=m.user_id
    where m.event_id=p_event_id and (
      (v_owner and m.state in ('pending','approved')) or (v_member and m.state='approved') or m.user_id=v_user
    ) order by m.created_at;
end $$;
revoke all on function public.event_roster(uuid) from public,anon;
grant execute on function public.event_roster(uuid) to authenticated;

create or replace function public.event_pin_suggestions(p_event_id uuid)
returns table(id uuid,user_id uuid,username text,latitude double precision,longitude double precision,state text,created_at timestamptz)
language plpgsql stable security definer set search_path = '' as $$
begin
  if (select auth.uid()) is null or not public.is_email_confirmed() or not public.is_event_owner(p_event_id) then
    raise exception 'event_owner_required' using errcode='42501';
  end if;
  return query select s.id,s.user_id,p.username,s.latitude,s.longitude,s.state,s.created_at
    from public.pin_suggestions s join public.profiles p on p.id=s.user_id
    where s.event_id=p_event_id order by s.created_at desc limit 50;
end $$;
revoke all on function public.event_pin_suggestions(uuid) from public,anon;
grant execute on function public.event_pin_suggestions(uuid) to authenticated;

create or replace function public.approve_event_pin(p_event_id uuid,p_suggestion_id uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_lat double precision; v_lon double precision;
begin
  if (select auth.uid()) is null or not public.is_email_confirmed() or not public.is_event_owner(p_event_id) then
    raise exception 'event_owner_required' using errcode='42501';
  end if;
  perform 1 from public.events e where e.id=p_event_id for update;
  if not found then raise exception 'event_not_found' using errcode='P0002'; end if;
  select s.latitude,s.longitude into v_lat,v_lon from public.pin_suggestions s
    where s.id=p_suggestion_id and s.event_id=p_event_id and s.state='pending' for update;
  if not found then raise exception 'pin_suggestion_not_found' using errcode='P0002'; end if;
  update public.events set latitude=v_lat,longitude=v_lon where id=p_event_id;
  update public.pin_suggestions set state=case when id=p_suggestion_id then 'approved' else 'rejected' end
    where event_id=p_event_id and state='pending';
  return true;
end $$;
revoke all on function public.approve_event_pin(uuid,uuid) from public,anon;
grant execute on function public.approve_event_pin(uuid,uuid) to authenticated;

create or replace function public.submit_player_report(p_event_id uuid,p_subject_id uuid,p_reason text,p_details text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=(select auth.uid()); v_report uuid;
begin
  if v_user is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if not public.is_email_confirmed() then raise exception 'email_confirmation_required' using errcode='42501'; end if;
  if p_subject_id=v_user or p_reason not in ('Comportamento scorretto','Molestie o minacce','Frode o falsa identità','Altro problema di sicurezza')
    or pg_catalog.char_length(pg_catalog.btrim(p_details)) not between 12 and 1500 then raise exception 'invalid_report' using errcode='22023'; end if;
  if not public.is_phone_verified() then raise exception 'phone_verification_required' using errcode='42501'; end if;
  if not (public.is_event_owner(p_event_id) or public.is_event_member(p_event_id)) then raise exception 'event_membership_required' using errcode='42501'; end if;
  if not (exists(select 1 from public.event_members m where m.event_id=p_event_id and m.user_id=p_subject_id and m.state='approved')
      or exists(select 1 from public.events e where e.id=p_event_id and e.creator_id=p_subject_id)) then
    raise exception 'report_subject_not_in_event' using errcode='42501';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(82032026,pg_catalog.hashtext(v_user::text));
  if (select pg_catalog.count(*) from public.player_reports r where r.reporter_id=v_user and r.created_at>pg_catalog.now()-interval '24 hours')>=5 then
    raise exception 'report_rate_limit' using errcode='23514';
  end if;
  insert into public.player_reports(event_id,reporter_id,subject_id,reason,details)
    values(p_event_id,v_user,p_subject_id,p_reason,pg_catalog.btrim(p_details)) returning id into v_report;
  return v_report;
end $$;
revoke all on function public.submit_player_report(uuid,uuid,text,text) from public,anon;
grant execute on function public.submit_player_report(uuid,uuid,text,text) to authenticated;

revoke all on function public.create_profile_for_new_user() from public,anon,authenticated;
revoke all on function public.is_support() from public,anon;
grant execute on function public.is_support() to authenticated;

-- Final least-privilege pass. Revoke inherited/default Data API grants first,
-- then grant only the operations used by the policies and trusted functions.
revoke all on public.profiles,public.events,public.event_members,public.event_host_contacts,
  public.event_invites,public.pin_suggestions,public.player_reports,public.support_requests,
  public.support_request_audit,public.support_submit_quota,public.subscriptions,
  public.verified_phones,public.phone_otp_quota,public.phone_otp_pending
  from anon,authenticated;
grant select on public.profiles to authenticated;
grant update(username,role) on public.profiles to authenticated;
grant select on public.event_members to authenticated;
grant select,insert,update,delete on public.event_host_contacts to authenticated;
grant select,insert,update on public.pin_suggestions to authenticated;
grant select,update on public.player_reports to authenticated;
grant select on public.subscriptions to authenticated;
