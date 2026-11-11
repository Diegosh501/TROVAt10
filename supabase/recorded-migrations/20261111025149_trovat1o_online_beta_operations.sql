do $$ begin if exists(select 1 from auth.users) or exists(select 1 from public.events) then raise exception 'readiness_migration_requires_prelaunch_database'; end if; end $$;

-- Source: supabase/host-contact.sql SHA256 0f3f642239eca6aae36889a3d188543455d2c302897cd68d26225203af2af0e7
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


-- Source: supabase/retention.sql SHA256 daffb53567965218bc4ddb1f1a6164d3f10a5e996b75364177aa73c44883f2ee
-- Event lifecycle and per-account history. Apply AFTER the Google/free-access,
-- notification and billing migrations. No account expires with its matches.
-- This file does NOT install extensions or activate a job without operator action.
alter table public.events add column closed_at timestamptz;
alter table public.events add column archived_at timestamptz;

-- A legacy row has no trustworthy closure timestamp. Grant a full seven-day
-- grace from migration time rather than infer closure from creation/start time.
-- The pre-launch database was empty when this migration was prepared.
update public.events set closed_at=pg_catalog.now()
where status in ('completed','cancelled') and closed_at is null;
alter table public.events add constraint events_closed_timestamp_matches_state
  check ((status in ('completed','cancelled'))=(closed_at is not null));
alter table public.events add constraint events_archive_requires_closure
  check (archived_at is null or (closed_at is not null and archived_at>=closed_at));
create index events_retention_closed_idx on public.events(closed_at,id)
  where closed_at is not null and archived_at is null;
create index events_retention_archive_idx on public.events(archived_at,id)
  where archived_at is not null;

create or replace function private.stamp_event_lifecycle()
returns trigger language plpgsql set search_path='' as $$
begin
  if tg_op='INSERT' then
    if new.status<>'scheduled' or new.closed_at is not null or new.archived_at is not null then
      raise exception 'new_event_must_be_scheduled' using errcode='22023'; end if;
    return new;
  end if;
  if old.status in ('completed','cancelled') and new.status is distinct from old.status then
    raise exception 'event_already_closed' using errcode='22023'; end if;
  if old.status in ('scheduled','in_progress') and new.status in ('completed','cancelled') then
    new.closed_at:=pg_catalog.now();
  elsif new.closed_at is distinct from old.closed_at then
    raise exception 'immutable_closed_at' using errcode='42501';
  end if;
  -- The public event RPCs accept no archive field and clients have no direct
  -- event writes. Only a trusted database worker/operator can archive/restore.
  if new.archived_at is distinct from old.archived_at and current_user not in ('postgres','supabase_admin','service_role') then
    raise exception 'server_archive_only' using errcode='42501'; end if;
  return new;
end $$;
revoke all on function private.stamp_event_lifecycle() from public,anon,authenticated;
create trigger a_event_lifecycle_stamp before insert or update on public.events
  for each row execute function private.stamp_event_lifecycle();

create table private.event_retention_holds (
  event_id uuid not null references public.events(id) on delete cascade,
  reason text not null check (reason in ('security_review','legal_preservation','support_review')),
  hold_until timestamptz not null,
  updated_at timestamptz not null default now(),
  primary key(event_id,reason)
);
create table private.event_retention_runs (
  id bigint generated always as identity primary key,
  ran_at timestamptz not null default now(),
  archived integer not null,restored integer not null,purged integer not null,
  held integer not null,dependency_blocked boolean not null
);
alter table private.event_retention_holds enable row level security;
alter table private.event_retention_runs enable row level security;
revoke all on private.event_retention_holds,private.event_retention_runs from public,anon,authenticated;

create or replace function private.active_history_premium(p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.subscriptions s where s.user_id=p_user
    and s.plan='premium' and s.status='active' and s.current_period_end>pg_catalog.now())
$$;
create or replace function private.event_has_premium_keeper(p_event uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.events e where e.id=p_event and
    (private.active_history_premium(e.creator_id) or exists(select 1 from public.event_members m
      where m.event_id=e.id and m.state='approved' and private.active_history_premium(m.user_id))))
$$;
create or replace function private.history_visible_for(p_event uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.events e where e.id=p_event and (
    (e.archived_at is null and (e.closed_at is null or e.closed_at>pg_catalog.now()-interval '7 days'))
    or (private.active_history_premium(p_user) and (e.creator_id=p_user or exists(
      select 1 from public.event_members m where m.event_id=e.id and m.user_id=p_user and m.state='approved')))))
$$;
revoke all on function private.active_history_premium(uuid),private.event_has_premium_keeper(uuid),
  private.history_visible_for(uuid,uuid) from public,anon,authenticated;

-- Restrictive policies close direct child-table side channels. They do not
-- replace the existing ownership/membership policies or grant new access.
create or replace function public.event_history_accessible(p_event uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select (select auth.uid()) is not null and public.is_email_confirmed()
    and private.history_visible_for(p_event,(select auth.uid())) and exists(
      select 1 from public.events e where e.id=p_event and (e.creator_id=(select auth.uid()) or exists(
        select 1 from public.event_members m where m.event_id=e.id and m.user_id=(select auth.uid()))))
$$;
revoke all on function public.event_history_accessible(uuid) from public,anon;
grant execute on function public.event_history_accessible(uuid) to authenticated;
create policy members_retained_history on public.event_members as restrictive for select to authenticated
  using (public.event_history_accessible(event_id));
create policy contacts_retained_history on public.event_host_contacts as restrictive for select to authenticated
  using (public.event_history_accessible(event_id));
create policy invites_retained_history on public.event_invites as restrictive for select to authenticated
  using (public.event_history_accessible(event_id));
create policy pins_retained_history on public.pin_suggestions as restrictive for select to authenticated
  using (public.event_history_accessible(event_id));
create policy notices_retained_history on public.app_notifications as restrictive for select to authenticated
  using (event_id is null or public.event_history_accessible(event_id));

-- Same return type/columns as the deployed feed: existing clients stay compatible.
create or replace function public.event_feed()
returns table(
  id uuid,creator_id uuid,creator_name text,title text,format smallint,kind text,
  starts_at timestamptz,venue text,city text,latitude double precision,longitude double precision,
  max_players smallint,cost_label text,skill text,visibility text,admission text,
  description text,status text,created_at timestamptz,updated_at timestamptz,
  participant_count integer,my_state text
)
language sql stable security definer set search_path='' as $$
  select e.id,e.creator_id,p.username,e.title,e.format,e.kind,e.starts_at,
    case when e.visibility='private' and e.creator_id is distinct from (select auth.uid()) and mine.state is distinct from 'approved'
      then 'Luogo comunicato dopo l’ammissione' else e.venue end,
    e.city,
    case when e.visibility='private' and e.creator_id is distinct from (select auth.uid()) and mine.state is distinct from 'approved'
      then null else e.latitude end,
    case when e.visibility='private' and e.creator_id is distinct from (select auth.uid()) and mine.state is distinct from 'approved'
      then null else e.longitude end,
    e.max_players,e.cost_label,e.skill,e.visibility,e.admission,e.description,e.status,e.created_at,e.updated_at,
    (1+count(m.user_id) filter(where m.state='approved'))::integer,mine.state
  from public.events e join public.profiles p on p.id=e.creator_id
  left join public.event_members m on m.event_id=e.id
  left join public.event_members mine on mine.event_id=e.id and mine.user_id=(select auth.uid())
  where ((select auth.uid()) is null or public.is_email_confirmed())
    and private.history_visible_for(e.id,(select auth.uid())) and (
    (e.visibility='public' and e.status='scheduled' and e.starts_at>pg_catalog.now())
    or e.creator_id=(select auth.uid())
    or exists(select 1 from public.event_members applies where applies.event_id=e.id and applies.user_id=(select auth.uid())))
  group by e.id,p.username,mine.state order by e.starts_at asc
$$;
revoke all on function public.event_feed() from public;
grant execute on function public.event_feed() to anon,authenticated;

-- A saved bearer link cannot revive an expired private match. Private location
-- masking is unchanged and no expired history is made public by Premium.
create or replace function public.get_event_invitation(p_token text)
returns table(event_id uuid,title text,format smallint,kind text,starts_at timestamptz,venue text,city text,
  max_players smallint,cost_label text,skill text,admission text,description text,status text,organizer_username text)
language sql stable security definer set search_path='' as $$
  select e.id,e.title,e.format,e.kind,e.starts_at,'Luogo comunicato dopo l’ammissione',e.city,e.max_players,e.cost_label,e.skill,e.admission,
    e.description,e.status,p.username
  from public.event_invites i join public.events e on e.id=i.event_id and e.visibility='private'
  join public.profiles p on p.id=e.creator_id
  where p_token~'^[a-f0-9]{64}$' and i.token_hash=extensions.digest(pg_catalog.convert_to(p_token,'UTF8'),'sha256')
    and (i.expires_at is null or i.expires_at>pg_catalog.now()) and e.archived_at is null
    and (e.closed_at is null or e.closed_at>pg_catalog.now()-interval '7 days')
$$;
revoke all on function public.get_event_invitation(text) from public;
grant execute on function public.get_event_invitation(text) to anon,authenticated;

create or replace function public.set_event_retention_hold(p_event uuid,p_reason text,p_until timestamptz)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if p_reason is null or p_reason not in ('security_review','legal_preservation','support_review') then
    raise exception 'invalid_hold_reason' using errcode='22023'; end if;
  perform 1 from public.events where id=p_event for update;
  if not found then raise exception 'event_not_found' using errcode='P0002'; end if;
  if p_until is null then
    delete from private.event_retention_holds where event_id=p_event and reason=p_reason;
  else
    if p_until<=pg_catalog.now() or p_until>pg_catalog.now()+interval '366 days' then
      raise exception 'invalid_hold_expiry' using errcode='22023'; end if;
    insert into private.event_retention_holds(event_id,reason,hold_until) values(p_event,p_reason,p_until)
      on conflict(event_id,reason) do update set hold_until=excluded.hold_until,updated_at=pg_catalog.now();
  end if;
  return true;
end $$;
revoke all on function public.set_event_retention_hold(uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function public.set_event_retention_hold(uuid,text,timestamptz) to service_role;

-- Reject unknown/transitively added FK dependencies before any physical purge.
-- Reports are explicitly excluded below, never cascaded or removed by this job.
create or replace function private.retention_dependencies_known()
returns boolean language sql stable security definer set search_path='' as $$
  select not exists(select 1 from pg_catalog.pg_constraint c where c.contype='f' and c.confrelid in (
    'public.events'::regclass,'public.event_members'::regclass,'public.event_host_contacts'::regclass,
    'public.event_invites'::regclass,'public.pin_suggestions'::regclass,'public.app_notifications'::regclass,
    'public.notification_delivery_queue'::regclass,'private.event_retention_holds'::regclass)
    and not (
      (c.confrelid='public.events'::regclass and c.conrelid in (
        'public.event_members'::regclass,'public.event_host_contacts'::regclass,'public.event_invites'::regclass,
        'public.pin_suggestions'::regclass,'public.app_notifications'::regclass,'private.event_retention_holds'::regclass)
        and c.confdeltype='c')
      or (c.confrelid='public.events'::regclass and c.conrelid='public.player_reports'::regclass and c.confdeltype in ('a','r'))
      or (c.confrelid='public.app_notifications'::regclass and c.conrelid='public.notification_delivery_queue'::regclass and c.confdeltype='c')))
$$;
revoke all on function private.retention_dependencies_known() from public,anon,authenticated;

create or replace function public.run_event_retention(p_limit integer default 250)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  e public.events%rowtype; archived_count integer:=0; restored_count integer:=0;
  purged_count integer:=0; held_count integer:=0; dependencies_ok boolean;
begin
  if p_limit is null or p_limit not between 1 and 500 then raise exception 'invalid_batch_limit' using errcode='22023'; end if;
  if not pg_catalog.pg_try_advisory_xact_lock(90112026,1) then return jsonb_build_object('skipped','already_running'); end if;
  dependencies_ok:=private.retention_dependencies_known();

  for e in select ev.* from public.events ev where ev.archived_at is not null and private.event_has_premium_keeper(ev.id)
    order by ev.archived_at,ev.id limit p_limit for update skip locked loop
    update public.events set archived_at=null where id=e.id;
    restored_count:=restored_count+1;
  end loop;
  for e in select ev.* from public.events ev where ev.closed_at<=pg_catalog.now()-interval '7 days'
    and ev.archived_at is null and not private.event_has_premium_keeper(ev.id)
    order by ev.closed_at,ev.id limit p_limit for update skip locked loop
    -- Closure time is preserved; an update/archive never restarts the seven days.
    update public.events set archived_at=pg_catalog.now() where id=e.id;
    archived_count:=archived_count+1;
  end loop;

  if dependencies_ok then
    for e in select ev.* from public.events ev where ev.archived_at<=pg_catalog.now()-interval '24 hours'
      and not private.event_has_premium_keeper(ev.id)
      and not exists(select 1 from public.player_reports r where r.event_id=ev.id)
      and not exists(select 1 from private.event_retention_holds h where h.event_id=ev.id and h.hold_until>pg_catalog.now())
      and not exists(select 1 from (
        select ev.creator_id user_id union select m.user_id from public.event_members m where m.event_id=ev.id and m.state='approved'
      ) keepers left join public.subscriptions s on s.user_id=keepers.user_id where s.user_id is null)
      order by ev.archived_at,ev.id limit p_limit for update skip locked loop
      -- A known subscription row for every keeper is required. Lock it against
      -- concurrent paid-plan updates; unknown legacy plan state fails closed.
      if exists(select 1 from (
        select e.creator_id user_id union select m.user_id from public.event_members m where m.event_id=e.id and m.state='approved'
      ) keepers left join public.subscriptions s on s.user_id=keepers.user_id where s.user_id is null) then
        continue;
      end if;
      perform s.user_id from public.subscriptions s where s.user_id=e.creator_id or s.user_id in (
        select m.user_id from public.event_members m where m.event_id=e.id and m.state='approved') for share;
      if private.event_has_premium_keeper(e.id) then continue; end if;
      -- Expected cascades: roster, invite, host contact, pins, notifications and
      -- notification deliveries. Any future restrictive FK fails this row safe.
      begin
        delete from public.events where id=e.id;
        purged_count:=purged_count+1;
      exception when foreign_key_violation then
        held_count:=held_count+1;
      end;
    end loop;
  end if;
  select held_count+pg_catalog.count(*) into held_count from public.events ev
    where ev.archived_at is not null and (exists(select 1 from public.player_reports r where r.event_id=ev.id)
      or exists(select 1 from private.event_retention_holds h where h.event_id=ev.id and h.hold_until>pg_catalog.now())
      or exists(select 1 from (
        select ev.creator_id user_id union select m.user_id from public.event_members m where m.event_id=ev.id and m.state='approved'
      ) keepers left join public.subscriptions s on s.user_id=keepers.user_id where s.user_id is null));
  insert into private.event_retention_runs(archived,restored,purged,held,dependency_blocked)
    values(archived_count,restored_count,purged_count,held_count,not dependencies_ok);
  delete from private.event_retention_runs where ran_at<pg_catalog.now()-interval '30 days';
  if pg_catalog.to_regclass('cron.job_run_details') is not null then
    delete from cron.job_run_details where jobid in (
      select jobid from cron.job where jobname='trovat1o-event-retention-v1'
    ) and start_time<pg_catalog.now()-interval '30 days';
  end if;
  return jsonb_build_object('archived',archived_count,'restored',restored_count,'purged',purged_count,
    'held',held_count,'dependencyBlocked',not dependencies_ok,'ranAt',pg_catalog.now());
end $$;
revoke all on function public.run_event_retention(integer) from public,anon,authenticated;
grant execute on function public.run_event_retention(integer) to service_role;

-- Separate activation: the core migration is usable without pg_cron. The
-- operator enables that bundled extension and calls this service-only function.
-- No network call, new hosting service, key or per-job vendor account is needed.
create or replace function public.configure_event_retention_cron(p_enabled boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_job bigint;
begin
  if p_enabled is null then raise exception 'invalid_schedule_state' using errcode='22023'; end if;
  if pg_catalog.to_regnamespace('cron') is null then raise exception 'cron_not_enabled' using errcode='55000'; end if;
  if p_enabled then
    select cron.schedule('trovat1o-event-retention-v1','17 * * * *','select public.run_event_retention(250);') into v_job;
  else
    select jobid into v_job from cron.job where jobname='trovat1o-event-retention-v1';
    if v_job is not null then perform cron.alter_job(v_job,active:=false); end if;
  end if;
  return jsonb_build_object('enabled',p_enabled,'jobId',v_job);
end $$;
revoke all on function public.configure_event_retention_cron(boolean) from public,anon,authenticated;
grant execute on function public.configure_event_retention_cron(boolean) to service_role;


-- Source: supabase/admin-operations.sql SHA256 9a14efab0cf78acc2ca454d9bbc2c632dfc9466fbfa67026defec51040cfbab5
-- Extend the already protected console. Operational roles never assign Admin.
alter table private.admin_audit drop constraint if exists admin_audit_action_check;
alter table private.admin_audit add constraint admin_audit_action_check check(action in (
  'dashboard_read','tickets_read','ticket_updated','admin_enabled','admin_disabled','audit_read',
  'users_read','events_read','reports_read','user_role_updated','report_reviewed','event_cancelled'));

create or replace function public.admin_users(p_query text default '',p_role text default '',p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb; total bigint;
begin
  perform private.require_platform_admin('users_read');
  if p_query is null or length(p_query)>100 or p_role is null or p_role not in ('','host','sportivo')
    or p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'invalid_request' using errcode='22023'; end if;
  select count(*) into total from public.profiles p where (p_role='' or p.role=p_role) and (p_query='' or p.username ilike '%'||p_query||'%');
  select coalesce(jsonb_agg(r.data order by r.username,r.id),'[]') into rows from (
    select p.username,p.id,jsonb_build_object('id',p.id,'username',p.username,'role',p.role,'createdAt',p.created_at,
      'plan',case when s.plan='premium' and s.status='active' and s.current_period_end>now() then 'premium' else 'free' end,
      'activeEvents',(select count(*) from public.events e where e.creator_id=p.id and e.status in ('scheduled','in_progress'))) as data
    from public.profiles p left join public.subscriptions s on s.user_id=p.id
    where (p_role='' or p.role=p_role) and (p_query='' or p.username ilike '%'||p_query||'%')
    order by p.username,p.id limit 25 offset p_offset) r;
  return jsonb_build_object('rows',rows,'total',total,'offset',p_offset,'limit',25);
end $$;

create or replace function public.admin_events(p_query text default '',p_status text default '',p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb; total bigint;
begin
  perform private.require_platform_admin('events_read');
  if p_query is null or length(p_query)>100 or p_status is null or p_status not in ('','scheduled','in_progress','completed','cancelled')
    or p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'invalid_request' using errcode='22023'; end if;
  select count(*) into total from public.events e join public.profiles p on p.id=e.creator_id
    where (p_status='' or e.status=p_status) and (p_query='' or e.title ilike '%'||p_query||'%' or p.username ilike '%'||p_query||'%');
  select coalesce(jsonb_agg(r.data order by r.starts_at desc,r.id),'[]') into rows from (
    select e.starts_at,e.id,jsonb_build_object('id',e.id,'title',e.title,'startsAt',e.starts_at,'format',e.format,
      'status',e.status,'visibility',e.visibility,'creatorUsername',p.username) as data
    from public.events e join public.profiles p on p.id=e.creator_id
    where (p_status='' or e.status=p_status) and (p_query='' or e.title ilike '%'||p_query||'%' or p.username ilike '%'||p_query||'%')
    order by e.starts_at desc,e.id limit 25 offset p_offset) r;
  return jsonb_build_object('rows',rows,'total',total,'offset',p_offset,'limit',25);
end $$;

create or replace function public.admin_reports(p_query text default '',p_status text default '',p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb; total bigint;
begin
  perform private.require_platform_admin('reports_read');
  if p_query is null or length(p_query)>100 or p_status is null or p_status not in ('','received','in_review','actioned','no_action','appealed')
    or p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'invalid_request' using errcode='22023'; end if;
  select count(*) into total from public.player_reports r join public.profiles s on s.id=r.subject_id
    join public.profiles p on p.id=r.reporter_id where (p_status='' or r.state=p_status) and
      (p_query='' or s.username ilike '%'||p_query||'%' or p.username ilike '%'||p_query||'%' or r.reason ilike '%'||p_query||'%');
  select coalesce(jsonb_agg(x.data order by x.created_at desc,x.id),'[]') into rows from (
    select r.created_at,r.id,jsonb_build_object('id',r.id,'eventId',r.event_id,'subjectUsername',s.username,
      'reporterUsername',p.username,'reason',r.reason,'details',r.details,'state',r.state,'createdAt',r.created_at,
      'reviewNote',r.review_note) as data from public.player_reports r join public.profiles s on s.id=r.subject_id
    join public.profiles p on p.id=r.reporter_id where (p_status='' or r.state=p_status) and
      (p_query='' or s.username ilike '%'||p_query||'%' or p.username ilike '%'||p_query||'%' or r.reason ilike '%'||p_query||'%')
    order by r.created_at desc,r.id limit 25 offset p_offset) x;
  return jsonb_build_object('rows',rows,'total',total,'offset',p_offset,'limit',25);
end $$;

create or replace function public.admin_set_user_role(p_id uuid,p_role text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  perform private.require_platform_admin('user_role_updated',p_id);
  if p_id is null or p_role is null or p_role not in ('host','sportivo') then raise exception 'invalid_request' using errcode='22023'; end if;
  update public.profiles set role=p_role where id=p_id;
  if not found then raise exception 'not_found' using errcode='PT404'; end if;
  return true;
end $$;
create or replace function public.admin_review_report(p_id uuid,p_status text,p_note text default '')
returns boolean language plpgsql security definer set search_path='' as $$
begin
  perform private.require_platform_admin('report_reviewed',p_id);
  if p_id is null or p_status is null or p_status not in ('received','in_review','actioned','no_action','appealed')
    or p_note is null or length(p_note)>2000 then raise exception 'invalid_request' using errcode='22023'; end if;
  update public.player_reports set state=p_status,review_note=p_note,
    reviewed_at=case when p_status in ('actioned','no_action') then now() else null end where id=p_id;
  if not found then raise exception 'not_found' using errcode='PT404'; end if;
  return true;
end $$;
create or replace function public.admin_cancel_event(p_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare state text;
begin
  perform private.require_platform_admin('event_cancelled',p_id);
  select e.status into state from public.events e where id=p_id for update;
  if not found then raise exception 'not_found' using errcode='PT404'; end if;
  if state='cancelled' then return true; end if;
  if state='completed' then raise exception 'closed_event' using errcode='22023'; end if;
  update public.events set status='cancelled',updated_at=now() where id=p_id;
  return true;
end $$;
revoke all on function public.admin_users(text,text,integer),public.admin_events(text,text,integer),public.admin_reports(text,text,integer),
  public.admin_set_user_role(uuid,text),public.admin_review_report(uuid,text,text),public.admin_cancel_event(uuid) from public,anon;
grant execute on function public.admin_users(text,text,integer),public.admin_events(text,text,integer),public.admin_reports(text,text,integer),
  public.admin_set_user_role(uuid,text),public.admin_review_report(uuid,text,text),public.admin_cancel_event(uuid) to authenticated;


-- Source: supabase/account-export.sql SHA256 f68cd59244aed5d4e1f117363b42807da26a4693b738ef53e7ad32b89647a60d
-- Subject-access export: caller-owned records only, paginated without Auth
-- tokens, phone HMACs, invitation tokens or other participants' personal data.
create table private.account_export_quota (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 window_at timestamptz not null, attempts integer not null
);
alter table private.account_export_quota enable row level security;
revoke all on private.account_export_quota from public,anon,authenticated;
create or replace function public.export_my_data(p_section text,p_after uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); sid uuid; rows jsonb; n integer;
begin
 if u is null or not public.is_email_confirmed() or not exists(select 1 from public.profiles where id=u) then
   raise exception 'authentication_required' using errcode='PT401'; end if;
 begin sid:=(auth.jwt()->>'session_id')::uuid; exception when invalid_text_representation then sid:=null; end;
 if sid is null or not exists(select 1 from auth.sessions where id=sid and user_id=u and (not_after is null or not_after>now())) then
   raise exception 'session_revoked' using errcode='PT401'; end if;
 if p_section is null or p_section not in ('profile','events','participations','reports','notifications','contacts','preferences','subscription','support') then
   raise exception 'invalid_section' using errcode='22023'; end if;
 insert into private.account_export_quota(user_id,window_at,attempts) values(u,now(),1)
 on conflict(user_id) do update set attempts=case when account_export_quota.window_at<now()-interval '1 minute' then 1 else account_export_quota.attempts+1 end,
   window_at=case when account_export_quota.window_at<now()-interval '1 minute' then now() else account_export_quota.window_at end returning attempts into n;
 if n>60 then raise exception 'export_rate_limited' using errcode='PT429'; end if;
 if p_section='profile' then
   select jsonb_build_array(jsonb_build_object('id',p.id,'username',p.username,'role',p.role,'email',a.email,
     'createdAt',p.created_at,'adultConfirmedAt',p.age_confirmed_at,'termsAcceptedAt',p.terms_accepted_at,
     'privacyAcknowledgedAt',p.privacy_notice_ack_at,'termsVersion',p.terms_version,'privacyVersion',p.privacy_notice_version,
     'phoneVerifiedAt',p.phone_verified_at,'googleName',a.raw_user_meta_data->>'full_name','googleAvatar',a.raw_user_meta_data->>'avatar_url')) into rows from public.profiles p join auth.users a on a.id=p.id where p.id=u and p_after is null;
 elsif p_section='events' then
   select jsonb_agg(x.data order by x.id) into rows from(select e.id,jsonb_build_object('id',e.id,'title',e.title,'format',e.format,
     'kind',e.kind,'startsAt',e.starts_at,'venue',e.venue,'city',e.city,'latitude',e.latitude,'longitude',e.longitude,
     'maxPlayers',e.max_players,'visibility',e.visibility,'admission',e.admission,'description',e.description,
     'costLabel',e.cost_label,'skill',e.skill,'status',e.status,'createdAt',e.created_at,'updatedAt',e.updated_at,
     'closedAt',to_jsonb(e)->'closed_at','archivedAt',to_jsonb(e)->'archived_at') as data
     from public.events e where e.creator_id=u and (p_after is null or e.id>p_after) order by e.id limit 100) x;
 elsif p_section='participations' then
   select jsonb_agg(x.data order by x.id) into rows from(select m.event_id as id,jsonb_build_object('id',m.event_id,
     'eventId',m.event_id,'state',m.state,'createdAt',m.created_at,'updatedAt',m.updated_at) as data
     from public.event_members m where m.user_id=u and (p_after is null or m.event_id>p_after) order by m.event_id limit 100) x;
 elsif p_section='reports' then
   select jsonb_agg(x.data order by x.id) into rows from(select r.id,jsonb_build_object('id',r.id,'eventId',r.event_id,
     'reason',r.reason,'details',r.details,'state',r.state,'createdAt',r.created_at,'reviewedAt',r.reviewed_at,'reviewNote',r.review_note) as data
     from public.player_reports r where r.reporter_id=u and (p_after is null or r.id>p_after) order by r.id limit 100) x;
 elsif p_section='notifications' then
   select jsonb_agg(x.data order by x.id) into rows from(select a.id,jsonb_build_object('id',a.id,'eventId',a.event_id,
     'type',a.type,'title',a.title,'body',a.body,'createdAt',a.created_at,'readAt',a.read_at) as data
     from public.app_notifications a where a.user_id=u and (p_after is null or a.id>p_after) order by a.id limit 100) x;
 elsif p_section='contacts' then
   select jsonb_agg(x.data order by x.id) into rows from(select c.event_id as id,jsonb_build_object('id',c.event_id,
     'phone',c.whatsapp_phone,'shareWithApproved',c.share_with_approved,'updatedAt',c.updated_at) as data
     from public.event_host_contacts c join public.events e on e.id=c.event_id where e.creator_id=u
       and (p_after is null or c.event_id>p_after) order by c.event_id limit 100) x;
 elsif p_section='support' then
   select jsonb_agg(x.data order by x.id) into rows from(select r.id,
     (to_jsonb(r)-'requester_user_id'-'search_document') as data from public.support_requests r
     where r.requester_user_id=u and (p_after is null or r.id>p_after) order by r.id limit 100) x;
 elsif p_section='preferences' then
   select jsonb_build_array(jsonb_build_object('id',n.user_id,'activityEnabled',n.activity_enabled,'remindersEnabled',n.reminders_enabled,
     'pushEnabled',n.push_enabled,'pushConsentAt',n.push_consent_at,'updatedAt',n.updated_at)) into rows
     from public.notification_preferences n where n.user_id=u and p_after is null;
 else
   select jsonb_build_array(jsonb_build_object('id',s.user_id,'plan',s.plan,'status',s.status,'currentPeriodEnd',s.current_period_end,
     'updatedAt',s.updated_at)) into rows from public.subscriptions s where s.user_id=u and p_after is null;
 end if;
 rows:=coalesce(rows,'[]'::jsonb);
 return jsonb_build_object('section',p_section,'rows',rows,'nextCursor',case when jsonb_array_length(rows)=100 then rows->99->>'id' else null end,
   'generatedAt',now(),'version',1);
end $$;
revoke all on function public.export_my_data(text,uuid) from public,anon;
grant execute on function public.export_my_data(text,uuid) to authenticated;


-- Source: supabase/write-quotas.sql SHA256 9d4072fad7a7dabdb47def1401115df442d5248632c7c19153497c5aa568dbc0
-- Apply after schema.sql, admin-security.sql and free-access.sql.
-- Technical abuse ceilings, separate from plan limits. No scheduler is enabled.
create table if not exists private.write_action_quotas (
  user_id uuid not null references auth.users(id) on delete cascade,
  action text not null check(action in ('event_create','join','manage')),
  minute_bucket timestamptz not null,
  minute_count integer not null check(minute_count>=1),
  hour_bucket timestamptz not null,
  hour_count integer not null check(hour_count>=1),
  primary key(user_id,action)
);
alter table private.write_action_quotas enable row level security;
revoke all on private.write_action_quotas from public,anon,authenticated;

create or replace function private.consume_write_quota(p_action text)
returns void language plpgsql security definer set search_path='' as $$
declare
  v_user uuid:=auth.uid();
  v_at timestamptz:=pg_catalog.now();
  v_min integer; v_hour integer; v_allowed integer;
begin
  if v_user is null then return; end if;
  if p_action='event_create' then v_min:=10; v_hour:=60;
  elsif p_action in ('join','manage') then v_min:=60; v_hour:=600;
  else raise exception 'invalid_write_quota_action' using errcode='22023'; end if;
  -- Both windows share the same locked (user,action) row. ON CONFLICT's WHERE
  -- is rechecked on the latest tuple after a concurrent writer releases it.
  insert into private.write_action_quotas as q(user_id,action,minute_bucket,minute_count,hour_bucket,hour_count)
    values(v_user,p_action,pg_catalog.date_trunc('minute',v_at),1,pg_catalog.date_trunc('hour',v_at),1)
  on conflict(user_id,action) do update set
    minute_bucket=excluded.minute_bucket,
    minute_count=case when q.minute_bucket=excluded.minute_bucket then q.minute_count+1 else 1 end,
    hour_bucket=excluded.hour_bucket,
    hour_count=case when q.hour_bucket=excluded.hour_bucket then q.hour_count+1 else 1 end
  where (q.minute_bucket<>excluded.minute_bucket or q.minute_count<v_min)
    and (q.hour_bucket<>excluded.hour_bucket or q.hour_count<v_hour)
  returning 1 into v_allowed;
  if v_allowed is null then raise exception 'write_rate_limited' using errcode='PT429'; end if;
end $$;
revoke all on function private.consume_write_quota(text) from public,anon,authenticated;

create or replace function private.quota_event_insert()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  perform private.consume_write_quota('event_create');
  return new;
end $$;
revoke all on function private.quota_event_insert() from public,anon,authenticated;
drop trigger if exists b_event_write_quota on public.events;
create trigger b_event_write_quota before insert on public.events
  for each row execute function private.quota_event_insert();

create or replace function private.quota_membership_write()
returns trigger language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid();
begin
  if v_user is null then return new; end if;
  if tg_op='UPDATE' and new.state is not distinct from old.state then return new; end if;
  if new.user_id=v_user then
    -- Withdrawal must remain possible even when new requests are throttled.
    if new.state='removed' then return new; end if;
    perform private.consume_write_quota('join');
  else
    -- Only an actual allowlisted administrator with a live session/recent TOTP
    -- may bypass the technical ceiling while moderating other participants.
    -- Normal Admin event creation and their own participation still count.
    if private.platform_admin_denial() is not null then
      perform private.consume_write_quota('manage');
    end if;
  end if;
  return new;
end $$;
revoke all on function private.quota_membership_write() from public,anon,authenticated;
drop trigger if exists b_membership_write_quota on public.event_members;
-- AFTER row triggers count the actual INSERT or UPDATE once. A BEFORE INSERT
-- trigger would also run on the conflict probe of INSERT ... ON CONFLICT UPDATE,
-- charging a returning participant twice. An exception still rolls back the
-- membership, counter and transactional notification work together.
create trigger b_membership_write_quota after insert or update of state on public.event_members
  for each row execute function private.quota_membership_write();

create or replace function public.cleanup_write_quotas()
returns integer language plpgsql security definer set search_path='' as $$
declare n integer;
begin
  delete from private.write_action_quotas where hour_bucket<pg_catalog.now()-interval '48 hours';
  get diagnostics n=row_count;
  return n;
end $$;
revoke all on function public.cleanup_write_quotas() from public,anon,authenticated;
grant execute on function public.cleanup_write_quotas() to service_role;


-- Source: supabase/push-dispatch.sql SHA256 2e24783d6dcb6e505b667f3233b50aec958fc73544855d458f59067402598c74
-- Apply after notifications.sql and retention.sql. No job/secrets activated here.
alter table public.notification_delivery_queue add column lease_token uuid;
alter table public.notification_delivery_queue add column lease_until timestamptz;
alter table public.notification_delivery_queue add column subscription_version timestamptz;
alter table public.notification_delivery_queue add column subscription_fingerprint bytea;

create or replace function private.push_notice_permitted(p_notice uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from public.app_notifications n
    join public.notification_preferences np on np.user_id=n.user_id
    join auth.users u on u.id=n.user_id
    left join public.events e on e.id=n.event_id
    where n.id=p_notice and n.user_id=p_user and n.created_at>=pg_catalog.now()-interval '24 hours'
      and np.push_enabled and np.push_consent_at is not null and np.push_consent_at<=n.created_at
      and case when n.type in ('reminder_24h','reminder_2h') then np.reminders_enabled else np.activity_enabled end
      and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null
      and (u.banned_until is null or u.banned_until<=pg_catalog.now())
      and (n.event_id is null or (e.id is not null and private.history_visible_for(e.id,p_user)
        and (n.type not in ('reminder_24h','reminder_2h') or (e.status='scheduled' and e.starts_at>pg_catalog.now())))))
$$;
revoke all on function private.push_notice_permitted(uuid,uuid) from public,anon,authenticated;

create or replace function public.claim_push_deliveries(p_limit integer default 10)
returns table(delivery_id uuid,lease_token uuid,subscription_id uuid,notice_id uuid,endpoint text,p256dh text,auth text)
language plpgsql security definer set search_path='' as $$
begin
  if p_limit is null or p_limit not between 1 and 25 then raise exception 'invalid_push_batch' using errcode='22023'; end if;
  -- Mark expired or withdrawn work terminal so stale queues cannot accumulate.
  update public.notification_delivery_queue q set status='failed',last_error='expired_or_disabled',lease_token=null,lease_until=null,updated_at=pg_catalog.now()
    where q.status in ('queued','sending') and (not private.push_notice_permitted(q.notification_id,q.user_id)
      or (q.attempts>=5 and (q.status='queued' or coalesce(q.lease_until,q.updated_at+interval '3 minutes')<=pg_catalog.now())));
  return query with picked as (
    select q.id from public.notification_delivery_queue q
    join public.push_subscriptions ps on ps.id=q.subscription_id and ps.user_id=q.user_id
    where q.attempts<5 and ((q.status='queued' and q.next_attempt_at<=pg_catalog.now())
      or (q.status='sending' and coalesce(q.lease_until,q.updated_at+interval '3 minutes')<=pg_catalog.now()))
      and private.push_notice_permitted(q.notification_id,q.user_id)
    order by q.next_attempt_at,q.created_at,q.id for update of q skip locked limit p_limit
  ), claimed as (
    update public.notification_delivery_queue q set status='sending',attempts=q.attempts+1,
      lease_token=gen_random_uuid(),lease_until=pg_catalog.now()+interval '3 minutes',updated_at=pg_catalog.now(),
      subscription_version=(select ps.updated_at from public.push_subscriptions ps where ps.id=q.subscription_id)
      ,subscription_fingerprint=(select extensions.digest(pg_catalog.convert_to(jsonb_build_array(ps.endpoint,ps.p256dh,ps.auth)::text,'UTF8'),'sha256')
        from public.push_subscriptions ps where ps.id=q.subscription_id)
    from picked p where q.id=p.id returning q.*
  ) select c.id,c.lease_token,c.subscription_id,c.notification_id,ps.endpoint,ps.p256dh,ps.auth
    from claimed c join public.push_subscriptions ps on ps.id=c.subscription_id and ps.user_id=c.user_id;
end $$;
revoke all on function public.claim_push_deliveries(integer) from public,anon,authenticated;
grant execute on function public.claim_push_deliveries(integer) to service_role;

-- Recheck immediately before sending; never rely only on the initial claim.
create or replace function public.check_push_delivery(p_delivery uuid,p_lease uuid)
returns jsonb language sql stable security definer set search_path='' as $$
  select jsonb_build_object('delivery_id',q.id,'lease_token',q.lease_token,'subscription_id',ps.id,
    'notice_id',q.notification_id,'endpoint',ps.endpoint,'p256dh',ps.p256dh,'auth',ps.auth)
  from public.notification_delivery_queue q join public.push_subscriptions ps on ps.id=q.subscription_id and ps.user_id=q.user_id
  where q.id=p_delivery and q.status='sending' and q.lease_token=p_lease and q.lease_until>pg_catalog.now()
    and ps.updated_at=q.subscription_version
    and extensions.digest(pg_catalog.convert_to(jsonb_build_array(ps.endpoint,ps.p256dh,ps.auth)::text,'UTF8'),'sha256')=q.subscription_fingerprint
    and private.push_notice_permitted(q.notification_id,q.user_id)
$$;
revoke all on function public.check_push_delivery(uuid,uuid) from public,anon,authenticated;
grant execute on function public.check_push_delivery(uuid,uuid) to service_role;

create or replace function public.finish_push_delivery(p_delivery uuid,p_lease uuid,p_result text)
returns boolean language plpgsql security definer set search_path='' as $$
declare q public.notification_delivery_queue%rowtype;
begin
  if p_result is null or p_result not in ('sent','retry','gone','invalid','skipped') then raise exception 'invalid_push_result' using errcode='22023'; end if;
  select * into q from public.notification_delivery_queue where id=p_delivery for update;
  if not found or q.lease_token is null or q.lease_token is distinct from p_lease then return false; end if;
  if q.status='sent' and p_result='sent' then return true; end if;
  if q.status<>'sending' or q.lease_until is null or q.lease_until<=pg_catalog.now() then return false; end if;
  if p_result='gone' then
    -- A subscription refreshed during an in-flight request must not be deleted.
    delete from public.push_subscriptions ps where ps.id=q.subscription_id and ps.user_id=q.user_id and ps.updated_at=q.subscription_version
      and extensions.digest(pg_catalog.convert_to(jsonb_build_array(ps.endpoint,ps.p256dh,ps.auth)::text,'UTF8'),'sha256')=q.subscription_fingerprint;
    update public.notification_preferences np set push_enabled=false,push_consent_at=null,updated_at=pg_catalog.now()
      where np.user_id=q.user_id and not exists(select 1 from public.push_subscriptions ps where ps.user_id=q.user_id);
  end if;
  update public.notification_delivery_queue set
    status=case when p_result='sent' then 'sent' when p_result='retry' and attempts<5 then 'queued' else 'failed' end,
    sent_at=case when p_result='sent' then pg_catalog.now() else null end,
    last_error=case when p_result='sent' then null else p_result end,
    next_attempt_at=case when p_result='retry' and attempts<5 then pg_catalog.now()+pg_catalog.make_interval(secs=>least(3600,30*power(2,attempts)::integer)) else next_attempt_at end,
    lease_until=null,updated_at=pg_catalog.now()
    where id=p_delivery;
  return true;
end $$;
revoke all on function public.finish_push_delivery(uuid,uuid,text) from public,anon,authenticated;
grant execute on function public.finish_push_delivery(uuid,uuid,text) to service_role;
-- Retire the unleased callback API before this dispatcher can be enabled.
revoke execute on function public.claim_notification_deliveries(integer),public.finish_notification_delivery(uuid,boolean,text),
  public.remove_push_subscription(uuid) from service_role;

create or replace function public.configure_push_dispatch_cron(p_enabled boolean,p_project_ref text default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare v_job bigint; v_secret text; v_url text; v_command text;
begin
  if p_enabled is null then raise exception 'invalid_push_schedule' using errcode='22023'; end if;
  if pg_catalog.to_regnamespace('cron') is null then raise exception 'cron_not_enabled' using errcode='55000'; end if;
  if not p_enabled then
    select jobid into v_job from cron.job where jobname='trovat1o-notifications-v1';
    if v_job is not null then perform cron.alter_job(v_job,active:=false); end if;
    return jsonb_build_object('enabled',false,'jobId',v_job);
  end if;
  if p_project_ref is null or p_project_ref!~'^[a-z0-9]{20}$' or pg_catalog.to_regnamespace('net') is null
    or pg_catalog.to_regclass('vault.decrypted_secrets') is null then raise exception 'push_schedule_unconfigured' using errcode='55000'; end if;
  select decrypted_secret into v_secret from vault.decrypted_secrets where name='trovat1o_push_cron_secret' limit 1;
  if v_secret is null or v_secret!~'^[A-Za-z0-9_-]{43,128}$' then raise exception 'push_schedule_unconfigured' using errcode='55000'; end if;
  v_url:='https://'||p_project_ref||'.supabase.co/functions/v1/push-dispatch';
  -- The URL is public/fixed. The secret is read from Vault only at execution;
  -- cron.job.command never contains its value. No arbitrary URL/header accepted.
  v_command:=format($cmd$select public.queue_event_reminders(); select net.http_post(url:=%L,
    headers:=jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||
      (select decrypted_secret from vault.decrypted_secrets where name='trovat1o_push_cron_secret' limit 1)),
    body:='{}'::jsonb,timeout_milliseconds:=120000);$cmd$,v_url);
  select cron.schedule('trovat1o-notifications-v1','*/5 * * * *',v_command) into v_job;
  return jsonb_build_object('enabled',true,'jobId',v_job);
end $$;
revoke all on function public.configure_push_dispatch_cron(boolean,text) from public,anon,authenticated;
grant execute on function public.configure_push_dispatch_cron(boolean,text) to service_role;



