-- Incremental candidate, after account-erasure-requests and session-security.
-- Never run on a populated service as a test. Execution starts disabled.
-- Application-owned objects only; no managed Auth schema alteration.
create table private.account_erasure_execution_settings (
  singleton boolean primary key default true check(singleton),
  enabled boolean not null default false,
  policy_version text not null default 'trovat1o-erasure-2026-11-13-v1',
  updated_at timestamptz not null default now()
);
insert into private.account_erasure_execution_settings(singleton) values(true);
create table private.account_erasure_execution_receipts (
  request_id uuid primary key references public.support_requests(id),
  -- Clear the target before successful deletion so the minimal final receipt
  -- survives. Other authorized Auth cleanup cascades unfinished receipts.
  user_id uuid references auth.users(id) on delete cascade,
  confirmed_session_id uuid,
  confirmed_at timestamptz not null,
  state text not null default 'confirmed' check(state in ('confirmed','blocked','completed')),
  blocker text,
  review_actor uuid,
  review_hash bytea check(review_hash is null or octet_length(review_hash)=32),
  review_expires_at timestamptz,
  completed_at timestamptz,
  updated_at timestamptz not null default now(),
  check(state<>'completed' or (completed_at is not null and user_id is null
    and confirmed_session_id is null and review_actor is null and review_hash is null))
);
alter table private.account_erasure_execution_settings enable row level security;
alter table private.account_erasure_execution_receipts enable row level security;
revoke all on private.account_erasure_execution_settings,private.account_erasure_execution_receipts from public,anon,authenticated;

alter table private.admin_audit drop constraint admin_audit_action_check;
alter table private.admin_audit add constraint admin_audit_action_check check(action in (
  'dashboard_read','tickets_read','ticket_updated','admin_enabled','admin_disabled','audit_read',
  'users_read','events_read','reports_read','user_role_updated','report_reviewed','event_cancelled',
  'erasure_reviewed','erasure_executed'));

create function public.set_account_erasure_execution_enabled(p_enabled boolean,p_policy_version text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  if p_enabled is null or p_policy_version is distinct from 'trovat1o-erasure-2026-11-13-v1' then
    raise exception 'invalid_erasure_configuration' using errcode='22023';end if;
  update private.account_erasure_execution_settings set enabled=p_enabled,updated_at=clock_timestamp();
  return true;
end $$;
revoke all on function public.set_account_erasure_execution_enabled(boolean,text) from public,anon,authenticated;
grant execute on function public.set_account_erasure_execution_enabled(boolean,text) to service_role;

create function private.lock_erasure_admin(p_action text,p_target uuid)
returns uuid language plpgsql security definer set search_path='' as $$
declare actor uuid; mfa_at numeric; claims jsonb;
begin
  actor:=private.require_platform_admin(p_action,p_target);claims:=auth.jwt();
  -- Serialize authority revocation with this irreversible transaction. Recheck
  -- after waiting for the locks, including the real clock rather than now().
  perform 1 from auth.users where id=actor for share;
  perform 1 from auth.sessions where id::text=claims->>'session_id' and user_id=actor for share;
  perform 1 from auth.mfa_factors f where f.user_id=actor and exists(
    select 1 from auth.sessions s where s.id::text=claims->>'session_id' and s.factor_id=f.id) for share;
  perform 1 from private.platform_admins where user_id=actor for share;
  if private.platform_admin_denial() is not null then raise exception 'admin_authority_changed' using errcode='PT403';end if;
  select max((m->>'timestamp')::numeric) into mfa_at from jsonb_array_elements(claims->'amr') m
    where m->>'method'='totp' and m->>'timestamp' ~ '^[0-9]{1,12}(\.[0-9]{1,6})?$';
  if mfa_at is null or mfa_at<extract(epoch from clock_timestamp())-900
      or mfa_at>extract(epoch from clock_timestamp())+30 then raise exception 'mfa_required' using errcode='PT403';end if;
  return actor;
end $$;
revoke all on function private.lock_erasure_admin(text,uuid) from public,anon,authenticated;

create function public.confirm_my_account_erasure(p_request_id uuid,p_confirm boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid; sid uuid; r public.support_requests%rowtype; at_time timestamptz:=clock_timestamp();
begin
  u:=private.require_lifecycle_caller();
  if p_request_id is null or p_confirm is distinct from true then
    raise exception 'confirmation_required' using errcode='22023';end if;
  sid:=(auth.jwt()->>'session_id')::uuid;
  -- A refreshed JWT is not recent reauthentication. Require the actual Auth
  -- session to have been established within the last fifteen minutes.
  if not exists(select 1 from auth.sessions s where s.id=sid and s.user_id=u
      and s.created_at between at_time-interval '15 minutes' and at_time+interval '30 seconds') then
    raise exception 'reauthentication_required' using errcode='PT401';end if;
  perform 1 from auth.users where id=u for update;
  perform 1 from public.profiles where id=u for update;
  if not found or not public.has_live_session() then raise exception 'authentication_required' using errcode='PT401';end if;
  perform 1 from auth.sessions where id=sid and user_id=u for share;
  if not found then raise exception 'authentication_required' using errcode='PT401';end if;
  select * into r from public.support_requests where id=p_request_id for update;
  if not found or r.request_kind<>'account_erasure' or r.requester_user_id is distinct from u
      or r.status in ('resolved','closed') then raise exception 'erasure_request_not_found' using errcode='PT404';end if;
  if exists(select 1 from private.platform_admins where user_id=u) then
    raise exception 'administration_succession_required' using errcode='PT403';end if;
  insert into private.account_erasure_execution_receipts(request_id,user_id,confirmed_session_id,confirmed_at)
    values(p_request_id,u,sid,at_time)
  on conflict(request_id) do update set user_id=excluded.user_id,confirmed_session_id=excluded.confirmed_session_id,
    confirmed_at=excluded.confirmed_at,state='confirmed',blocker=null,review_actor=null,review_hash=null,
    review_expires_at=null,updated_at=excluded.confirmed_at
    where account_erasure_execution_receipts.state<>'completed';
  return jsonb_build_object('requestId',p_request_id,'confirmedAt',at_time,'accountErased',false,'accessClosed',false);
end $$;
revoke all on function public.confirm_my_account_erasure(uuid,boolean) from public,anon;
grant execute on function public.confirm_my_account_erasure(uuid,boolean) to authenticated;

-- Extend the explicit cascade allowlist for the one new Auth FK.
create or replace function private.account_deletion_dependencies_known()
returns boolean language sql stable security definer set search_path='' as $$
  with recursive targets(id) as (
    select 'auth.users'::regclass::oid union
    select c.conrelid from pg_catalog.pg_constraint c join targets t on c.confrelid=t.id
      where c.contype='f' and c.confdeltype='c'
  ), expected(parent,child,cols,action) as (values
    ('auth.users','public.profiles','id','c'),
    ('auth.users','private.account_erasure_execution_receipts','user_id','c'),
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

create function private.requested_account_erasure_hold(p_user uuid,p_request uuid)
returns text language plpgsql stable security definer set search_path='' as $$
declare has_objects boolean;
begin
  if exists(select 1 from private.platform_admins where user_id=p_user) then return 'administration';end if;
  if private.active_history_premium(p_user) then return 'premium';end if;
  if not exists(select 1 from public.subscriptions where user_id=p_user) then return 'unknown_plan';end if;
  if exists(select 1 from private.billing_accounts where user_id=p_user) then return 'billing';end if;
  if exists(select 1 from private.account_retention_holds where user_id=p_user and hold_until>now()) then return 'preservation';end if;
  if exists(select 1 from public.player_reports where reporter_id=p_user or subject_id=p_user) then return 'safety_report';end if;
  if exists(select 1 from public.events where creator_id=p_user) then return 'owned_match';end if;
  if exists(select 1 from public.event_members m join public.events e on e.id=m.event_id
      where m.user_id=p_user and m.state in ('pending','approved') and e.status in ('scheduled','in_progress')) then return 'active_participation';end if;
  if exists(select 1 from public.pin_suggestions where user_id=p_user) then return 'location_contribution';end if;
  -- Other tickets can contain voluntary personal/safety material. Even a
  -- closed ticket needs explicit minimisation review before automatic erasure.
  if exists(select 1 from public.support_requests where requester_user_id=p_user and id<>p_request) then return 'support_history_review';end if;
  if exists(select 1 from public.support_request_audit where actor_id=p_user) then return 'support_audit';end if;
  if pg_catalog.to_regclass('storage.objects') is not null then
    if exists(select 1 from information_schema.columns where table_schema='storage' and table_name='objects' and column_name='owner_id') then
      execute 'select exists(select 1 from storage.objects where owner_id::text=$1)' into has_objects using p_user::text;
    elsif exists(select 1 from information_schema.columns where table_schema='storage' and table_name='objects' and column_name='owner') then
      execute 'select exists(select 1 from storage.objects where owner::text=$1)' into has_objects using p_user::text;
    else return 'unknown_storage_ownership';end if;
    if has_objects then return 'storage';end if;
  end if;
  if not private.account_deletion_dependencies_known() then return 'unknown_dependencies';end if;
  return null;
end $$;
revoke all on function private.requested_account_erasure_hold(uuid,uuid) from public,anon,authenticated;

-- Locks follow Auth -> profile -> subscription -> request -> receipt, matching
-- intake and financial/retention guards. Re-read after any lock wait.
create function private.lock_account_erasure_request(p_request uuid)
returns public.support_requests language plpgsql security definer set search_path='' as $$
declare u uuid; r public.support_requests%rowtype;
begin
  if p_request is null then raise exception 'invalid_request' using errcode='22023';end if;
  select requester_user_id into u from public.support_requests where id=p_request;
  if u is not null then
    perform 1 from auth.users where id=u for update;
    perform 1 from public.profiles where id=u for update;
    perform 1 from public.subscriptions where user_id=u for update;
  end if;
  select * into r from public.support_requests where id=p_request for update;
  if not found or r.request_kind<>'account_erasure' then raise exception 'erasure_request_not_found' using errcode='PT404';end if;
  perform 1 from private.account_erasure_execution_receipts where request_id=p_request for update;
  return r;
end $$;
revoke all on function private.lock_account_erasure_request(uuid) from public,anon,authenticated;

create function private.erasure_confirmation_current(p_request uuid,p_user uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select exists(select 1 from private.account_erasure_execution_receipts c
    join auth.sessions s on s.id=c.confirmed_session_id and s.user_id=c.user_id
    join auth.users u on u.id=c.user_id and u.email_confirmed_at is not null and u.deleted_at is null
    where c.request_id=p_request and c.user_id=p_user and c.state<>'completed'
      and c.confirmed_at between clock_timestamp()-interval '15 minutes' and clock_timestamp()+interval '30 seconds'
      and (s.not_after is null or s.not_after>clock_timestamp())
      and not coalesce(u.is_anonymous,false) and (u.banned_until is null or u.banned_until<=clock_timestamp()))
$$;
revoke all on function private.erasure_confirmation_current(uuid,uuid) from public,anon,authenticated;

create function public.admin_preview_account_erasure(p_request_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid; r public.support_requests%rowtype; block_reason text; token text; expires timestamptz;
begin
  actor:=private.lock_erasure_admin('erasure_reviewed',p_request_id);
  r:=private.lock_account_erasure_request(p_request_id);
  if exists(select 1 from private.account_erasure_execution_receipts where request_id=r.id and state='completed') then
    return jsonb_build_object('requestId',r.id,'status','completed','accountErased',true,'accessClosed',true);end if;
  if not (select enabled from private.account_erasure_execution_settings) then block_reason:='execution_disabled';
  elsif r.status in ('resolved','closed') or r.requester_user_id is null then block_reason:='request_closed';
  elsif not private.erasure_confirmation_current(r.id,r.requester_user_id) then block_reason:='reauthentication_required';
  else block_reason:=private.requested_account_erasure_hold(r.requester_user_id,r.id);end if;
  if block_reason is not null then
    update private.account_erasure_execution_receipts set state='blocked',blocker=block_reason,
      review_actor=null,review_hash=null,review_expires_at=null,updated_at=clock_timestamp() where request_id=r.id;
    return jsonb_build_object('requestId',r.id,'status','blocked','reason',block_reason,'accountErased',false,'accessClosed',false);
  end if;
  token:=encode(extensions.gen_random_bytes(32),'hex');expires:=clock_timestamp()+interval '5 minutes';
  update private.account_erasure_execution_receipts set state='confirmed',blocker=null,review_actor=actor,
    review_hash=extensions.digest(convert_to(token,'UTF8'),'sha256'),review_expires_at=expires,updated_at=clock_timestamp() where request_id=r.id;
  return jsonb_build_object('requestId',r.id,'status','ready','reviewToken',token,'reviewExpiresAt',expires,
    'accountErased',false,'accessClosed',false);
end $$;
revoke all on function public.admin_preview_account_erasure(uuid) from public,anon;
grant execute on function public.admin_preview_account_erasure(uuid) to authenticated;

create function public.admin_execute_account_erasure(p_request_id uuid,p_review_token text,p_confirmation text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor uuid; r public.support_requests%rowtype; c private.account_erasure_execution_receipts%rowtype;
  block_reason text; target uuid; done_at timestamptz;
begin
  actor:=private.lock_erasure_admin('erasure_executed',p_request_id);
  if p_confirmation is distinct from 'CANCELLA ACCOUNT' or p_review_token is null or p_review_token !~ '^[a-f0-9]{64}$' then
    raise exception 'confirmation_required' using errcode='22023';end if;
  r:=private.lock_account_erasure_request(p_request_id);
  select * into c from private.account_erasure_execution_receipts where request_id=r.id;
  if c.state='completed' then return jsonb_build_object('requestId',r.id,'status','completed',
    'completedAt',c.completed_at,'accountErased',true,'accessClosed',true,'reused',true);end if;
  if not (select enabled from private.account_erasure_execution_settings) then raise exception 'erasure_execution_disabled' using errcode='55000';end if;
  if c.review_actor is distinct from actor or c.review_hash is distinct from extensions.digest(convert_to(p_review_token,'UTF8'),'sha256')
      or c.review_expires_at is null or c.review_expires_at<=clock_timestamp() then
    raise exception 'erasure_review_required' using errcode='PT403';end if;
  target:=r.requester_user_id;
  if r.status in ('resolved','closed') or target is null then block_reason:='request_closed';
  elsif not private.erasure_confirmation_current(r.id,target) then block_reason:='reauthentication_required';
  else block_reason:=private.requested_account_erasure_hold(target,r.id);end if;
  if block_reason is not null then
    update private.account_erasure_execution_receipts set state='blocked',blocker=block_reason,
      review_actor=null,review_hash=null,review_expires_at=null,updated_at=clock_timestamp() where request_id=r.id;
    return jsonb_build_object('requestId',r.id,'status','blocked','reason',block_reason,'accountErased',false,'accessClosed',false);
  end if;
  begin
    delete from auth.sessions where user_id=target;
    done_at:=clock_timestamp();
    update private.account_erasure_execution_receipts set state='completed',user_id=null,confirmed_session_id=null,
      review_actor=null,review_hash=null,review_expires_at=null,blocker=null,completed_at=done_at,updated_at=done_at where request_id=r.id;
    update public.support_requests set status='resolved',contact_name=null,contact_email=null,contact_allowed=false,
      subject='Cancellazione account completata',details='Account e sessioni applicative eliminati dopo verifica autorizzata.',
      admin_reply='Cancellazione dell’account applicativo completata.',updated_at=done_at where id=r.id;
    delete from auth.users where id=target;
    if not found then raise exception 'erasure_target_missing' using errcode='PT404';end if;
    if exists(select 1 from public.profiles where id=target) or exists(select 1 from auth.sessions where user_id=target)
        or exists(select 1 from auth.identities where user_id=target) then raise exception 'erasure_incomplete';end if;
  exception when foreign_key_violation or deadlock_detected or lock_not_available then
    -- Subtransaction restores the sessions, receipt and ticket on failure.
    update private.account_erasure_execution_receipts set state='blocked',blocker='dependencies_changed',
      review_actor=null,review_hash=null,review_expires_at=null,updated_at=clock_timestamp() where request_id=r.id;
    return jsonb_build_object('requestId',r.id,'status','blocked','reason','dependencies_changed','accountErased',false,'accessClosed',false);
  end;
  return jsonb_build_object('requestId',r.id,'status','completed','completedAt',done_at,'accountErased',true,'accessClosed',true,'reused',false);
end $$;
revoke all on function public.admin_execute_account_erasure(uuid,text,text) from public,anon;
grant execute on function public.admin_execute_account_erasure(uuid,text,text) to authenticated;
