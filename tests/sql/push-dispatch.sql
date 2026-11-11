-- Actual PostgreSQL transport/lease tests. Empty local/staging database only.
begin;
do $$ begin if exists(select 1 from auth.users) or exists(select 1 from public.events) then
  raise exception 'push_regression_refused_on_populated_database'; end if; end $$;
create temporary table push_fixture(user_id uuid default gen_random_uuid(),sub_id uuid default gen_random_uuid(),
  notice_id uuid default gen_random_uuid(),event_id uuid default gen_random_uuid(),delivery_id uuid,lease uuid,old_lease uuid) on commit drop;
insert into push_fixture default values;
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select user_id,'push-'||user_id||'@example.invalid',now(),'{"provider":"google","providers":["google"]}','{}' from push_fixture;
insert into public.profiles(id,username,role,age_confirmed_at,terms_accepted_at,privacy_notice_ack_at,terms_version,privacy_notice_version)
select user_id,'qa_push_'||left(replace(user_id::text,'-',''),8),'host',now(),now(),now(),'regression','regression' from push_fixture;
insert into public.notification_preferences(user_id,push_enabled,push_consent_at)
select user_id,true,now()-interval '1 hour' from push_fixture;
insert into public.push_subscriptions(id,user_id,endpoint,p256dh,auth)
select sub_id,user_id,'https://fcm.googleapis.com/fcm/send/synthetic-fixture',repeat('a',87),repeat('b',22) from push_fixture;
insert into public.app_notifications(id,user_id,type,title,body,dedupe_key)
select notice_id,user_id,'event_updated','Synthetic update','Synthetic update for SQL fixture','push-fixture' from push_fixture;
-- 1. Only the new leased API is available to trusted service workers.
do $$ begin
  if has_function_privilege('authenticated','public.claim_push_deliveries(integer)','execute') or
    has_function_privilege('anon','public.check_push_delivery(uuid,uuid)','execute') or
    has_function_privilege('authenticated','public.finish_push_delivery(uuid,uuid,text)','execute') or
    has_function_privilege('service_role','public.finish_notification_delivery(uuid,boolean,text)','execute') then
    raise exception 'push_callback_acl_bypass'; end if;
end $$;
update push_fixture f set delivery_id=c.delivery_id,lease=c.lease_token from public.claim_push_deliveries() c;
-- 2. A live claim cannot be simultaneously claimed again.
do $$ begin
  if (select lease from push_fixture) is null or exists(select 1 from public.claim_push_deliveries()) then raise exception 'duplicate_claim'; end if;
  if public.check_push_delivery((select delivery_id from push_fixture),(select lease from push_fixture)) is null then raise exception 'valid_claim_missing'; end if;
end $$;
-- 3. Forged callbacks and checks cannot affect another leased delivery.
do $$ begin
  if public.check_push_delivery((select delivery_id from push_fixture),gen_random_uuid()) is not null
    or public.finish_push_delivery((select delivery_id from push_fixture),gen_random_uuid(),'sent') then raise exception 'forged_lease_accepted'; end if;
end $$;
-- 4. Reclaim rotates the token and a delayed old worker cannot acknowledge it.
update push_fixture set old_lease=lease;
update public.notification_delivery_queue set lease_until=now()-interval '1 second' where id=(select delivery_id from push_fixture);
update push_fixture f set lease=c.lease_token from public.claim_push_deliveries() c where c.delivery_id=f.delivery_id;
do $$ begin
  if (select lease=old_lease from push_fixture) or public.finish_push_delivery((select delivery_id from push_fixture),(select old_lease from push_fixture),'sent') then
    raise exception 'stale_worker_acknowledged_new_claim'; end if;
end $$;
-- 5. Repeated successful callbacks are idempotent and do not resend/requeue.
select public.finish_push_delivery(delivery_id,lease,'sent') from push_fixture;
do $$ begin
  if not public.finish_push_delivery((select delivery_id from push_fixture),(select lease from push_fixture),'sent') or
    exists(select 1 from public.claim_push_deliveries()) then raise exception 'sent_callback_not_idempotent'; end if;
end $$;
-- Prepare the same fixture anew without touching identities/subscriptions.
delete from public.app_notifications;
insert into public.app_notifications(id,user_id,type,title,body,dedupe_key)
select notice_id,user_id,'event_updated','Synthetic update','Synthetic update','withdrawal-fixture' from push_fixture;
update push_fixture f set delivery_id=c.delivery_id,lease=c.lease_token from public.claim_push_deliveries() c;
-- 6. Withdrawal after claim is checked before the actual send.
update public.notification_preferences set push_enabled=false where user_id=(select user_id from push_fixture);
do $$ begin if public.check_push_delivery((select delivery_id from push_fixture),(select lease from push_fixture)) is not null then
  raise exception 'withdrawal_ignored'; end if; end $$;
select public.claim_push_deliveries();
do $$ begin if (select status from public.notification_delivery_queue)<>'failed' then raise exception 'disabled_queue_not_terminal'; end if; end $$;
-- 7. Re-consent cannot revive notifications created before the new consent.
update public.notification_preferences set push_enabled=true,push_consent_at=now()+interval '1 second';
update public.notification_delivery_queue set status='queued',attempts=0;
do $$ begin if exists(select 1 from public.claim_push_deliveries()) then raise exception 'old_notice_revived_by_reconsent'; end if; end $$;
update public.notification_preferences set push_consent_at=now()-interval '1 hour';
delete from public.app_notifications;
insert into public.app_notifications(id,user_id,type,title,body,dedupe_key,created_at)
select notice_id,user_id,'event_updated','Synthetic old update','Synthetic old update','stale-fixture',now()-interval '25 hours' from push_fixture;
-- 8. Work older than 24 hours never reaches a push provider.
do $$ begin if exists(select 1 from public.claim_push_deliveries()) then raise exception 'stale_notice_claimed'; end if; end $$;
delete from public.app_notifications;
insert into public.app_notifications(id,user_id,type,title,body,dedupe_key)
select notice_id,user_id,'event_updated','Synthetic update','Synthetic update','refresh-fixture' from push_fixture;
update push_fixture f set delivery_id=c.delivery_id,lease=c.lease_token from public.claim_push_deliveries() c;
-- 9. Replacing encryption material while preserving editable updated_at still
-- invalidates the claim fingerprint and protects a renewed subscription from410.
update public.push_subscriptions set auth=repeat('c',22) where id=(select sub_id from push_fixture);
do $$ begin if public.check_push_delivery((select delivery_id from push_fixture),(select lease from push_fixture)) is not null then
  raise exception 'subscription_fingerprint_not_checked'; end if; end $$;
select public.finish_push_delivery(delivery_id,lease,'gone') from push_fixture;
do $$ begin if not exists(select 1 from public.push_subscriptions) then raise exception 'refreshed_subscription_deleted'; end if; end $$;
delete from public.app_notifications;
insert into public.app_notifications(id,user_id,type,title,body,dedupe_key)
select notice_id,user_id,'event_updated','Synthetic update','Synthetic update','attempts-fixture' from push_fixture;
update push_fixture f set delivery_id=c.delivery_id,lease=c.lease_token from public.claim_push_deliveries() c;
-- 10. Failed sends back off; exhausted/crashed final attempts become terminal.
select public.finish_push_delivery(delivery_id,lease,'retry') from push_fixture;
do $$ begin if exists(select 1 from public.claim_push_deliveries()) or
  (select next_attempt_at from public.notification_delivery_queue)<=now() then raise exception 'retry_backoff_missing'; end if; end $$;
update public.notification_delivery_queue set status='sending',attempts=5,lease_until=now()-interval '1 second';
select public.claim_push_deliveries();
do $$ begin if (select status from public.notification_delivery_queue)<>'failed' then raise exception 'final_crashed_attempt_not_terminal'; end if; end $$;
delete from public.app_notifications;
insert into public.app_notifications(id,user_id,type,title,body,dedupe_key)
select notice_id,user_id,'event_updated','Synthetic update','Synthetic update','gone-fixture' from push_fixture;
update push_fixture f set delivery_id=c.delivery_id,lease=c.lease_token from public.claim_push_deliveries() c;
-- 11.410 removes only the current expired subscription and dependent deliveries.
select public.finish_push_delivery(delivery_id,lease,'gone') from push_fixture;
do $$ begin if exists(select 1 from public.push_subscriptions) or exists(select 1 from public.notification_delivery_queue) or
  (select push_enabled from public.notification_preferences) then raise exception 'gone_subscription_cleanup_failed'; end if; end $$;
-- 12. Expired event history is excluded even for a freshly created notice.
insert into public.push_subscriptions(id,user_id,endpoint,p256dh,auth)
select sub_id,user_id,'https://web.push.apple.com/synthetic-fixture',repeat('a',87),repeat('b',22) from push_fixture;
update public.notification_preferences set push_enabled=true,push_consent_at=now()-interval '1 hour';
alter table public.events disable trigger a_event_lifecycle_stamp;
insert into public.events(id,creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission,status,closed_at)
select event_id,user_id,'Fixture expired event',5,'Amichevole',now()-interval '10 days','Private field','Roma',10,'private','approval','completed',now()-interval '8 days' from push_fixture;
alter table public.events enable trigger a_event_lifecycle_stamp;
delete from public.app_notifications;
insert into public.app_notifications(id,user_id,event_id,type,title,body,dedupe_key)
select notice_id,user_id,event_id,'event_updated','Synthetic update','Synthetic update','history-fixture' from push_fixture;
do $$ begin if exists(select 1 from public.claim_push_deliveries()) then raise exception 'expired_history_pushed'; end if; end $$;
-- 13. Invalid controls fail and Cron is never claimed active without extension.
do $$ begin
  begin perform public.claim_push_deliveries(0); raise exception 'invalid_batch_accepted'; exception when invalid_parameter_value then null; end;
  if to_regnamespace('cron') is null then
    begin perform public.configure_push_dispatch_cron(true,'nrixslotansgrtrosaof'); raise exception 'missing_cron_reported_ready';
    exception when object_not_in_prerequisite_state then null; end;
  end if;
end $$;
rollback;
