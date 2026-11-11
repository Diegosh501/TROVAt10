-- Apply after schema.sql and oauth-profiles.sql. A verified Google identity
-- with a completed profile unlocks public play without a paid SMS service.
-- A genuinely verified phone remains supported for existing accounts.
create or replace function public.is_play_verified()
returns boolean language sql stable security definer set search_path = '' as $$
  select public.is_email_confirmed() and exists(select 1 from public.profiles p
    where p.id=(select auth.uid()) and p.age_confirmed_at is not null
      and (p.phone_verified_at is not null or public.is_google_verified()))
$$;
revoke all on function public.is_play_verified() from public,anon;
grant execute on function public.is_play_verified() to authenticated;

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
  select p.role,public.is_play_verified() into v_role,v_phone_verified from public.profiles p where p.id=v_user;
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
  select p.role,public.is_play_verified() into v_role,v_phone_verified from public.profiles p where p.id=v_user;
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

create or replace function public.request_event_join(p_event_id uuid,p_invite_token text default null)
returns text language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=(select auth.uid()); v_event public.events%rowtype; v_phone_verified boolean; v_state text; v_active_count integer;
begin
  if v_user is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if not public.is_email_confirmed() then raise exception 'email_confirmation_required' using errcode='42501'; end if;
  select public.is_play_verified() into v_phone_verified from public.profiles p where p.id=v_user;
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

create or replace function public.submit_player_report(p_event_id uuid,p_subject_id uuid,p_reason text,p_details text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=(select auth.uid()); v_report uuid;
begin
  if v_user is null then raise exception 'authentication_required' using errcode='42501'; end if;
  if not public.is_email_confirmed() then raise exception 'email_confirmation_required' using errcode='42501'; end if;
  if p_subject_id=v_user or p_reason not in ('Comportamento scorretto','Molestie o minacce','Frode o falsa identità','Altro problema di sicurezza')
    or pg_catalog.char_length(pg_catalog.btrim(p_details)) not between 12 and 1500 then raise exception 'invalid_report' using errcode='22023'; end if;
  if not public.is_play_verified() then raise exception 'phone_verification_required' using errcode='42501'; end if;
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

-- Phone-contact sharing remains behind phone verification. Google does not
-- prove ownership of an arbitrary WhatsApp number supplied in a form.
drop policy if exists pins_insert_member on public.pin_suggestions;
create policy pins_insert_member on public.pin_suggestions for insert to authenticated
  with check(public.is_email_confirmed() and user_id=(select auth.uid()) and state='pending' and public.is_play_verified()
    and (public.is_event_owner(event_id) or public.is_event_member(event_id)));
