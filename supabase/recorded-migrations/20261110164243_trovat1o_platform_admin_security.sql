-- Apply after schema.sql. The private allowlist, not editable JWT metadata,
-- is authoritative for platform administration. Never grant it to web clients.
create schema if not exists private;
revoke all on schema private from public,anon,authenticated;

create table if not exists private.platform_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  enabled boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table if not exists private.admin_action_quota (
  user_id uuid primary key references auth.users(id) on delete cascade,
  window_start timestamptz not null,
  request_count integer not null check(request_count between 1 and 60)
);
create table if not exists private.admin_audit (
  id bigint generated always as identity primary key,
  actor_id uuid references auth.users(id) on delete set null,
  action text not null check(action in ('dashboard_read','tickets_read','ticket_updated','admin_enabled','admin_disabled','audit_read')),
  target_id uuid,
  created_at timestamptz not null default now()
);
create index if not exists admin_audit_actor_idx on private.admin_audit(actor_id,created_at desc);
create index if not exists admin_audit_created_idx on private.admin_audit(created_at desc);
alter table private.platform_admins enable row level security;
alter table private.admin_action_quota enable row level security;
alter table private.admin_audit enable row level security;
revoke all on all tables in schema private from public,anon,authenticated;
revoke all on all sequences in schema private from public,anon,authenticated;

create or replace function private.platform_admin_denial()
returns text language plpgsql stable security definer set search_path = '' as $$
declare
  v_user uuid := (select auth.uid());
  v_claims jsonb := (select auth.jwt());
  v_mfa_at numeric;
begin
  if v_user is null or not exists (
    select 1 from auth.users u where u.id=v_user and u.email_confirmed_at is not null
      and not coalesce(u.is_anonymous,false) and u.deleted_at is null
      and (u.banned_until is null or u.banned_until<=pg_catalog.now())
  ) then return 'authentication_required'; end if;
  if not exists(select 1 from private.platform_admins a where a.user_id=v_user and a.enabled) then
    return 'admin_required';
  end if;
  -- A still-unexpired access token must not outlive logout/revocation.
  if not exists(select 1 from auth.sessions s where s.id::text=v_claims->>'session_id'
    and s.user_id=v_user and (s.not_after is null or s.not_after>pg_catalog.now())) then
    return 'session_revoked';
  end if;
  if coalesce(v_claims->>'aal','')<>'aal2' or not exists (
    select 1 from auth.sessions s join auth.mfa_factors f on f.id=s.factor_id and f.user_id=s.user_id
      where s.id::text=v_claims->>'session_id' and s.user_id=v_user and s.aal='aal2'
        and f.status='verified' and f.factor_type='totp'
  ) then return 'mfa_required'; end if;
  select max((m->>'timestamp')::numeric) into v_mfa_at
    from pg_catalog.jsonb_array_elements(case when pg_catalog.jsonb_typeof(v_claims->'amr')='array'
      then v_claims->'amr' else '[]'::jsonb end) m
    where m->>'method'='totp' and m->>'timestamp' ~ '^[0-9]{1,12}(\.[0-9]{1,6})?$';
  if v_mfa_at is null or v_mfa_at<extract(epoch from pg_catalog.now())-900
      or v_mfa_at>extract(epoch from pg_catalog.now())+30 then return 'mfa_required'; end if;
  return null;
end $$;
revoke all on function private.platform_admin_denial() from public,anon,authenticated;

create or replace function private.require_platform_admin(p_action text,p_target uuid default null)
returns uuid language plpgsql security definer set search_path = '' as $$
declare v_user uuid := (select auth.uid()); v_reason text; v_requests integer;
begin
  v_reason:=private.platform_admin_denial();
  if v_reason is not null then
    if v_reason in ('authentication_required','session_revoked') then
      raise exception '%',v_reason using errcode='PT401';
    end if;
    raise exception '%',v_reason using errcode='PT403';
  end if;
  insert into private.admin_action_quota(user_id,window_start,request_count)
    values(v_user,pg_catalog.date_trunc('minute',pg_catalog.now()),1)
    on conflict(user_id) do update set
      window_start=excluded.window_start,
      request_count=case when admin_action_quota.window_start<excluded.window_start then 1
        else admin_action_quota.request_count+1 end
    where admin_action_quota.window_start<excluded.window_start or admin_action_quota.request_count<60
    returning request_count into v_requests;
  if v_requests is null then raise exception 'admin_rate_limited' using errcode='PT429'; end if;
  insert into private.admin_audit(actor_id,action,target_id) values(v_user,p_action,p_target);
  return v_user;
end $$;
revoke all on function private.require_platform_admin(text,uuid) from public,anon,authenticated;

-- Existing report policies call this helper. Removing a platform administrator,
-- signing out or removing the MFA factor now also removes moderation access.
create or replace function public.is_support()
returns boolean language sql stable security definer set search_path = '' as $$
  select private.platform_admin_denial() is null
$$;
revoke all on function public.is_support() from public,anon;
grant execute on function public.is_support() to authenticated;

-- Only the trusted provisioning process can call this RPC. It never accepts a
-- role from signup metadata and never promotes an unconfirmed/anonymous account.
create or replace function public.provision_platform_admin(p_user_id uuid,p_enabled boolean)
returns boolean language plpgsql security definer set search_path = '' as $$
begin
  if p_enabled is null then raise exception 'invalid_request' using errcode='22023'; end if;
  if not exists(select 1 from auth.users u where u.id=p_user_id and (not p_enabled or (
    u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false) and u.deleted_at is null
    and (u.banned_until is null or u.banned_until<=pg_catalog.now())))) then
    raise exception 'confirmed_account_required' using errcode='42501';
  end if;
  insert into private.platform_admins(user_id,enabled) values(p_user_id,p_enabled)
    on conflict(user_id) do update set enabled=excluded.enabled,updated_at=pg_catalog.now();
  insert into private.admin_audit(action,target_id)
    values(case when p_enabled then 'admin_enabled' else 'admin_disabled' end,p_user_id);
  return true;
end $$;
revoke all on function public.provision_platform_admin(uuid,boolean) from public,anon,authenticated;
grant execute on function public.provision_platform_admin(uuid,boolean) to service_role;

create or replace function public.admin_dashboard()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_metrics jsonb;
begin
  perform private.require_platform_admin('dashboard_read');
  select pg_catalog.jsonb_build_object(
    'totalUsers',(select count(*) from public.profiles),
    'hosts',(select count(*) from public.profiles where role='host'),
    'sportivi',(select count(*) from public.profiles where role='sportivo'),
    'verifiedPhones',(select count(*) from public.profiles where phone_verified_at is not null),
    'totalEvents',(select count(*) from public.events),
    'activeEvents',(select count(*) from public.events where status in ('scheduled','in_progress')),
    'pendingJoins',(select count(*) from public.event_members where state='pending'),
    'participations',(select count(*) from public.event_members where state='approved'),
    'completedEvents',(select count(*) from public.events where status='completed'),
    'cancelledEvents',(select count(*) from public.events where status='cancelled'),
    'newTickets',(select count(*) from public.support_requests where status='new'),
    'openTickets',(select count(*) from public.support_requests where status in ('new','in_progress','waiting_user')),
    'openReports',(select count(*) from public.player_reports where state='received'),
    'signups30d',(select count(*) from public.profiles where created_at>=pg_catalog.now()-interval '30 days')
  ) into v_metrics;
  return pg_catalog.jsonb_build_object('updatedAt',pg_catalog.now(),'metrics',v_metrics,
    'usage',pg_catalog.jsonb_build_object('available',false,'observedAt',null,'counts',null));
end $$;
revoke all on function public.admin_dashboard() from public,anon;
grant execute on function public.admin_dashboard() to authenticated;

create or replace function public.admin_support_tickets(p_query text default '',p_status text default '',p_category text default '',p_sort text default 'date')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_rows jsonb; v_total bigint;
begin
  perform private.require_platform_admin('tickets_read');
  if p_query is null or char_length(p_query)>100 or p_status is null
    or p_status not in ('','new','in_progress','waiting_user','resolved','closed') or p_category is null
    or p_category not in ('','bug','account','event','safety','other') or p_sort is null
    or p_sort not in ('date','name') then raise exception 'invalid_request' using errcode='22023'; end if;
  with matches as (
    select id,category,subject,details,contact_name,contact_email,contact_allowed,status,admin_reply,created_at,updated_at
    from public.support_requests
    where (p_status='' or status=p_status) and (p_category='' or category=p_category)
      and (pg_catalog.btrim(p_query)='' or search_document @@ pg_catalog.websearch_to_tsquery('simple',p_query))
  ), page as (
    select *,count(*) over() as full_count from matches
    order by case when p_sort='name' then contact_name end asc nulls last,created_at desc,id
    limit 50
  ) select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(page)-'full_count'),'[]'::jsonb),coalesce(max(full_count),0)
    into v_rows,v_total from page;
  return pg_catalog.jsonb_build_object('tickets',v_rows,'total',v_total);
end $$;
revoke all on function public.admin_support_tickets(text,text,text,text) from public,anon;
grant execute on function public.admin_support_tickets(text,text,text,text) to authenticated;

create or replace function public.admin_update_support_ticket(p_id uuid,p_status text,p_reply text)
returns boolean language plpgsql security definer set search_path = '' as $$
declare v_actor uuid; v_old_status text;
begin
  v_actor:=private.require_platform_admin('ticket_updated',p_id);
  if p_status is null or p_status not in ('new','in_progress','waiting_user','resolved','closed')
    or p_reply is null or char_length(p_reply)>3000 then
    raise exception 'invalid_request' using errcode='22023';
  end if;
  select status into v_old_status from public.support_requests where id=p_id for update;
  if not found then raise exception 'ticket_not_found' using errcode='PT404'; end if;
  update public.support_requests set status=p_status,admin_reply=nullif(pg_catalog.btrim(p_reply),''),updated_at=pg_catalog.now() where id=p_id;
  -- The update and BOTH audit entries are one transaction; an audit failure
  -- rolls the update back rather than silently losing the administrative log.
  insert into public.support_request_audit(ticket_id,actor_id,action,old_status,new_status)
    values(p_id,v_actor,'status_changed',v_old_status,p_status),(p_id,v_actor,'reply_saved',v_old_status,p_status);
  return true;
end $$;
revoke all on function public.admin_update_support_ticket(uuid,text,text) from public,anon;
grant execute on function public.admin_update_support_ticket(uuid,text,text) to authenticated;

create or replace function public.admin_audit_log()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_rows jsonb;
begin
  perform private.require_platform_admin('audit_read');
  select coalesce(pg_catalog.jsonb_agg(pg_catalog.to_jsonb(a)),'[]'::jsonb) into v_rows from (
    select id,actor_id,action,target_id,created_at from private.admin_audit order by id desc limit 50
  ) a;
  return pg_catalog.jsonb_build_object('entries',v_rows);
end $$;
revoke all on function public.admin_audit_log() from public,anon;
grant execute on function public.admin_audit_log() to authenticated;
