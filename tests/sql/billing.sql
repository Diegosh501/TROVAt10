-- Pre-launch only, synthetic data, complete ROLLBACK. Refuses a populated app.
begin;
do $$ begin
  if exists(select 1 from auth.users) or exists(select 1 from public.events) then
    raise exception 'billing_regression_refused_on_populated_database'; end if;
end $$;
create temporary table billing_fixture(user_id uuid default gen_random_uuid(),session_id uuid default gen_random_uuid(),
  lease uuid,sync_lease uuid,claims jsonb) on commit drop;
insert into billing_fixture default values;
grant select on billing_fixture to authenticated,service_role;
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select user_id,'billing-'||user_id||'@example.invalid',now(),'{"provider":"google","providers":["google"]}','{}' from billing_fixture;
insert into auth.identities(provider_id,user_id,identity_data,provider,created_at,updated_at)
select user_id::text,user_id,jsonb_build_object('sub',user_id,'email_verified',true),'google',now(),now() from billing_fixture;
insert into public.profiles(id,username,role,age_confirmed_at,terms_accepted_at,privacy_notice_ack_at,terms_version,privacy_notice_version)
select user_id,'qa_billing_'||left(replace(user_id::text,'-',''),8),'host',now(),now(),now(),'regression','regression' from billing_fixture;
insert into public.subscriptions(user_id,plan,status) select user_id,'free','active' from billing_fixture;
insert into auth.sessions(id,user_id,created_at,updated_at,aal,not_after)
select session_id,user_id,now(),now(),'aal1',now()+interval '1 hour' from billing_fixture;
update billing_fixture set claims=jsonb_build_object('sub',user_id,'role','authenticated','session_id',session_id);
select set_config('request.jwt.claims',(select claims::text from billing_fixture),true);
-- 1. Public roles cannot call privileged payment transport or read private data.
do $$ begin
  if has_function_privilege('anon','public.billing_service(text,jsonb)','execute') or
    has_function_privilege('authenticated','public.billing_service(text,jsonb)','execute') or
    has_table_privilege('authenticated','private.billing_accounts','select') or
    has_table_privilege('authenticated','public.subscriptions','update') then raise exception 'billing_privilege_bypass'; end if;
end $$;
-- 2. An existing, verified Google session can authorize only itself.
set local role authenticated;
do $$ begin if public.billing_authorize()<>(select user_id from billing_fixture) then raise exception 'wrong_billing_identity'; end if; end $$;
reset role;
-- 3. Missing/expired sessions fail immediately despite valid old JWT claims.
update auth.sessions set not_after=now()-interval '1 second' where id=(select session_id from billing_fixture);
set local role authenticated;
do $$ begin
  begin perform public.billing_authorize(); raise exception 'expired_session_accepted';
  exception when sqlstate 'PT401' then null; end;
end $$;
reset role;
update auth.sessions set not_after=now()+interval '1 hour' where id=(select session_id from billing_fixture);
-- 4. Bans apply to payment actions before token expiry.
update auth.users set banned_until=now()+interval '1 hour' where id=(select user_id from billing_fixture);
set local role authenticated;
do $$ begin
  begin perform public.billing_authorize(); raise exception 'banned_account_accepted';
  exception when sqlstate 'PT401' then null; end;
end $$;
reset role;
update auth.users set banned_until=null where id=(select user_id from billing_fixture);
-- 5. Purchase lock serializes concurrent requests and cannot be forged with null.
update billing_fixture set lease=(public.billing_service('checkout-lock',jsonb_build_object('mode','test','user_id',user_id))->>'token')::uuid;
do $$ declare u uuid:=(select user_id from billing_fixture); begin
  begin perform public.billing_service('checkout-lock',jsonb_build_object('mode','test','user_id',u)); raise exception 'parallel_checkout_accepted';
  exception when sqlstate 'PT409' then null; end;
  begin perform public.billing_service('customer-bind',jsonb_build_object('mode','test','user_id',u,'customer_id','cus_test')); raise exception 'null_lease_accepted';
  exception when sqlstate 'PT409' then null; end;
end $$;
select public.billing_service('customer-bind',jsonb_build_object('mode','test','user_id',user_id,'token',lease,'customer_id','cus_test')) from billing_fixture;
-- 6. Sync is serialized separately and validates its lease.
update billing_fixture set sync_lease=(public.billing_service('sync-lock','{"mode":"test","customer_id":"cus_test"}')->>'token')::uuid;
do $$ begin
  begin perform public.billing_service('sync-lock','{"mode":"test","customer_id":"cus_test"}'); raise exception 'parallel_sync_accepted';
  exception when sqlstate 'PT409' then null; end;
end $$;
create function pg_temp.apply_billing(p_mode text,p_customer text,p_token uuid,p_status text default 'active',p_cancel boolean default false,p_risk jsonb default null)
returns jsonb language sql as $$
  select public.billing_service('apply',jsonb_build_object('mode',p_mode,'customer_id',p_customer,'token',p_token,
    'subscription',jsonb_build_object('id','sub_'||p_mode,'customer_id',p_customer,'price_id','price_annual','status',p_status,'cancel_at_period_end',p_cancel),
    'invoices',jsonb_build_array(jsonb_build_object('id','in_'||p_mode,'paid_until',extract(epoch from now()+interval '365 days'))),'risk',p_risk))
$$;
-- 7. A paid TEST subscription never grants production Premium.
select pg_temp.apply_billing('test','cus_test',sync_lease) from billing_fixture;
do $$ begin if exists(select 1 from public.subscriptions where plan<>'free') then raise exception 'sandbox_elevated_production'; end if; end $$;
-- 8. Test and live customer mappings are independent.
update billing_fixture set lease=(public.billing_service('checkout-lock',jsonb_build_object('mode','live','user_id',user_id))->>'token')::uuid;
select public.billing_service('customer-bind',jsonb_build_object('mode','live','user_id',user_id,'token',lease,'customer_id','cus_livefixture')) from billing_fixture;
update billing_fixture set sync_lease=(public.billing_service('sync-lock','{"mode":"live","customer_id":"cus_livefixture"}')->>'token')::uuid;
-- 9. A verified live paid period grants exactly the mapped owner Premium.
select pg_temp.apply_billing('live','cus_livefixture',sync_lease) from billing_fixture;
do $$ begin if (select plan from public.subscriptions)<>'premium' or
  (select current_period_end from public.subscriptions)<=now() then raise exception 'live_paid_entitlement_missing'; end if; end $$;
-- 10. Cancellation at period end retains the paid term.
select pg_temp.apply_billing('live','cus_livefixture',sync_lease,'active',true) from billing_fixture;
do $$ begin if (select plan from public.subscriptions)<>'premium' then raise exception 'period_end_removed_paid_service'; end if; end $$;
-- 11. Full refunds revoke only the affected invoice.
select pg_temp.apply_billing('live','cus_livefixture',sync_lease,'active',true,
  jsonb_build_object('reason','refund','invoice_id','in_live','paid_until',extract(epoch from now()+interval '365 days'))) from billing_fixture;
do $$ begin if (select plan from public.subscriptions)<>'free' then raise exception 'refunded_entitlement_retained'; end if; end $$;
-- 12. Delayed invoice.paid replay cannot undo a refund tombstone.
select pg_temp.apply_billing('live','cus_livefixture',sync_lease) from billing_fixture;
do $$ begin if (select plan from public.subscriptions)<>'free' then raise exception 'replay_undid_refund'; end if; end $$;
-- 13. A dispute hold survives later ordinary subscription updates.
update private.billing_invoices set revoked=false where mode='live';
select pg_temp.apply_billing('live','cus_livefixture',sync_lease,'active',false,'{"reason":"dispute","object_id":"dp_fixture","active":true}') from billing_fixture;
select pg_temp.apply_billing('live','cus_livefixture',sync_lease) from billing_fixture;
do $$ begin if (select plan from public.subscriptions)<>'free' then raise exception 'ordinary_update_cleared_hold'; end if; end $$;
-- 14. A won dispute clears exactly its hold; remaining fraud holds still apply.
select pg_temp.apply_billing('live','cus_livefixture',sync_lease,'active',false,'{"reason":"dispute","object_id":"dp_fixture","active":false}') from billing_fixture;
do $$ begin if (select plan from public.subscriptions)<>'premium' then raise exception 'won_dispute_did_not_restore'; end if; end $$;
select pg_temp.apply_billing('live','cus_livefixture',sync_lease,'active',false,'{"reason":"fraud","object_id":"issfr_fixture","active":true}') from billing_fixture;
select pg_temp.apply_billing('live','cus_livefixture',sync_lease,'active',false,'{"reason":"dispute","object_id":"dp_fixture","active":false}') from billing_fixture;
do $$ begin if (select plan from public.subscriptions)<>'free' then raise exception 'fraud_hold_bypassed'; end if; end $$;
-- 15. Immediate cancellation removes access even with a paid period on record.
update private.billing_holds set active=false where mode='live';
select pg_temp.apply_billing('live','cus_livefixture',sync_lease,'canceled') from billing_fixture;
do $$ begin if (select plan from public.subscriptions)<>'free' then raise exception 'canceled_retained_access'; end if; end $$;
-- 16. Infinite Premium without an expiry is invalid even for privileged writes.
do $$ begin
  begin update public.subscriptions set plan='premium',current_period_end=null; raise exception 'infinite_premium_accepted';
  exception when check_violation then null; end;
end $$;
-- 17. Event claims deduplicate delivery and support a retry after failure.
do $$ declare e jsonb; again jsonb; begin
  e:=public.billing_service('claim-event',jsonb_build_object('mode','test','event_id','evt_fixture','type','invoice.paid','created',extract(epoch from now())));
  begin perform public.billing_service('claim-event',jsonb_build_object('mode','test','event_id','evt_fixture','type','invoice.paid','created',extract(epoch from now()))); raise exception 'event_claim_reentered';
  exception when sqlstate 'PT409' then null; end;
  perform public.billing_service('finish-event',jsonb_build_object('mode','test','event_id','evt_fixture','token',e->>'token','success',false));
  again:=public.billing_service('claim-event',jsonb_build_object('mode','test','event_id','evt_fixture','type','invoice.paid','created',extract(epoch from now())));
  if again->>'token'=e->>'token' then raise exception 'event_lease_not_rotated'; end if;
  perform public.billing_service('finish-event',jsonb_build_object('mode','test','event_id','evt_fixture','token',again->>'token','success',true));
  e:=public.billing_service('claim-event',jsonb_build_object('mode','test','event_id','evt_fixture','type','invoice.paid','created',extract(epoch from now())));
  if not (e->>'done')::boolean then raise exception 'event_not_deduplicated'; end if;
end $$;
-- 18. A forged service lease never changes the entitlement.
do $$ begin
  begin perform pg_temp.apply_billing('live','cus_livefixture',null); raise exception 'null_sync_lease_accepted';
  exception when sqlstate 'PT409' then null; end;
end $$;
-- 19. Rate limiting is checked in the same authenticated database path.
set local role authenticated;
do $$ begin
  for n in 1..11 loop perform public.billing_authorize(); end loop;
  begin perform public.billing_authorize(); raise exception 'billing_quota_bypassed';
  exception when sqlstate 'PT429' then null; end;
end $$;
reset role;
rollback;
