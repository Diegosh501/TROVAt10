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
