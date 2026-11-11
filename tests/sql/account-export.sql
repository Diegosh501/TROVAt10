begin;
do $$ begin if exists(select 1 from auth.users) or exists(select 1 from public.events) then
 raise exception 'account_export_regression_refused_on_populated_database'; end if; end $$;
create temporary table export_fixture(first_id uuid default gen_random_uuid(),other_id uuid default gen_random_uuid(),
 session_id uuid default gen_random_uuid(),event_id uuid default gen_random_uuid()) on commit drop;
insert into export_fixture default values;
grant select on export_fixture to authenticated;
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select u,'export-'||u||'@example.invalid',now(),'{"provider":"email"}'::jsonb,jsonb_build_object('username','qa_export_'||left(replace(u::text,'-',''),8),
 'role','host','age_confirmed','true','terms_accepted','true','terms_version','regression','privacy_notice_version','regression')
from export_fixture f cross join lateral(values(f.first_id),(f.other_id)) users(u);
insert into auth.sessions(id,user_id,created_at,updated_at,aal,not_after)
select session_id,first_id,now(),now(),'aal1',now()+interval '1 hour' from export_fixture;
insert into public.events(id,creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission)
select event_id,other_id,'Other private fixture',5,'Amichevole',now()+interval '1 day','Private venue','Roma',10,'private','approval' from export_fixture;
insert into public.events(creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission)
select first_id,'Export pagination fixture',5,'Amichevole',now()+interval '1 day','Own venue','Roma',10,'private','approval'
from export_fixture cross join generate_series(1,102);
insert into public.event_members(event_id,user_id,state) select event_id,first_id,'pending' from export_fixture;
select set_config('request.jwt.claims',(select jsonb_build_object('sub',first_id,'role','authenticated','session_id',session_id)::text from export_fixture),true);
-- 1. Anonymous callers and arbitrary UID input have no export API.
do $$ begin if has_function_privilege('anon','public.export_my_data(text,uuid)','execute') then raise exception 'anonymous_export_privilege'; end if; end $$;
set local role authenticated;
-- 2. Profile contains only the caller's information and no Auth tokens.
do $$ declare x jsonb; begin x:=public.export_my_data('profile');
 if x->'rows'->0->>'id'<>(select first_id::text from export_fixture) or jsonb_array_length(x->'rows')<>1
   or x::text like '%encrypted_password%' or x::text like '%session_id%' then raise exception 'profile_export_leak'; end if;
end $$;
-- 3. Paginated own events exclude another user's private event and all tokens.
do $$ declare a jsonb;b jsonb; begin a:=public.export_my_data('events');
 if jsonb_array_length(a->'rows')<>100 or a->>'nextCursor' is null then raise exception 'export_page_bound'; end if;
 b:=public.export_my_data('events',(a->>'nextCursor')::uuid);
 if jsonb_array_length(b->'rows')<>2 or b->>'nextCursor' is not null then raise exception 'export_second_page'; end if;
 if a::text like '%Other private fixture%' or b::text like '%Other private fixture%' or a::text like '%token_hash%' then raise exception 'foreign_event_export'; end if;
end $$;
-- 4. Participation exports own state, not the private venue or other players.
do $$ declare x jsonb; begin x:=public.export_my_data('participations');
 if x->'rows'->0->>'state'<>'pending' or x::text like '%Private venue%' or x::text like '%username%' then raise exception 'participation_export_leak'; end if;
end $$;
-- 5. Missing optional sections return empty arrays, never another user's records.
do $$ declare s text;x jsonb; begin foreach s in array array['reports','notifications','contacts','preferences','subscription','support'] loop
 x:=public.export_my_data(s); if jsonb_typeof(x->'rows')<>'array' then raise exception 'invalid_export_shape'; end if; end loop;
end $$;
-- 6. Section validation prevents arbitrary table/SQL access.
do $$ begin begin perform public.export_my_data('auth.users'); raise exception 'arbitrary_export'; exception when invalid_parameter_value then null; end; end $$;
reset role;
-- 7. An old JWT cannot continue exporting after session revocation.
delete from auth.sessions;
set local role authenticated;
do $$ begin begin perform public.export_my_data('profile'); raise exception 'revoked_export'; exception when sqlstate 'PT401' then null; end; end $$;
reset role;
rollback;
