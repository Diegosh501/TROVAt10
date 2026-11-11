-- Apply after oauth-profiles.sql and free-access.sql. Payment data stays private.
-- Test-mode purchases NEVER update production entitlements in subscriptions.
create table private.billing_accounts (
  user_id uuid not null references public.profiles(id) on delete cascade,
  mode text not null check (mode in ('test','live')),
  customer_id text check (customer_id ~ '^cus_[A-Za-z0-9]+$'),
  checkout_id text,
  checkout_expires_at timestamptz,
  checkout_lease uuid,
  checkout_lease_until timestamptz,
  sync_lease uuid,
  sync_lease_until timestamptz,
  primary key (user_id,mode), unique (mode,customer_id)
);
create table private.billing_states (
  mode text not null,
  subscription_id text not null check (subscription_id ~ '^sub_[A-Za-z0-9]+$'),
  user_id uuid not null,
  customer_id text not null,
  price_id text not null check (price_id ~ '^price_[A-Za-z0-9]+$'),
  status text not null check (status in ('incomplete','incomplete_expired','trialing','active','past_due','canceled','unpaid','paused')),
  cancel_at_period_end boolean not null default false,
  paid_until timestamptz,
  updated_at timestamptz not null default now(),
  primary key (mode,subscription_id),
  foreign key (user_id,mode) references private.billing_accounts(user_id,mode) on delete cascade
);
create index billing_states_user_idx on private.billing_states(user_id,mode);
create table private.billing_invoices (
  mode text not null,
  invoice_id text not null check (invoice_id ~ '^in_[A-Za-z0-9]+$'),
  subscription_id text not null,
  paid_until timestamptz not null,
  revoked boolean not null default false,
  primary key (mode,invoice_id),
  foreign key (mode,subscription_id) references private.billing_states(mode,subscription_id) on delete cascade
);
create index billing_invoices_subscription_idx on private.billing_invoices(mode,subscription_id);
create table private.billing_holds (
  mode text not null,
  subscription_id text not null,
  reason text not null check (reason in ('dispute','fraud')),
  object_id text not null,
  active boolean not null default true,
  primary key (mode,subscription_id,reason,object_id),
  foreign key (mode,subscription_id) references private.billing_states(mode,subscription_id) on delete cascade
);
create table private.billing_events (
  mode text not null check (mode in ('test','live')),
  event_id text not null check (event_id ~ '^evt_[A-Za-z0-9]+$'),
  event_type text not null check (length(event_type)<=100),
  stripe_created_at timestamptz not null,
  received_at timestamptz not null default now(),
  lease uuid,
  lease_until timestamptz,
  done_at timestamptz,
  primary key (mode,event_id)
);
create table private.billing_quotas (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  window_at timestamptz not null,
  attempts integer not null
);
alter table private.billing_accounts enable row level security;
alter table private.billing_states enable row level security;
alter table private.billing_invoices enable row level security;
alter table private.billing_holds enable row level security;
alter table private.billing_events enable row level security;
alter table private.billing_quotas enable row level security;
revoke all on private.billing_accounts,private.billing_states,private.billing_invoices,
  private.billing_holds,private.billing_events,private.billing_quotas from public,anon,authenticated;

-- The caller token, its live session, identity and profile are checked before any
-- Stripe API call. A JWT that survives logout is insufficient for a purchase.
create or replace function public.billing_authorize()
returns uuid language plpgsql security definer set search_path='' as $$
declare v_user uuid:=auth.uid(); v_session uuid; v_count integer;
begin
  if v_user is null or not public.is_google_verified() or not exists(
    select 1 from public.profiles p where p.id=v_user and p.age_confirmed_at is not null
  ) then raise exception 'billing_auth_required' using errcode='PT401'; end if;
  begin v_session:=(auth.jwt()->>'session_id')::uuid;
  exception when invalid_text_representation then v_session:=null; end;
  if v_session is null or not exists(select 1 from auth.sessions s
    where s.id=v_session and s.user_id=v_user and (s.not_after is null or s.not_after>now()))
  then raise exception 'session_revoked' using errcode='PT401'; end if;
  insert into private.billing_quotas(user_id,window_at,attempts) values(v_user,now(),1)
    on conflict(user_id) do update set
      attempts=case when billing_quotas.window_at<now()-interval '1 minute' then 1 else billing_quotas.attempts+1 end,
      window_at=case when billing_quotas.window_at<now()-interval '1 minute' then now() else billing_quotas.window_at end
    returning attempts into v_count;
  if v_count>12 then raise exception 'billing_rate_limited' using errcode='PT429'; end if;
  return v_user;
end $$;
revoke all on function public.billing_authorize() from public,anon;
grant execute on function public.billing_authorize() to authenticated;

-- Narrow service-only transport. No SQL text, arbitrary table names, PII,
-- request-supplied prices or application-admin operations are accepted here.
create or replace function public.billing_service(p_action text,p jsonb)
returns jsonb language plpgsql security definer set search_path='' as $$
declare
  m text:=p->>'mode'; u uuid; a private.billing_accounts%rowtype;
  ev private.billing_events%rowtype; tok uuid; s jsonb; inv jsonb; risk jsonb;
  sid text; until_at timestamptz; winner private.billing_states%rowtype;
begin
  if m is null or m not in ('test','live') then raise exception 'invalid_mode' using errcode='22023'; end if;
  if p_action in ('claim-event','finish-event') then
    if coalesce(p->>'event_id','')!~'^evt_[A-Za-z0-9]+$' then raise exception 'invalid_event' using errcode='22023'; end if;
    if p_action='claim-event' then
      insert into private.billing_events(mode,event_id,event_type,stripe_created_at)
        values(m,p->>'event_id',p->>'type',to_timestamp((p->>'created')::double precision))
        on conflict do nothing;
      select * into ev from private.billing_events where mode=m and event_id=p->>'event_id' for update;
      if ev.done_at is not null then return jsonb_build_object('done',true); end if;
      if ev.lease_until>now() then raise exception 'billing_busy' using errcode='PT409'; end if;
      tok:=gen_random_uuid();
      update private.billing_events set lease=tok,lease_until=now()+interval '2 minutes' where mode=m and event_id=ev.event_id;
      return jsonb_build_object('token',tok,'done',false);
    end if;
    update private.billing_events set done_at=case when (p->>'success')::boolean then now() else null end,
      lease=null,lease_until=null where mode=m and event_id=p->>'event_id' and lease=(p->>'token')::uuid;
    return jsonb_build_object('ok',found);
  end if;
  if p_action in ('sync-lock','sync-release','apply') then
    select * into a from private.billing_accounts where mode=m and customer_id=p->>'customer_id' for update;
    if not found then return null; end if;
    if p_action='sync-lock' then
      if a.sync_lease_until>now() then raise exception 'billing_busy' using errcode='PT409'; end if;
      tok:=gen_random_uuid();
      update private.billing_accounts set sync_lease=tok,sync_lease_until=now()+interval '2 minutes' where user_id=a.user_id and mode=m;
      return jsonb_build_object('token',tok,'user_id',a.user_id);
    end if;
    if a.sync_lease is null or a.sync_lease_until is null or a.sync_lease is distinct from (p->>'token')::uuid or a.sync_lease_until<=now() then
      raise exception 'lease_expired' using errcode='PT409'; end if;
    if p_action='sync-release' then
      update private.billing_accounts set sync_lease=null,sync_lease_until=null where user_id=a.user_id and mode=m;
      return jsonb_build_object('ok',true);
    end if;
    s:=p->'subscription'; sid:=s->>'id';
    if sid is null or sid!~'^sub_[A-Za-z0-9]+$' or s->>'customer_id' is distinct from a.customer_id then
      raise exception 'invalid_subscription' using errcode='22023'; end if;
    if exists(select 1 from private.billing_states where mode=m and subscription_id=sid and user_id<>a.user_id) then
      raise exception 'ownership_conflict' using errcode='PT403'; end if;
    insert into private.billing_states(mode,subscription_id,user_id,customer_id,price_id,status,cancel_at_period_end)
      values(m,sid,a.user_id,a.customer_id,s->>'price_id',s->>'status',coalesce((s->>'cancel_at_period_end')::boolean,false))
      on conflict(mode,subscription_id) do update set status=excluded.status,price_id=excluded.price_id,
        cancel_at_period_end=excluded.cancel_at_period_end,updated_at=now();
    for inv in select value from jsonb_array_elements(coalesce(p->'invoices','[]'::jsonb)) loop
      until_at:=to_timestamp((inv->>'paid_until')::double precision);
      if until_at is null or until_at>now()+interval '400 days' then raise exception 'invalid_paid_period' using errcode='22023'; end if;
      if exists(select 1 from private.billing_invoices where mode=m and invoice_id=inv->>'id' and subscription_id<>sid) then
        raise exception 'invoice_ownership_conflict' using errcode='PT403'; end if;
      insert into private.billing_invoices(mode,invoice_id,subscription_id,paid_until)
        values(m,inv->>'id',sid,until_at) on conflict(mode,invoice_id) do update set paid_until=excluded.paid_until;
      -- A replayed invoice.paid cannot undo a recorded refund.
    end loop;
    risk:=p->'risk';
    if risk is not null and risk<>'null'::jsonb then
      if risk->>'reason'='refund' then
        -- Retain a tombstone even if the refund arrives before invoice.paid.
        until_at:=to_timestamp((risk->>'paid_until')::double precision);
        if until_at is null then raise exception 'invalid_refund' using errcode='22023'; end if;
        if exists(select 1 from private.billing_invoices where mode=m and invoice_id=risk->>'invoice_id' and subscription_id<>sid) then
          raise exception 'invoice_ownership_conflict' using errcode='PT403'; end if;
        insert into private.billing_invoices(mode,invoice_id,subscription_id,paid_until,revoked)
          values(m,risk->>'invoice_id',sid,until_at,true)
          on conflict(mode,invoice_id) do update set revoked=true;
      else
        insert into private.billing_holds(mode,subscription_id,reason,object_id,active)
          values(m,sid,risk->>'reason',risk->>'object_id',(risk->>'active')::boolean)
          on conflict(mode,subscription_id,reason,object_id) do update set active=excluded.active;
      end if;
    end if;
    update private.billing_states set paid_until=(select max(i.paid_until) from private.billing_invoices i
      where i.mode=m and i.subscription_id=sid and not i.revoked) where mode=m and subscription_id=sid;
    if m='live' then
      select bs.* into winner from private.billing_states bs where bs.user_id=a.user_id and bs.mode='live'
        and bs.status in ('active','past_due') and bs.paid_until>now() and not exists(
          select 1 from private.billing_holds h where h.mode=bs.mode and h.subscription_id=bs.subscription_id and h.active)
        order by bs.paid_until desc limit 1;
      insert into public.subscriptions(user_id,plan,status,current_period_end,stripe_customer_id,stripe_subscription_id)
        values(a.user_id,case when winner.subscription_id is not null then 'premium' else 'free' end,
          case when winner.subscription_id is not null then 'active' else 'inactive' end,
          winner.paid_until,a.customer_id,winner.subscription_id)
        on conflict(user_id) do update set plan=excluded.plan,status=excluded.status,
          current_period_end=excluded.current_period_end,stripe_customer_id=excluded.stripe_customer_id,
          stripe_subscription_id=excluded.stripe_subscription_id,updated_at=now();
    end if;
    return jsonb_build_object('ok',true);
  end if;
  u:=(p->>'user_id')::uuid;
  if u is null or not exists(select 1 from public.profiles where id=u) then raise exception 'profile_required' using errcode='PT401'; end if;
  if p_action='checkout-lock' then
    insert into private.billing_accounts(user_id,mode) values(u,m) on conflict do nothing;
  end if;
  select * into a from private.billing_accounts where user_id=u and mode=m for update;
  if not found then return null; end if;
  if p_action='account' then return jsonb_build_object('customer_id',a.customer_id,'checkout_id',a.checkout_id,'checkout_expires_at',a.checkout_expires_at); end if;
  if p_action='status' then
    select bs.* into winner from private.billing_states bs where bs.user_id=u and bs.mode=m
      and bs.status in ('active','past_due') and bs.paid_until>now() and not exists(
        select 1 from private.billing_holds h where h.mode=m and h.subscription_id=bs.subscription_id and h.active)
      order by bs.paid_until desc limit 1;
    return jsonb_build_object('plan',case when winner.subscription_id is null then 'free' else 'premium' end,
      'validUntil',winner.paid_until,'cancelAtPeriodEnd',coalesce(winner.cancel_at_period_end,false),'hasCustomer',a.customer_id is not null);
  end if;
  if p_action='checkout-lock' then
    if a.checkout_lease_until>now() then raise exception 'billing_busy' using errcode='PT409'; end if;
    tok:=gen_random_uuid();
    update private.billing_accounts set checkout_lease=tok,checkout_lease_until=now()+interval '2 minutes' where user_id=u and mode=m;
    return jsonb_build_object('token',tok,'customer_id',a.customer_id,'checkout_id',a.checkout_id);
  end if;
  if a.checkout_lease is null or a.checkout_lease_until is null or a.checkout_lease is distinct from (p->>'token')::uuid or a.checkout_lease_until<=now() then raise exception 'lease_expired' using errcode='PT409'; end if;
  if p_action='customer-bind' then
    if a.customer_id is not null and a.customer_id is distinct from p->>'customer_id' then raise exception 'ownership_conflict' using errcode='PT403'; end if;
    update private.billing_accounts set customer_id=p->>'customer_id' where user_id=u and mode=m;
  elsif p_action='checkout-save' then
    if coalesce(p->>'checkout_id','')!~'^cs_[A-Za-z0-9_]+$' then raise exception 'invalid_checkout' using errcode='22023'; end if;
    update private.billing_accounts set checkout_id=p->>'checkout_id',checkout_expires_at=to_timestamp((p->>'expires_at')::double precision) where user_id=u and mode=m;
  elsif p_action='checkout-release' then
    update private.billing_accounts set checkout_lease=null,checkout_lease_until=null where user_id=u and mode=m;
  else raise exception 'invalid_action' using errcode='22023'; end if;
  return jsonb_build_object('ok',true);
end $$;
revoke all on function public.billing_service(text,jsonb) from public,anon,authenticated;
grant execute on function public.billing_service(text,jsonb) to service_role;

-- Null expiry is never a paid entitlement. Both browser and write RPCs use an
-- explicit future expiry; only the verified live webhook can write it.
update public.subscriptions set plan='free',status='inactive'
where plan='premium' and current_period_end is null;
alter table public.subscriptions add constraint premium_requires_expiry
  check (plan<>'premium' or current_period_end is not null);
