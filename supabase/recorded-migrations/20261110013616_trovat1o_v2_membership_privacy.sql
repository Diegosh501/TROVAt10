-- Reviewed, narrow V2 security corrections. Apply as one remote migration.
-- No user/event row mutations are included.

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

drop policy if exists members_select_self_or_owner on public.event_members;
create policy members_select_self_or_owner on public.event_members for select to authenticated
  using (user_id=(select auth.uid()) or public.is_event_owner(event_id)
    or (state='approved' and public.is_event_member(event_id)));
