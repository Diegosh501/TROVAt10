-- Account expiry is separate from seven-day MATCH history. Apply after all
-- existing source migrations. Both enforcement and physical deletion start OFF.
-- Only first event creation starts the clock; joining and role changes do not.
create table private.account_lifecycle_settings (
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default false,
  purge_enabled boolean not null default false,
  policy_version text not null default 'trovat1o-account-2026-11-11-v1',
  updated_at timestamptz not null default now(),
  check(not purge_enabled or enabled)
);
insert into private.account_lifecycle_settings(singleton) values(true);
create table private.account_lifecycle (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  acknowledged_at timestamptz,
  policy_version text,
  first_match_at timestamptz,
  first_notice_at timestamptz,
  deletion_notice_at timestamptz,
  next_check_at timestamptz not null default now(),
  check((acknowledged_at is null)=(policy_version is null)),
  check(first_notice_at is null or first_match_at is not null)
);
create index account_lifecycle_due_idx on private.account_lifecycle(first_match_at,user_id)
  where first_match_at is not null;
create table private.account_retention_holds (
  user_id uuid not null references public.profiles(id) on delete cascade,
  reason text not null check(reason in ('security_review','legal_preservation','support_review')),
  hold_until timestamptz not null,
  primary key(user_id,reason)
);
create table private.account_retention_runs (
  id bigint generated always as identity primary key,
  ran_at timestamptz not null default now(),
  scanned integer not null,warned integer not null,purged integer not null,
  held integer not null,dependency_blocked boolean not null
);
alter table private.account_lifecycle_settings enable row level security;
alter table private.account_lifecycle enable row level security;
alter table private.account_retention_holds enable row level security;
alter table private.account_retention_runs enable row level security;
revoke all on private.account_lifecycle_settings,private.account_lifecycle,
  private.account_retention_holds,private.account_retention_runs from public,anon,authenticated;

alter table public.app_notifications drop constraint app_notifications_type_check;
alter table public.app_notifications add constraint app_notifications_type_check check(type in (
  'join_request','participant_joined','join_approved','join_declined','participant_removed','participant_left',
  'event_updated','event_cancelled','reminder_24h','reminder_2h','account_expiry','account_deletion'
));

create function private.account_lifecycle_expired(p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.account_lifecycle l cross join private.account_lifecycle_settings s
    where l.user_id=p_user and s.enabled and l.policy_version=s.policy_version
      and l.acknowledged_at<=l.first_match_at and l.first_match_at<=now()-interval '7 days'
      and not private.active_history_premium(p_user)
      and not exists(select 1 from private.platform_admins a where a.user_id=p_user))
$$;
revoke all on function private.account_lifecycle_expired(uuid) from public,anon,authenticated;

create function private.require_lifecycle_caller()
returns uuid language plpgsql stable security definer set search_path='' as $$
declare u uuid:=auth.uid(); sid uuid;
begin
  if u is null or not public.is_email_confirmed() then raise exception 'authentication_required' using errcode='PT401'; end if;
  begin sid:=(auth.jwt()->>'session_id')::uuid; exception when invalid_text_representation then sid:=null; end;
  if sid is null or not exists(select 1 from auth.sessions where id=sid and user_id=u and (not_after is null or not_after>now())) then
    raise exception 'session_revoked' using errcode='PT401'; end if;
  return u;
end $$;
revoke all on function private.require_lifecycle_caller() from public,anon,authenticated;

-- Acknowledgement is an explicit contract disclosure, not GDPR marketing consent.
-- It cannot set/reset the first-match timestamp or assert a paid entitlement.
create function public.acknowledge_account_lifecycle(p_policy_version text)
returns boolean language plpgsql security definer set search_path='' as $$
declare u uuid; v text;
begin
  u:=private.require_lifecycle_caller();
  select policy_version into v from private.account_lifecycle_settings;
  if p_policy_version is distinct from v then raise exception 'account_policy_changed' using errcode='22023'; end if;
  insert into private.account_lifecycle(user_id,acknowledged_at,policy_version) values(u,now(),v)
    on conflict(user_id) do update set acknowledged_at=excluded.acknowledged_at,policy_version=excluded.policy_version
      where account_lifecycle.acknowledged_at is null or account_lifecycle.policy_version is distinct from v;
  return true;
end $$;
revoke all on function public.acknowledge_account_lifecycle(text) from public,anon;
grant execute on function public.acknowledge_account_lifecycle(text) to authenticated;

create function public.my_account_lifecycle()
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u uuid; s private.account_lifecycle_settings%rowtype; l private.account_lifecycle%rowtype;
begin
  u:=private.require_lifecycle_caller();
  select * into s from private.account_lifecycle_settings;
  select * into l from private.account_lifecycle where user_id=u;
  return jsonb_build_object('enabled',s.enabled,'purgeEnabled',s.purge_enabled,'policyVersion',s.policy_version,
    'acknowledged',l.policy_version=s.policy_version and l.acknowledged_at is not null,
    'firstMatchAt',l.first_match_at,'expiresAt',l.first_match_at+interval '7 days',
    'expired',private.account_lifecycle_expired(u),'premiumProtected',private.active_history_premium(u),
    'deletionNotBefore',l.deletion_notice_at+interval '48 hours');
end $$;
revoke all on function public.my_account_lifecycle() from public,anon;
grant execute on function public.my_account_lifecycle() to authenticated;

create function private.record_first_match()
returns trigger language plpgsql security definer set search_path='' as $$
declare s private.account_lifecycle_settings%rowtype; l private.account_lifecycle%rowtype; stamp timestamptz;
begin
  select * into s from private.account_lifecycle_settings for share;
  if private.account_lifecycle_expired(new.creator_id) then raise exception 'free_account_expired' using errcode='PT403'; end if;
  select * into l from private.account_lifecycle where user_id=new.creator_id for update;
  if s.enabled and (l.acknowledged_at is null or l.policy_version is distinct from s.policy_version)
    and not exists(select 1 from private.platform_admins a where a.user_id=new.creator_id) then
    raise exception 'account_policy_acknowledgement_required' using errcode='PT403'; end if;
  -- Transaction now() can precede an ACK committed while this transaction
  -- waited. Stamp after acquiring the row lock, so acknowledgement<=first match
  -- cannot become false merely by running the two RPCs in separate tabs.
  stamp:=pg_catalog.clock_timestamp();
  -- ON CONFLICT serializes two first creations. A cancellation/purge cannot reset it.
  insert into private.account_lifecycle(user_id,first_match_at) values(new.creator_id,stamp)
    on conflict(user_id) do update set first_match_at=excluded.first_match_at
      where account_lifecycle.first_match_at is null;
  if s.enabled then
    insert into public.app_notifications(user_id,type,title,body,dedupe_key)
      select stored.user_id,'account_expiry','Il tuo periodo Free è iniziato',
        'Il periodo Free dura 7 giorni dal primo match creato. Trovi la scadenza nel tuo piano. Un Premium verificato protegge l’account; le partite in corso e le pratiche di sicurezza sono salvaguardate.',
        'account-expiry:'||s.policy_version from private.account_lifecycle stored where stored.user_id=new.creator_id
      on conflict(user_id,dedupe_key) do nothing;
    update private.account_lifecycle set first_notice_at=coalesce(first_notice_at,stamp) where user_id=new.creator_id;
  end if;
  return new;
end $$;
revoke all on function private.record_first_match() from public,anon,authenticated;
create trigger z_record_first_match after insert on public.events for each row execute function private.record_first_match();

create function private.guard_expired_account_join()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  -- Existing decisions/withdrawals and Host administration must remain possible.
  if auth.uid()=new.user_id and new.state in ('pending','approved')
    and (tg_op='INSERT' or old.state in ('declined','removed'))
    and private.account_lifecycle_expired(new.user_id) then
    raise exception 'free_account_expired' using errcode='PT403'; end if;
  return new;
end $$;
revoke all on function private.guard_expired_account_join() from public,anon,authenticated;
create trigger z_guard_expired_account_join after insert or update on public.event_members
  for each row execute function private.guard_expired_account_join();

-- Inspect the full cascade graph, not only direct auth/profile references.
-- Unknown application dependencies (including new CASCADEs) stop physical purge.
create function private.account_deletion_dependencies_known()
returns boolean language sql stable security definer set search_path='' as $$
  with recursive targets(id) as (
    select 'auth.users'::regclass::oid union
    select c.conrelid from pg_catalog.pg_constraint c join targets t on c.confrelid=t.id
      where c.contype='f' and c.confdeltype='c'
  ), expected(parent,child,cols,action) as (values
    ('auth.users','public.profiles','id','c'),
    ('auth.users','public.support_request_audit','actor_id','a'),
    ('auth.users','public.support_submit_quota','user_id','c'),
    ('auth.users','private.support_submission_receipts','user_id','c'),
    ('auth.users','private.support_captcha_redemptions','user_id','n'),
    ('auth.users','private.platform_admins','user_id','c'),
    ('auth.users','private.admin_action_quota','user_id','c'),
    ('auth.users','private.admin_audit','actor_id','n'),
    ('auth.users','private.write_action_quotas','user_id','c'),
    ('public.profiles','public.verified_phones','user_id','c'),
    ('public.profiles','public.events','creator_id','a'),
    ('public.profiles','public.event_members','user_id','c'),
    ('public.profiles','public.pin_suggestions','user_id','a'),
    ('public.profiles','public.player_reports','reporter_id','a'),
    ('public.profiles','public.player_reports','subject_id','a'),
    ('public.profiles','public.support_requests','requester_user_id','n'),
    ('public.profiles','public.subscriptions','user_id','c'),
    ('public.profiles','public.phone_otp_quota','user_id','c'),
    ('public.profiles','public.phone_otp_pending','user_id','c'),
    ('public.profiles','public.notification_preferences','user_id','c'),
    ('public.profiles','public.push_subscriptions','user_id','c'),
    ('public.profiles','public.app_notifications','user_id','c'),
    ('public.profiles','public.notification_delivery_queue','user_id','c'),
    ('public.profiles','private.billing_accounts','user_id','c'),
    ('public.profiles','private.billing_quotas','user_id','c'),
    ('public.profiles','private.account_export_quota','user_id','c'),
    ('public.profiles','private.host_contact_quota','user_id','c'),
    ('public.profiles','private.account_lifecycle','user_id','c'),
    ('public.profiles','private.account_retention_holds','user_id','c'),
    ('private.billing_accounts','private.billing_states','user_id,mode','c'),
    ('private.billing_states','private.billing_invoices','mode,subscription_id','c'),
    ('private.billing_states','private.billing_holds','mode,subscription_id','c'),
    ('public.push_subscriptions','public.notification_delivery_queue','subscription_id','c'),
    ('public.app_notifications','public.notification_delivery_queue','notification_id','c')
  ) select not exists(select 1 from pg_catalog.pg_constraint c join targets t on t.id=c.confrelid
    join pg_catalog.pg_namespace ns on ns.oid=c.connamespace
    where c.contype='f' and ns.nspname<>'auth' and not exists(select 1 from expected e
      where pg_catalog.to_regclass(e.parent)=c.confrelid and pg_catalog.to_regclass(e.child)=c.conrelid
        and e.action=c.confdeltype::text and e.cols=(select string_agg(a.attname,',' order by k.n)
          from unnest(c.conkey) with ordinality k(num,n)
          join pg_catalog.pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num)))
$$;
revoke all on function private.account_deletion_dependencies_known() from public,anon,authenticated;

create function private.account_deletion_hold(p_user uuid)
returns text language plpgsql stable security definer set search_path='' as $$
declare has_objects boolean;
begin
  if exists(select 1 from private.platform_admins where user_id=p_user) then return 'administration'; end if;
  if private.active_history_premium(p_user) then return 'premium'; end if;
  if not exists(select 1 from public.subscriptions where user_id=p_user) then return 'unknown_plan'; end if;
  -- Preserve financial mappings even after a plan expires, including pending
  -- checkouts. Billing-record minimisation needs its own explicit policy.
  if exists(select 1 from private.billing_accounts where user_id=p_user) then return 'billing'; end if;
  if exists(select 1 from private.account_retention_holds where user_id=p_user and hold_until>now()) then return 'preservation'; end if;
  if exists(select 1 from public.player_reports where reporter_id=p_user or subject_id=p_user) then return 'safety_report'; end if;
  if exists(select 1 from public.events where creator_id=p_user) then return 'owned_match'; end if;
  if exists(select 1 from public.event_members m join public.events e on e.id=m.event_id where m.user_id=p_user
    and m.state in ('pending','approved') and e.status in ('scheduled','in_progress')) then return 'active_participation'; end if;
  if exists(select 1 from public.pin_suggestions where user_id=p_user) then return 'location_contribution'; end if;
  if exists(select 1 from public.support_requests where requester_user_id=p_user and status not in ('resolved','closed')) then return 'support'; end if;
  if exists(select 1 from public.support_request_audit where actor_id=p_user) then return 'support_audit'; end if;
  -- Storage ownership is not necessarily an FK. Do not silently orphan objects.
  if pg_catalog.to_regclass('storage.objects') is not null then
    if exists(select 1 from information_schema.columns where table_schema='storage' and table_name='objects' and column_name='owner_id') then
      execute 'select exists(select 1 from storage.objects where owner_id::text=$1)' into has_objects using p_user::text;
    elsif exists(select 1 from information_schema.columns where table_schema='storage' and table_name='objects' and column_name='owner') then
      execute 'select exists(select 1 from storage.objects where owner::text=$1)' into has_objects using p_user::text;
    else return 'unknown_storage_ownership'; end if;
    if has_objects then return 'storage'; end if;
  end if;
  return null;
end $$;
revoke all on function private.account_deletion_hold(uuid) from public,anon,authenticated;

create function public.run_account_retention(p_limit integer default 25)
returns jsonb language plpgsql security definer set search_path='' as $$
declare s private.account_lifecycle_settings%rowtype; l private.account_lifecycle%rowtype;
  scanned_count integer:=0;warned_count integer:=0;purged_count integer:=0;held_count integer:=0;deps boolean;
begin
  if p_limit is null or p_limit not between 1 and 100 then raise exception 'invalid_batch_limit' using errcode='22023'; end if;
  if not pg_catalog.pg_try_advisory_xact_lock(91112026,1) then return jsonb_build_object('skipped','already_running'); end if;
  select * into s from private.account_lifecycle_settings for share;
  if not s.enabled then return jsonb_build_object('skipped','disabled','purged',0); end if;
  deps:=private.account_deletion_dependencies_known();
  for l in select a.* from private.account_lifecycle a
    where a.first_match_at<=now()-interval '7 days' and a.next_check_at<=now() and a.policy_version=s.policy_version
      and a.acknowledged_at<=a.first_match_at
    order by a.next_check_at,a.first_match_at,a.user_id limit p_limit for update skip locked loop
    scanned_count:=scanned_count+1;
    begin
      update private.account_lifecycle set next_check_at=now()+interval '6 hours' where user_id=l.user_id;
      -- A single transaction serializes new children and entitlement changes
      -- with deletion. No HTTP lease/check/delete race with a paid webhook.
      perform 1 from auth.users where id=l.user_id for update;
      perform 1 from public.profiles where id=l.user_id for update;
      perform 1 from public.subscriptions where user_id=l.user_id for update;
      if private.active_history_premium(l.user_id) or exists(select 1 from private.platform_admins where user_id=l.user_id) then
        update private.account_lifecycle set deletion_notice_at=null where user_id=l.user_id;
        held_count:=held_count+1;continue;
      end if;
      if l.deletion_notice_at is null then
        insert into public.app_notifications(user_id,type,title,body,dedupe_key)
          values(l.user_id,'account_deletion','Il periodo Free è terminato',
            'Il periodo Free è terminato. Puoi esportare i dati o attivare Premium, se disponibile. La cancellazione può avvenire non prima di 48 ore; partite e pratiche ancora necessarie sono protette.',
            'account-deletion:'||s.policy_version||':'||extract(epoch from now())::text);
        update private.account_lifecycle set deletion_notice_at=now(),next_check_at=now()+interval '48 hours' where user_id=l.user_id;
        warned_count:=warned_count+1;continue;
      end if;
      if not s.purge_enabled or l.deletion_notice_at>now()-interval '48 hours' then continue; end if;
      if not deps or private.account_deletion_hold(l.user_id) is not null then held_count:=held_count+1;continue; end if;
      -- Only unreferenced, unpaid accounts reach this point. Auth-owned rows
      -- and profiles cascade atomically; existing JWTs no longer pass live-user
      -- checks. Never change Supabase's managed schema or disable its triggers.
      delete from auth.users where id=l.user_id;
      if found then purged_count:=purged_count+1; end if;
    exception when foreign_key_violation or deadlock_detected or lock_not_available then
      held_count:=held_count+1;
    end;
  end loop;
  insert into private.account_retention_runs(scanned,warned,purged,held,dependency_blocked)
    values(scanned_count,warned_count,purged_count,held_count,not deps);
  delete from private.account_retention_runs where ran_at<now()-interval '30 days';
  return jsonb_build_object('scanned',scanned_count,'warned',warned_count,'purged',purged_count,
    'held',held_count,'dependencyBlocked',not deps,'purgeEnabled',s.purge_enabled);
end $$;
revoke all on function public.run_account_retention(integer) from public,anon,authenticated;
grant execute on function public.run_account_retention(integer) to service_role;

create function public.set_account_lifecycle_enabled(p_enabled boolean,p_purge_enabled boolean,p_policy_version text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if p_enabled is null or p_purge_enabled is null or (p_purge_enabled and not p_enabled)
    or p_policy_version is distinct from 'trovat1o-account-2026-11-11-v1' then
    raise exception 'invalid_account_lifecycle_configuration' using errcode='22023'; end if;
  update private.account_lifecycle_settings set enabled=p_enabled,purge_enabled=p_purge_enabled,updated_at=now();
  return true;
end $$;
revoke all on function public.set_account_lifecycle_enabled(boolean,boolean,text) from public,anon,authenticated;
grant execute on function public.set_account_lifecycle_enabled(boolean,boolean,text) to service_role;

create function public.set_account_retention_hold(p_user uuid,p_reason text,p_until timestamptz)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if p_reason is null or p_reason not in ('security_review','legal_preservation','support_review') then
    raise exception 'invalid_hold_reason' using errcode='22023'; end if;
  if p_until is not null and (p_until<=now() or p_until>now()+interval '366 days') then
    raise exception 'invalid_hold_expiry' using errcode='22023'; end if;
  -- Same parent lock order as the worker. In particular an UPDATE of an
  -- existing expired hold must serialize with deletion, not just a new FK.
  perform 1 from auth.users where id=p_user for update;
  if not found then raise exception 'account_not_found' using errcode='P0002'; end if;
  perform 1 from public.profiles where id=p_user for update;
  if not found then raise exception 'account_not_found' using errcode='P0002'; end if;
  if p_until is null then delete from private.account_retention_holds where user_id=p_user and reason=p_reason;
  else insert into private.account_retention_holds(user_id,reason,hold_until) values(p_user,p_reason,p_until)
    on conflict(user_id,reason) do update set hold_until=excluded.hold_until; end if;
  return true;
end $$;
revoke all on function public.set_account_retention_hold(uuid,text,timestamptz) from public,anon,authenticated;
grant execute on function public.set_account_retention_hold(uuid,text,timestamptz) to service_role;

create function public.configure_account_retention_cron(p_enabled boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare job bigint;
begin
  if p_enabled is null then raise exception 'invalid_schedule_state' using errcode='22023'; end if;
  if to_regnamespace('cron') is null then raise exception 'cron_not_enabled' using errcode='55000'; end if;
  if p_enabled then
    select cron.schedule('trovat1o-account-retention-v1','37 * * * *','select public.run_account_retention(25);') into job;
  else
    select jobid into job from cron.job where jobname='trovat1o-account-retention-v1';
    if job is not null then perform cron.alter_job(job,active:=false); end if;
  end if;
  return jsonb_build_object('enabled',p_enabled,'jobId',job);
end $$;
revoke all on function public.configure_account_retention_cron(boolean) from public,anon,authenticated;
grant execute on function public.configure_account_retention_cron(boolean) to service_role;
