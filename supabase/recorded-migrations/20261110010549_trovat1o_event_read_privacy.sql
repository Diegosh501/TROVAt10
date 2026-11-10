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
drop policy if exists events_update_owner on public.events;
drop policy if exists events_deny_direct_client_access on public.events;
create policy events_deny_direct_client_access on public.events for all to anon,authenticated using (false) with check (false);
revoke all on public.events from anon,authenticated;
revoke all on function public.is_event_applicant(uuid) from anon;