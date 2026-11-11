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
