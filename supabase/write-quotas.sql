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
