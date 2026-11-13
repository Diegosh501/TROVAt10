begin;
do $$ begin if exists(select 1 from auth.users) or exists(select 1 from public.events) then
 raise exception 'erasure_intake_test_refused_on_populated_database'; end if; end $$;
create temporary table erasure_fixture(a uuid default gen_random_uuid(),b uuid default gen_random_uuid(),sa uuid default gen_random_uuid(),sb uuid default gen_random_uuid()) on commit drop;
insert into erasure_fixture default values;
grant select on erasure_fixture to authenticated;
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select id,'erasure-'||id||'@example.invalid',now(),'{"provider":"email"}'::jsonb,
 jsonb_build_object('username','qa_erase_'||left(replace(id::text,'-',''),8),'role','sportivo','age_confirmed','true','terms_accepted','true','terms_version','regression','privacy_notice_version','regression')
from erasure_fixture f cross join lateral(values(f.a),(f.b)) ids(id);
insert into auth.sessions(id,user_id,aal,not_after) select sid,uid,'aal1',now()+interval '1 hour' from erasure_fixture f cross join lateral(values(f.sa,f.a),(f.sb,f.b)) sessions(sid,uid);
insert into public.subscriptions(user_id,plan,status,current_period_end) select a,'premium','active',now()+interval '1 year' from erasure_fixture;
insert into public.subscriptions(user_id,plan,status) select b,'free','active' from erasure_fixture;
-- No target account argument, anonymous grants or direct table permissions.
do $$ begin
 if has_function_privilege('anon','public.request_account_erasure(boolean)','execute') or has_function_privilege('anon','public.my_account_erasure_request()','execute')
 or has_table_privilege('authenticated','public.support_requests','select') or has_table_privilege('authenticated','public.support_requests','insert') then raise exception 'intake_privilege_leak'; end if;
end $$;
select set_config('request.jwt.claims',(select jsonb_build_object('sub',a,'session_id',sa,'role','authenticated')::text from erasure_fixture),true);
set local role authenticated;
do $$ declare x jsonb; begin
 if public.my_account_erasure_request() is not null then raise exception 'invented_receipt'; end if;
 begin perform public.request_account_erasure(false);raise exception 'false_confirmation_accepted';exception when invalid_parameter_value then null;end;
 begin perform public.request_account_erasure(null);raise exception 'null_confirmation_accepted';exception when invalid_parameter_value then null;end;
 x:=public.request_account_erasure(true);
 if x->>'status'<>'new' or (x->>'accountErased')::boolean or (x->>'accessClosed')::boolean then raise exception 'fake_erased_or_closed'; end if;
 if public.request_account_erasure(true)->>'id'<>x->>'id' then raise exception 'duplicate_request'; end if;
 if x::text like '%example.invalid%' or x::text like '%session_id%' or x::text like '%details%' then raise exception 'receipt_pii'; end if;
 begin perform 1 from public.support_requests;raise exception 'direct_table_read';exception when insufficient_privilege then null;end;
end $$;
reset role;
do $$ begin
 if (select count(*) from public.support_requests)<>1 or exists(select 1 from public.support_requests where request_kind<>'account_erasure' or category<>'account' or requester_user_id<>(select a from erasure_fixture) or contact_allowed or contact_email is not null or contact_name is not null) then raise exception 'bad_admin_queue_record'; end if;
 if private.account_deletion_hold((select a from erasure_fixture))<>'premium' then raise exception 'premium_hold_changed'; end if;
 if (select count(*) from auth.users)<>2 or (select count(*) from auth.sessions)<>2 or not public.has_live_session() then raise exception 'request_deleted_or_closed_account'; end if;
end $$;
-- Independent Free/no-match caller sees no other receipt and can request now.
select set_config('request.jwt.claims',(select jsonb_build_object('sub',b,'session_id',sb,'role','authenticated')::text from erasure_fixture),true);
set local role authenticated;
do $$ declare x jsonb; begin
 if public.my_account_erasure_request() is not null then raise exception 'cross_user_receipt'; end if;
 x:=public.request_account_erasure(true);if x->>'id' is null then raise exception 'free_no_match_blocked'; end if;
end $$;
reset role;
do $$ begin if private.account_deletion_hold((select b from erasure_fixture))<>'support' then raise exception 'open_request_not_preserved'; end if;end $$;
-- Existing generic tickets do not impersonate an erasure request.
insert into public.support_requests(requester_user_id,category,subject,details) select b,'account','Generic ticket','Generic support is not authenticated erasure intent.' from erasure_fixture;
-- Closed receipts stay receipts, not claims that a deletion occurred.
update public.support_requests set status='closed' where requester_user_id=(select b from erasure_fixture) and request_kind='account_erasure';
set local role authenticated;
do $$ declare x jsonb;begin x:=public.my_account_erasure_request();if x->>'status'<>'closed' or (x->>'accountErased')::boolean then raise exception 'closed_means_erased';end if;end $$;
reset role;
-- Three actual requests/day maximum, while repeats of open requests stay idempotent.
update public.support_requests set status='closed' where requester_user_id=(select b from erasure_fixture);
set local role authenticated;
select public.request_account_erasure(true);
reset role;
update public.support_requests set status='closed' where requester_user_id=(select b from erasure_fixture);
set local role authenticated;
select public.request_account_erasure(true);
reset role;
update public.support_requests set status='closed' where requester_user_id=(select b from erasure_fixture);
set local role authenticated;
do $$ begin begin perform public.request_account_erasure(true);raise exception 'quota_bypassed';exception when sqlstate 'PT429' then null;end;end $$;
reset role;
-- Revocation rejects both reads and writes with the previous JWT.
delete from auth.sessions where id=(select sb from erasure_fixture);
set local role authenticated;
do $$ begin
 begin perform public.request_account_erasure(true);raise exception 'revoked_write';exception when sqlstate 'PT401' then null;end;
 begin perform public.my_account_erasure_request();raise exception 'revoked_read';exception when sqlstate 'PT401' then null;end;
end $$;
reset role;
rollback;
