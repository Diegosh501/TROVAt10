-- A verified account must share the number it actually verified. Legacy contact
-- rows remain visible to their owner but cannot be disclosed to participants.
alter table public.event_host_contacts add column if not exists phone_binding_hash text;
revoke insert,update on public.event_host_contacts from anon,authenticated;
revoke select on public.event_host_contacts from authenticated;
grant select(event_id,whatsapp_phone,share_with_approved,updated_at) on public.event_host_contacts to authenticated;

create table private.host_contact_quota (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  window_at timestamptz not null, attempts integer not null
);
alter table private.host_contact_quota enable row level security;
revoke all on private.host_contact_quota from public,anon,authenticated;

create or replace function public.host_contact_is_current(p_event uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select public.is_email_confirmed() and
    (public.is_event_owner(p_event) or public.is_event_member(p_event)) and exists(
      select 1 from public.event_host_contacts c join public.events e on e.id=c.event_id
      join public.profiles p on p.id=e.creator_id join public.verified_phones v on v.user_id=p.id
      where c.event_id=p_event and p.phone_verified_at is not null and c.phone_binding_hash=v.phone_hash)
$$;
revoke all on function public.host_contact_is_current(uuid) from public,anon;
grant execute on function public.host_contact_is_current(uuid) to authenticated;
drop policy if exists event_contact_select_owner_or_admitted on public.event_host_contacts;
create policy event_contact_select_owner_or_admitted on public.event_host_contacts for select to authenticated
  using(public.is_email_confirmed() and (public.is_event_owner(event_id) or
    (share_with_approved and public.is_event_member(event_id) and public.host_contact_is_current(event_id))));

create or replace function public.authorize_host_contact(p_event uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); s uuid; n integer;
begin
  if u is null or not public.is_email_confirmed() or not public.is_event_owner(p_event) then
    raise exception 'forbidden' using errcode='PT403'; end if;
  begin s:=(auth.jwt()->>'session_id')::uuid;
  exception when invalid_text_representation then s:=null; end;
  if s is null or not exists(select 1 from auth.sessions where id=s and user_id=u and (not_after is null or not_after>now())) then
    raise exception 'session_revoked' using errcode='PT401'; end if;
  insert into private.host_contact_quota(user_id,window_at,attempts) values(u,now(),1)
    on conflict(user_id) do update set attempts=case when host_contact_quota.window_at<now()-interval '1 minute' then 1 else host_contact_quota.attempts+1 end,
      window_at=case when host_contact_quota.window_at<now()-interval '1 minute' then now() else host_contact_quota.window_at end
    returning attempts into n;
  if n>12 then raise exception 'rate_limited' using errcode='PT429'; end if;
  return jsonb_build_object('user_id',u,'session_id',s);
end $$;
revoke all on function public.authorize_host_contact(uuid) from public,anon;
grant execute on function public.authorize_host_contact(uuid) to authenticated;

create or replace function public.set_verified_host_contact(p_user uuid,p_session uuid,p_event uuid,p_phone text,p_hash text,p_share boolean)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if p_user is null or p_session is null or not exists(select 1 from auth.users u
    join auth.sessions s on s.user_id=u.id where u.id=p_user and s.id=p_session
      and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null
      and (u.banned_until is null or u.banned_until<=now()) and (s.not_after is null or s.not_after>now())) then
    raise exception 'unauthorized' using errcode='PT401'; end if;
  perform 1 from public.events where id=p_event and creator_id=p_user for update;
  if not found then raise exception 'forbidden' using errcode='PT403'; end if;
  if p_share is false then delete from public.event_host_contacts where event_id=p_event; return true; end if;
  if p_share is distinct from true or coalesce(p_phone,'')!~'^\+[1-9][0-9]{7,14}$'
    or coalesce(p_hash,'')!~'^[a-f0-9]{64}$' then raise exception 'invalid_request' using errcode='22023'; end if;
  perform 1 from public.verified_phones v join public.profiles p on p.id=v.user_id
    where p.id=p_user and p.phone_verified_at is not null and v.phone_hash=p_hash for update of v,p;
  if not found then raise exception 'phone_mismatch' using errcode='PT403'; end if;
  insert into public.event_host_contacts(event_id,whatsapp_phone,share_with_approved,phone_binding_hash)
    values(p_event,p_phone,true,p_hash) on conflict(event_id) do update set whatsapp_phone=excluded.whatsapp_phone,
      share_with_approved=true,phone_binding_hash=excluded.phone_binding_hash,updated_at=now();
  return true;
end $$;
revoke all on function public.set_verified_host_contact(uuid,uuid,uuid,text,text,boolean) from public,anon,authenticated;
grant execute on function public.set_verified_host_contact(uuid,uuid,uuid,text,text,boolean) to service_role;
