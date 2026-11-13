-- Local isolated fixture only. Refuses populated data, rolls back all changes.
begin;
do $$ begin if exists(select 1 from auth.users) or exists(select 1 from public.events) then
  raise exception 'notification_regression_refused_on_populated_database'; end if; end $$;
create temporary table notice_fixture(host_id uuid default gen_random_uuid(),player_id uuid default gen_random_uuid()) on commit drop;
insert into notice_fixture default values;
grant select on notice_fixture to authenticated;
insert into auth.users(id,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data)
select uid,uid||'@example.invalid',now(),'{"provider":"email","providers":["email"]}'::jsonb,
 jsonb_build_object('username','notice_'||left(replace(uid::text,'-',''),10),'role',role,
 'age_confirmed','true','terms_accepted','true','terms_version','regression','privacy_notice_version','regression')
from notice_fixture f cross join lateral(values(f.host_id,'host'),(f.player_id,'sportivo')) users(uid,role);
insert into auth.sessions(id,user_id,aal,not_after)
select uid,uid,'aal1',now()+interval '1 hour' from notice_fixture f cross join lateral(values(f.host_id),(f.player_id)) users(uid);
update public.profiles set phone_verified_at=now();
-- Premium is fixture setup to isolate notifications from the two-active limit.
update public.subscriptions set plan='premium',current_period_end=now()+interval '1 year';
create temporary table notice_events(id uuid default gen_random_uuid(),purpose text) on commit drop;
insert into notice_events(purpose) values('start'),('finish'),('cancel'),('edit');
grant select on notice_events to authenticated;
insert into public.events(id,creator_id,title,format,kind,starts_at,venue,city,max_players,visibility,admission,status)
select n.id,f.host_id,'Notification regression - '||n.purpose,5,'Amichevole',now()+interval '2 days',
 'Synthetic private venue','Synthetic city',10,'private','approval','scheduled'
from notice_events n cross join notice_fixture f;
insert into public.event_members(event_id,user_id,state)
select n.id,f.player_id,'approved' from notice_events n cross join notice_fixture f;
-- Prepare completion independently; a transaction shares now(), so remove only
-- this fixture's prior update notice before asserting its final notice.
update public.events set status='in_progress' where id=(select id from notice_events where purpose='finish');
delete from public.app_notifications where event_id=(select id from notice_events where purpose='finish') and type='event_updated';
select set_config('request.jwt.claims',(select jsonb_build_object('sub',host_id,'role','authenticated','session_id',host_id)::text from notice_fixture),true);
set local role authenticated;
select public.update_event_status(id,'in_progress') from notice_events where purpose='start';
select public.update_event_status(id,'completed') from notice_events where purpose='finish';
select public.update_event_status(id,'cancelled') from notice_events where purpose='cancel';
reset role;
update public.events set venue='Changed synthetic venue' where id=(select id from notice_events where purpose='edit');
do $$ declare v_purpose text;v_title text;v_body text;v_expected text; begin
 for v_purpose,v_expected in select * from (values('start','Partita iniziata'),('finish','Partita conclusa'),('cancel','Partita annullata'),('edit','Partita aggiornata')) expectations(purpose,title)
 loop
  select title,body into v_title,v_body from public.app_notifications
   where user_id=(select player_id from notice_fixture) and event_id=(select id from notice_events where purpose=v_purpose)
     and type in ('event_updated','event_cancelled');
  if v_title is distinct from v_expected then raise exception 'wrong notification for %: %',v_purpose,v_title; end if;
  if v_purpose in ('start','finish') and v_body like '%data, orario o luogo%' then raise exception 'status incorrectly described as schedule change'; end if;
  if v_body like '%private venue%' or v_body like '%Synthetic%' then raise exception 'notification leaked private venue'; end if;
 end loop;
end $$;
rollback;
