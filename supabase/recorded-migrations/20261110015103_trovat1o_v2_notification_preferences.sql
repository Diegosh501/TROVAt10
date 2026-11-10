-- TROVAT1O notifications scaffold.
-- Apply after schema.sql on a fresh staging project. It stores in-app notices,
-- user preferences, push subscriptions and a private delivery queue. It does
-- not send push messages until a trusted dispatcher and secrets are configured.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists public.notification_preferences (
  user_id uuid primary key references public.profiles(id) on delete cascade,
  activity_enabled boolean not null default true,
  reminders_enabled boolean not null default true,
  push_enabled boolean not null default false,
  push_consent_at timestamptz,
  updated_at timestamptz not null default now(),
  check (not push_enabled or push_consent_at is not null)
);

create table if not exists public.push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  endpoint text not null unique check (endpoint like 'https://%' and char_length(endpoint) <= 2048),
  p256dh text not null check (char_length(p256dh) between 40 and 200),
  auth text not null check (char_length(auth) between 16 and 100),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists push_subscriptions_user_idx on public.push_subscriptions(user_id);

create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  event_id uuid references public.events(id) on delete cascade,
  type text not null check (type in (
    'join_request','participant_joined','join_approved','join_declined',
    'participant_removed','participant_left','event_updated','event_cancelled','reminder_24h','reminder_2h'
  )),
  title text not null check (char_length(title) between 1 and 100),
  body text not null check (char_length(body) between 1 and 500),
  dedupe_key text not null check (char_length(dedupe_key) between 1 and 200),
  created_at timestamptz not null default now(),
  read_at timestamptz,
  unique(user_id,dedupe_key)
);
create index if not exists app_notifications_user_feed_idx on public.app_notifications(user_id,created_at desc);

create table if not exists public.notification_delivery_queue (
  id uuid primary key default gen_random_uuid(),
  notification_id uuid not null references public.app_notifications(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  subscription_id uuid not null references public.push_subscriptions(id) on delete cascade,
  status text not null default 'queued' check (status in ('queued','sending','sent','failed')),
  attempts smallint not null default 0 check (attempts between 0 and 10),
  next_attempt_at timestamptz not null default now(),
  last_error text check (char_length(last_error) <= 500),
  sent_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(notification_id,subscription_id)
);
create index if not exists notification_delivery_due_idx on public.notification_delivery_queue(status,next_attempt_at,created_at);

alter table public.notification_preferences enable row level security;
alter table public.push_subscriptions enable row level security;
alter table public.app_notifications enable row level security;
alter table public.notification_delivery_queue enable row level security;

drop policy if exists notification_preferences_owner on public.notification_preferences;
create policy notification_preferences_owner on public.notification_preferences for all to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
drop policy if exists push_subscriptions_owner on public.push_subscriptions;
create policy push_subscriptions_owner on public.push_subscriptions for all to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
drop policy if exists app_notifications_read_owner on public.app_notifications;
create policy app_notifications_read_owner on public.app_notifications for select to authenticated
  using (user_id=(select auth.uid()));
drop policy if exists app_notifications_mark_read_owner on public.app_notifications;
create policy app_notifications_mark_read_owner on public.app_notifications for update to authenticated
  using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
-- Delivery queue intentionally has no client policy or grant.

revoke all on public.notification_delivery_queue from anon, authenticated;
revoke all on public.app_notifications from anon, authenticated;
revoke all on public.notification_preferences from anon, authenticated;
revoke all on public.push_subscriptions from anon, authenticated;
grant select,insert,update on public.notification_preferences to authenticated;
grant select,insert,update,delete on public.push_subscriptions to authenticated;
grant select on public.app_notifications to authenticated;
grant update(read_at) on public.app_notifications to authenticated;
grant all on public.notification_delivery_queue to service_role;
grant all on public.app_notifications to service_role;
grant all on public.notification_preferences to service_role;
grant all on public.push_subscriptions to service_role;

create or replace function private.enqueue_user_notification(
  p_user_id uuid, p_event_id uuid, p_type text, p_title text, p_body text, p_dedupe_key text
) returns void language plpgsql security definer set search_path = '' as $$
declare v_enabled boolean;
begin
  if p_type in ('reminder_24h','reminder_2h') then
    select coalesce(np.reminders_enabled,true) into v_enabled
      from public.notification_preferences np where np.user_id=p_user_id;
    if not found then v_enabled:=true; end if;
  else
    select coalesce(np.activity_enabled,true) into v_enabled
      from public.notification_preferences np where np.user_id=p_user_id;
    if not found then v_enabled:=true; end if;
  end if;
  if not coalesce(v_enabled,false) then return; end if;
  insert into public.app_notifications(user_id,event_id,type,title,body,dedupe_key)
  values(p_user_id,p_event_id,p_type,p_title,p_body,p_dedupe_key)
  on conflict(user_id,dedupe_key) do nothing;
end $$;
revoke all on function private.enqueue_user_notification(uuid,uuid,text,text,text,text) from public, anon, authenticated;

create or replace function private.touch_event_member_updated_at()
returns trigger language plpgsql set search_path = '' as $$
begin
  new.updated_at:=pg_catalog.now();
  return new;
end $$;
revoke all on function private.touch_event_member_updated_at() from public, anon, authenticated;
drop trigger if exists event_members_touch_updated_at on public.event_members;
create trigger event_members_touch_updated_at before update on public.event_members
for each row execute function private.touch_event_member_updated_at();

create or replace function private.queue_notification_delivery()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  insert into public.notification_delivery_queue(notification_id,user_id,subscription_id)
  select new.id,new.user_id,ps.id
  from public.notification_preferences np
  join public.push_subscriptions ps on ps.user_id=np.user_id
  where np.user_id=new.user_id and np.push_enabled and np.push_consent_at is not null
  on conflict(notification_id,subscription_id) do nothing;
  return new;
end $$;
revoke all on function private.queue_notification_delivery() from public, anon, authenticated;
drop trigger if exists app_notifications_queue_push on public.app_notifications;
create trigger app_notifications_queue_push after insert on public.app_notifications
for each row execute function private.queue_notification_delivery();

create or replace function private.notify_event_member_change()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_creator uuid; v_type text; v_title text; v_body text; v_key text;
begin
  select e.creator_id into v_creator from public.events e where e.id=new.event_id;
  if v_creator is null then return new; end if;
  if tg_op='INSERT' then
    if new.state not in ('pending','approved') or new.user_id=v_creator then return new; end if;
    if new.state='approved' then
      v_type:='participant_joined'; v_title:='Nuovo partecipante'; v_body:='Un giocatore è nella lista della partita.';
    else
      v_type:='join_request'; v_title:='Nuova richiesta'; v_body:='Un giocatore chiede di partecipare.';
    end if;
    v_key:=new.event_id::text||':'||new.user_id::text||':'||v_type;
    perform private.enqueue_user_notification(v_creator,new.event_id,v_type,v_title,v_body,v_key);
    return new;
  end if;
  if new.state is not distinct from old.state then return new; end if;
  if new.state='pending' and old.state in ('declined','removed') then
    v_type:='join_request'; v_title:='Nuova richiesta'; v_body:='Un giocatore chiede nuovamente di partecipare.';
    v_key:=new.event_id::text||':'||new.user_id::text||':'||v_type||':'||new.updated_at::text;
    perform private.enqueue_user_notification(v_creator,new.event_id,v_type,v_title,v_body,v_key);
    return new;
  elsif new.state='approved' and old.state='pending' then
    v_type:='join_approved'; v_title:='Richiesta accettata'; v_body:='L’organizzatore ti ha ammesso alla partita.';
  elsif new.state='declined' and old.state='pending' then
    v_type:='join_declined'; v_title:='Richiesta aggiornata'; v_body:='L’organizzatore non ha accettato la richiesta.';
  elsif new.state='removed' and old.state='approved' then
    if auth.uid()=new.user_id then
      v_type:='participant_left'; v_title:='Giocatore uscito'; v_body:='Un partecipante ha lasciato la partita.';
      v_key:=new.event_id::text||':'||new.user_id::text||':'||v_type||':'||new.updated_at::text;
      perform private.enqueue_user_notification(v_creator,new.event_id,v_type,v_title,v_body,v_key);
      return new;
    else
      v_type:='participant_removed'; v_title:='Partecipazione aggiornata'; v_body:='L’organizzatore ti ha rimosso dalla lista.';
    end if;
  else return new;
  end if;
  v_key:=new.event_id::text||':'||new.user_id::text||':'||v_type||':'||new.updated_at::text;
  perform private.enqueue_user_notification(new.user_id,new.event_id,v_type,v_title,v_body,v_key);
  return new;
end $$;
revoke all on function private.notify_event_member_change() from public, anon, authenticated;
drop trigger if exists event_members_notify on public.event_members;
create trigger event_members_notify after insert or update of state on public.event_members
for each row execute function private.notify_event_member_change();

create or replace function private.notify_event_update()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_rec record; v_type text; v_title text; v_body text;
begin
  if old.status is not distinct from new.status
     and old.starts_at is not distinct from new.starts_at
     and old.venue is not distinct from new.venue
     and old.city is not distinct from new.city then return new; end if;
  if new.status='cancelled' and old.status is distinct from 'cancelled' then
    v_type:='event_cancelled'; v_title:='Partita annullata'; v_body:='L’organizzatore ha annullato la partita.';
  else
    v_type:='event_updated'; v_title:='Partita aggiornata'; v_body:='L’organizzatore ha aggiornato data, orario o luogo.';
  end if;
  for v_rec in
    select distinct m.user_id from public.event_members m where m.event_id=new.id and m.state='approved'
    union select new.creator_id
  loop
    if v_rec.user_id is distinct from new.creator_id then
      perform private.enqueue_user_notification(v_rec.user_id,new.id,v_type,v_title,v_body,new.id::text||':'||v_type||':'||new.updated_at::text);
    end if;
  end loop;
  return new;
end $$;
revoke all on function private.notify_event_update() from public, anon, authenticated;
drop trigger if exists events_notify_update on public.events;
create trigger events_notify_update after update of status,starts_at,venue,city on public.events
for each row execute function private.notify_event_update();

create or replace function public.queue_event_reminders()
returns integer language plpgsql security definer set search_path = '' as $$
declare v_count integer;
begin
  with windows as (
    select e.id event_id,e.creator_id user_id,'reminder_24h'::text notice_type
    from public.events e
    where e.status='scheduled' and e.starts_at>pg_catalog.now()+interval '23 hours 50 minutes' and e.starts_at<=pg_catalog.now()+interval '24 hours'
    union
    select e.id,m.user_id,'reminder_24h'::text
    from public.events e join public.event_members m on m.event_id=e.id and m.state='approved'
    where e.status='scheduled' and e.starts_at>pg_catalog.now()+interval '23 hours 50 minutes' and e.starts_at<=pg_catalog.now()+interval '24 hours'
    union
    select e.id,e.creator_id,'reminder_2h'::text
    from public.events e
    where e.status='scheduled' and e.starts_at>pg_catalog.now()+interval '1 hour 50 minutes' and e.starts_at<=pg_catalog.now()+interval '2 hours'
    union
    select e.id,m.user_id,'reminder_2h'::text
    from public.events e join public.event_members m on m.event_id=e.id and m.state='approved'
    where e.status='scheduled' and e.starts_at>pg_catalog.now()+interval '1 hour 50 minutes' and e.starts_at<=pg_catalog.now()+interval '2 hours'
  )
  insert into public.app_notifications(user_id,event_id,type,title,body,dedupe_key)
  select w.user_id,w.event_id,w.notice_type,
    case when w.notice_type='reminder_24h' then 'Partita domani' else 'Partita tra poco' end,
    case when w.notice_type='reminder_24h' then 'Promemoria: la partita inizia tra circa 24 ore.' else 'Promemoria: la partita inizia tra circa 2 ore.' end,
    w.event_id::text||':'||w.notice_type
  from windows w
  where coalesce((select np.reminders_enabled from public.notification_preferences np where np.user_id=w.user_id),true)
  on conflict(user_id,dedupe_key) do nothing;
  get diagnostics v_count = row_count;
  return v_count;
end $$;
revoke all on function public.queue_event_reminders() from public, anon, authenticated;

create or replace function public.claim_notification_deliveries(p_limit integer default 40)
returns table(delivery_id uuid,user_id uuid,event_id uuid,notice_type text,title text,body text,endpoint text,p256dh text,auth text,subscription_id uuid,attempts smallint)
language plpgsql security definer set search_path = '' as $$
begin
  return query
  with picked as (
    select q.id from public.notification_delivery_queue q
    join public.app_notifications n on n.id=q.notification_id and n.user_id=q.user_id
    join public.notification_preferences np on np.user_id=q.user_id
    where ((q.status='queued' and q.next_attempt_at<=pg_catalog.now())
       or (q.status='sending' and q.updated_at<pg_catalog.now()-interval '15 minutes'))
      -- Recheck the current consent and category preferences at claim time:
      -- users may have opted out after this delivery was originally queued.
      and np.push_enabled and np.push_consent_at is not null
      and case when n.type in ('reminder_24h','reminder_2h')
        then np.reminders_enabled else np.activity_enabled end
    order by q.next_attempt_at,q.created_at
    for update of q skip locked
    limit least(greatest(coalesce(p_limit,40),1),100)
  ), claimed as (
    update public.notification_delivery_queue q
    set status='sending',attempts=least(q.attempts+1,10),updated_at=pg_catalog.now()
    from picked p where q.id=p.id
    returning q.id,q.notification_id,q.user_id,q.subscription_id,q.attempts
  )
  select c.id,c.user_id,n.event_id,n.type,n.title,n.body,ps.endpoint,ps.p256dh,ps.auth,c.subscription_id,c.attempts
  from claimed c join public.app_notifications n on n.id=c.notification_id
  join public.push_subscriptions ps on ps.id=c.subscription_id;
end $$;
revoke all on function public.claim_notification_deliveries(integer) from public, anon, authenticated;
grant execute on function public.claim_notification_deliveries(integer) to service_role;

create or replace function public.finish_notification_delivery(p_delivery_id uuid,p_success boolean,p_error text default null)
returns void language plpgsql security definer set search_path = '' as $$
begin
  update public.notification_delivery_queue q set
    status=case when p_success then 'sent' when q.attempts>=5 then 'failed' else 'queued' end,
    sent_at=case when p_success then pg_catalog.now() else null end,
    next_attempt_at=case when p_success or q.attempts>=5 then q.next_attempt_at else pg_catalog.now()+pg_catalog.make_interval(mins=>least(60,power(2,least(q.attempts,6))::integer)) end,
    last_error=case when p_success then null else left(coalesce(p_error,'push delivery failed'),500) end,
    updated_at=pg_catalog.now()
  where q.id=p_delivery_id and q.status='sending';
end $$;
revoke all on function public.finish_notification_delivery(uuid,boolean,text) from public, anon, authenticated;
grant execute on function public.finish_notification_delivery(uuid,boolean,text) to service_role;

create or replace function public.remove_push_subscription(p_subscription_id uuid)
returns void language sql security definer set search_path = '' as $$
  delete from public.push_subscriptions where id=p_subscription_id;
$$;
revoke all on function public.remove_push_subscription(uuid) from public, anon, authenticated;
grant execute on function public.remove_push_subscription(uuid) to service_role;

comment on table public.app_notifications is 'Private in-app notices; bodies must not include private location or phone details.';
comment on table public.push_subscriptions is 'Sensitive endpoint and encryption keys; readable only by owner and trusted service role.';
comment on table public.notification_delivery_queue is 'Private retry queue; only service role can claim or update deliveries.';

-- Optional after verifying pg_cron availability: run every five minutes.
-- select cron.schedule('trovatio-event-reminders','*/5 * * * *','select public.queue_event_reminders();');
-- A server-side dispatcher must claim queue rows, send VAPID Web Push and
-- call finish_notification_delivery. Do not expose service-role or VAPID keys.
