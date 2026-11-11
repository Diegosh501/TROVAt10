-- Synthetic, transaction-only regression. Use local PostgreSQL/staging; never
-- insert fixtures into a populated Auth/event database. This file always rolls back.
begin;
do $$ begin if exists(select 1 from auth.users) or exists(select 1 from public.events) then
  raise exception 'host_contact_regression_refused_on_populated_database'; end if; end $$;
create temporary table contact_fixture(owner_id uuid default gen_random_uuid(),member_id uuid default gen_random_uuid(),
  stranger_id uuid default gen_random_uuid(),session_id uuid default gen_random_uuid(),event_id uuid default gen_random_uuid()) on commit drop;
insert into contact_fixture default values;
grant select on contact_fixture to authenticated,service_role;
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select u,'contact-'||u||'@example.invalid',now(),'{"provider":"email"}'::jsonb,
  jsonb_build_object('username','qa_contact_'||left(replace(u::text,'-',''),8),'role','host',
    'age_confirmed','true','terms_accepted','true','terms_version','regression','privacy_notice_version','regression')
from contact_fixture f cross join lateral (values(f.owner_id),(f.member_id),(f.stranger_id)) users(u);
insert into auth.sessions(id,user_id,created_at,updated_at,aal,not_after)
select session_id,owner_id,now(),now(),'aal1',now()+interval '1 hour' from contact_fixture;
update public.profiles set phone_verified_at=now() where id=(select owner_id from contact_fixture);
insert into public.verified_phones(user_id,phone_hash) select owner_id,repeat('a',64) from contact_fixture;
insert into public.events(id,creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission)
select event_id,owner_id,'Synthetic contact match',5,'Amichevole',now()+interval '1 day','Synthetic venue','Roma',10,'public','approval' from contact_fixture;
insert into public.event_members(event_id,user_id,state) select event_id,member_id,'approved' from contact_fixture;
select set_config('request.jwt.claims',(select jsonb_build_object('sub',owner_id,'role','authenticated','session_id',session_id)::text from contact_fixture),true);
-- 1. No direct writes or HMAC disclosure to public clients.
do $$ begin if has_table_privilege('authenticated','public.event_host_contacts','insert') or
  has_table_privilege('authenticated','public.event_host_contacts','update') or
  has_column_privilege('authenticated','public.event_host_contacts','phone_binding_hash','select') or
  has_function_privilege('authenticated','public.set_verified_host_contact(uuid,uuid,uuid,text,text,boolean)','execute') or
  has_function_privilege('anon','public.authorize_host_contact(uuid)','execute') then raise exception 'contact_privilege_bypass'; end if; end $$;
-- 2. The user-bound operation resolves only the caller's live session.
set local role authenticated;
do $$ declare a jsonb; begin select public.authorize_host_contact(event_id) into a from contact_fixture;
  if a->>'user_id'<>(select owner_id::text from contact_fixture) then raise exception 'wrong_contact_identity'; end if; end $$;
reset role;
-- 3. A wrong HMAC cannot publish a phone merely because the account is verified.
do $$ begin
  begin perform public.set_verified_host_contact(owner_id,session_id,event_id,'+393331234567',repeat('b',64),true) from contact_fixture;
    raise exception 'wrong_number_accepted'; exception when sqlstate 'PT403' then null; end;
end $$;
-- 4. A valid server-bound hash permits sharing.
select public.set_verified_host_contact(owner_id,session_id,event_id,'+393331234567',repeat('a',64),true) from contact_fixture;
-- 5. Approved participants can read only the explicitly shared number.
select set_config('request.jwt.claims',(select jsonb_build_object('sub',member_id,'role','authenticated')::text from contact_fixture),true);
set local role authenticated;
do $$ begin if (select count(whatsapp_phone) from public.event_host_contacts)<>1 then raise exception 'approved_contact_missing'; end if; end $$;
reset role;
-- 6. Another authenticated account cannot see it.
select set_config('request.jwt.claims',(select jsonb_build_object('sub',stranger_id,'role','authenticated')::text from contact_fixture),true);
set local role authenticated;
do $$ begin if (select count(whatsapp_phone) from public.event_host_contacts)<>0 then raise exception 'stranger_contact_leak'; end if; end $$;
reset role;
-- 7. Pending requests do not reveal the contact.
update public.event_members set state='pending';
select set_config('request.jwt.claims',(select jsonb_build_object('sub',member_id,'role','authenticated')::text from contact_fixture),true);
set local role authenticated;
do $$ begin if (select count(whatsapp_phone) from public.event_host_contacts)<>0 then raise exception 'pending_contact_leak'; end if; end $$;
reset role;
update public.event_members set state='approved';
-- 8. A subsequently changed verified number invalidates the old contact binding.
update public.verified_phones set phone_hash=repeat('c',64);
set local role authenticated;
do $$ begin if (select count(whatsapp_phone) from public.event_host_contacts)<>0 then raise exception 'stale_phone_contact_leak'; end if; end $$;
reset role;
update public.verified_phones set phone_hash=repeat('a',64);
-- 9. Legacy rows without a binding are visible only to their owner.
update public.event_host_contacts set phone_binding_hash=null;
set local role authenticated;
do $$ begin if (select count(whatsapp_phone) from public.event_host_contacts)<>0 then raise exception 'legacy_contact_leak'; end if; end $$;
reset role;
select set_config('request.jwt.claims',(select jsonb_build_object('sub',owner_id,'role','authenticated','session_id',session_id)::text from contact_fixture),true);
set local role authenticated;
do $$ begin if (select count(whatsapp_phone) from public.event_host_contacts)<>1 then raise exception 'owner_lost_contact'; end if; end $$;
reset role;
-- 10. Revoked consent removes the row without requiring a current phone hash.
select public.set_verified_host_contact(owner_id,session_id,event_id,'','',false) from contact_fixture;
do $$ begin if exists(select 1 from public.event_host_contacts) then raise exception 'consent_revoke_failed'; end if; end $$;
-- 11. A forged user/session pair cannot use the reserved write function.
do $$ begin
  begin perform public.set_verified_host_contact(stranger_id,session_id,event_id,'+393331234567',repeat('a',64),true) from contact_fixture;
    raise exception 'session_identity_mismatch_accepted'; exception when sqlstate 'PT401' then null; end;
end $$;
-- 12. Revocation is checked again at commit, after initial authorization.
delete from auth.sessions;
do $$ begin
  begin perform public.set_verified_host_contact(owner_id,session_id,event_id,'+393331234567',repeat('a',64),true) from contact_fixture;
    raise exception 'revoked_session_accepted'; exception when sqlstate 'PT401' then null; end;
end $$;
rollback;
