-- Prepared on an empty pre-launch project. Policy and deletion stay OFF.
-- No existing user or event is deleted by this installation.
do $$ begin
 if exists(select 1 from auth.users) or exists(select 1 from public.profiles) or exists(select 1 from public.events) then
  raise exception 'prelaunch_account_lifecycle_requires_empty_project';
 end if;
end $$;

-- Source: profile-consent-version; SHA256 4b45fb80f508994f3e09deccb22141a75f8271937589670242c30b380a04630f
create or replace function public.complete_my_profile(
  p_username text,p_role text,p_adult_confirmed boolean,p_terms_accepted boolean,p_privacy_acknowledged boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=(select auth.uid()); v_profile public.profiles%rowtype;
begin
  if v_user is null or not public.is_google_verified() then
    raise exception 'google_identity_required' using errcode='42501';
  end if;
  if p_username is null or pg_catalog.btrim(p_username) !~ '^[A-Za-z0-9_.-]{3,24}$'
    or p_role is null or p_role not in ('host','sportivo') then
    raise exception 'invalid_profile' using errcode='22023';
  end if;
  if p_adult_confirmed is distinct from true or p_terms_accepted is distinct from true
    or p_privacy_acknowledged is distinct from true then
    raise exception 'profile_confirmations_required' using errcode='22023';
  end if;
  -- Serializes retries/two tabs of the same account. No arbitrary target UUID.
  perform pg_catalog.pg_advisory_xact_lock(82102026,pg_catalog.hashtext(v_user::text));
  select * into v_profile from public.profiles where id=v_user;
  if not found then
    insert into public.profiles(id,username,role,age_confirmed_at,terms_accepted_at,privacy_notice_ack_at,terms_version,privacy_notice_version)
      values(v_user,pg_catalog.btrim(p_username),p_role,pg_catalog.now(),pg_catalog.now(),pg_catalog.now(),
        'trovat1o-2026-11-11-v2','trovat1o-2026-11-11-v2') returning * into v_profile;
    insert into public.subscriptions(user_id,plan,status) values(v_user,'free','active') on conflict(user_id) do nothing;
  end if;
  -- Repeated completion is idempotent; it never overwrites a profile or plan.
  return pg_catalog.jsonb_build_object('id',v_profile.id,'username',v_profile.username,'role',v_profile.role,
    'age_confirmed_at',v_profile.age_confirmed_at,'phone_verified_at',v_profile.phone_verified_at);
end $$;
revoke all on function public.complete_my_profile(text,text,boolean,boolean,boolean) from public,anon;
grant execute on function public.complete_my_profile(text,text,boolean,boolean,boolean) to authenticated;

-- Source: account-lifecycle.sql; SHA256 08c5210e3d2fffa5a2b9206129eab9692a0400c4a64d43cdde72e3bae4959c21
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

-- Source: export-profile-lifecycle; SHA256 5602110e85068b2f964aa632dc2ae8ab1d200196a9b1127904349d46da798f6f
create or replace function public.export_my_data(p_section text,p_after uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); sid uuid; rows jsonb; n integer; lifecycle jsonb;
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
   if to_regclass('private.account_lifecycle') is not null then
     select jsonb_build_object('firstMatchAt',l.first_match_at,'policyAcknowledgedAt',l.acknowledged_at,
       'policyVersion',l.policy_version,'firstNoticeAt',l.first_notice_at,'deletionNoticeAt',l.deletion_notice_at)
       into lifecycle from private.account_lifecycle l where l.user_id=u;
   end if;
   select jsonb_build_array(jsonb_build_object('id',p.id,'username',p.username,'role',p.role,'email',a.email,
     'createdAt',p.created_at,'adultConfirmedAt',p.age_confirmed_at,'termsAcceptedAt',p.terms_accepted_at,
     'privacyAcknowledgedAt',p.privacy_notice_ack_at,'termsVersion',p.terms_version,'privacyVersion',p.privacy_notice_version,
     'phoneVerifiedAt',p.phone_verified_at,'googleName',a.raw_user_meta_data->>'full_name','googleAvatar',a.raw_user_meta_data->>'avatar_url',
     'accountLifecycle',lifecycle)) into rows from public.profiles p join auth.users a on a.id=p.id where p.id=u and p_after is null;
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

