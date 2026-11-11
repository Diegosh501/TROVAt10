-- Extend the already protected console. Operational roles never assign Admin.
alter table private.admin_audit drop constraint if exists admin_audit_action_check;
alter table private.admin_audit add constraint admin_audit_action_check check(action in (
  'dashboard_read','tickets_read','ticket_updated','admin_enabled','admin_disabled','audit_read',
  'users_read','events_read','reports_read','user_role_updated','report_reviewed','event_cancelled'));

create or replace function public.admin_users(p_query text default '',p_role text default '',p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb; total bigint;
begin
  perform private.require_platform_admin('users_read');
  if p_query is null or length(p_query)>100 or p_role is null or p_role not in ('','host','sportivo')
    or p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'invalid_request' using errcode='22023'; end if;
  select count(*) into total from public.profiles p where (p_role='' or p.role=p_role) and (p_query='' or p.username ilike '%'||p_query||'%');
  select coalesce(jsonb_agg(r.data order by r.username,r.id),'[]') into rows from (
    select p.username,p.id,jsonb_build_object('id',p.id,'username',p.username,'role',p.role,'createdAt',p.created_at,
      'plan',case when s.plan='premium' and s.status='active' and s.current_period_end>now() then 'premium' else 'free' end,
      'activeEvents',(select count(*) from public.events e where e.creator_id=p.id and e.status in ('scheduled','in_progress'))) as data
    from public.profiles p left join public.subscriptions s on s.user_id=p.id
    where (p_role='' or p.role=p_role) and (p_query='' or p.username ilike '%'||p_query||'%')
    order by p.username,p.id limit 25 offset p_offset) r;
  return jsonb_build_object('rows',rows,'total',total,'offset',p_offset,'limit',25);
end $$;

create or replace function public.admin_events(p_query text default '',p_status text default '',p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb; total bigint;
begin
  perform private.require_platform_admin('events_read');
  if p_query is null or length(p_query)>100 or p_status is null or p_status not in ('','scheduled','in_progress','completed','cancelled')
    or p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'invalid_request' using errcode='22023'; end if;
  select count(*) into total from public.events e join public.profiles p on p.id=e.creator_id
    where (p_status='' or e.status=p_status) and (p_query='' or e.title ilike '%'||p_query||'%' or p.username ilike '%'||p_query||'%');
  select coalesce(jsonb_agg(r.data order by r.starts_at desc,r.id),'[]') into rows from (
    select e.starts_at,e.id,jsonb_build_object('id',e.id,'title',e.title,'startsAt',e.starts_at,'format',e.format,
      'status',e.status,'visibility',e.visibility,'creatorUsername',p.username) as data
    from public.events e join public.profiles p on p.id=e.creator_id
    where (p_status='' or e.status=p_status) and (p_query='' or e.title ilike '%'||p_query||'%' or p.username ilike '%'||p_query||'%')
    order by e.starts_at desc,e.id limit 25 offset p_offset) r;
  return jsonb_build_object('rows',rows,'total',total,'offset',p_offset,'limit',25);
end $$;

create or replace function public.admin_reports(p_query text default '',p_status text default '',p_offset integer default 0)
returns jsonb language plpgsql security definer set search_path='' as $$
declare rows jsonb; total bigint;
begin
  perform private.require_platform_admin('reports_read');
  if p_query is null or length(p_query)>100 or p_status is null or p_status not in ('','received','in_review','actioned','no_action','appealed')
    or p_offset is null or p_offset<0 or p_offset>100000 then raise exception 'invalid_request' using errcode='22023'; end if;
  select count(*) into total from public.player_reports r join public.profiles s on s.id=r.subject_id
    join public.profiles p on p.id=r.reporter_id where (p_status='' or r.state=p_status) and
      (p_query='' or s.username ilike '%'||p_query||'%' or p.username ilike '%'||p_query||'%' or r.reason ilike '%'||p_query||'%');
  select coalesce(jsonb_agg(x.data order by x.created_at desc,x.id),'[]') into rows from (
    select r.created_at,r.id,jsonb_build_object('id',r.id,'eventId',r.event_id,'subjectUsername',s.username,
      'reporterUsername',p.username,'reason',r.reason,'details',r.details,'state',r.state,'createdAt',r.created_at,
      'reviewNote',r.review_note) as data from public.player_reports r join public.profiles s on s.id=r.subject_id
    join public.profiles p on p.id=r.reporter_id where (p_status='' or r.state=p_status) and
      (p_query='' or s.username ilike '%'||p_query||'%' or p.username ilike '%'||p_query||'%' or r.reason ilike '%'||p_query||'%')
    order by r.created_at desc,r.id limit 25 offset p_offset) x;
  return jsonb_build_object('rows',rows,'total',total,'offset',p_offset,'limit',25);
end $$;

create or replace function public.admin_set_user_role(p_id uuid,p_role text)
returns boolean language plpgsql security definer set search_path='' as $$
begin
  perform private.require_platform_admin('user_role_updated',p_id);
  if p_id is null or p_role is null or p_role not in ('host','sportivo') then raise exception 'invalid_request' using errcode='22023'; end if;
  update public.profiles set role=p_role where id=p_id;
  if not found then raise exception 'not_found' using errcode='PT404'; end if;
  return true;
end $$;
create or replace function public.admin_review_report(p_id uuid,p_status text,p_note text default '')
returns boolean language plpgsql security definer set search_path='' as $$
begin
  perform private.require_platform_admin('report_reviewed',p_id);
  if p_id is null or p_status is null or p_status not in ('received','in_review','actioned','no_action','appealed')
    or p_note is null or length(p_note)>2000 then raise exception 'invalid_request' using errcode='22023'; end if;
  update public.player_reports set state=p_status,review_note=p_note,
    reviewed_at=case when p_status in ('actioned','no_action') then now() else null end where id=p_id;
  if not found then raise exception 'not_found' using errcode='PT404'; end if;
  return true;
end $$;
create or replace function public.admin_cancel_event(p_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare state text;
begin
  perform private.require_platform_admin('event_cancelled',p_id);
  select e.status into state from public.events e where id=p_id for update;
  if not found then raise exception 'not_found' using errcode='PT404'; end if;
  if state='cancelled' then return true; end if;
  if state='completed' then raise exception 'closed_event' using errcode='22023'; end if;
  update public.events set status='cancelled',updated_at=now() where id=p_id;
  return true;
end $$;
revoke all on function public.admin_users(text,text,integer),public.admin_events(text,text,integer),public.admin_reports(text,text,integer),
  public.admin_set_user_role(uuid,text),public.admin_review_report(uuid,text,text),public.admin_cancel_event(uuid) from public,anon;
grant execute on function public.admin_users(text,text,integer),public.admin_events(text,text,integer),public.admin_reports(text,text,integer),
  public.admin_set_user_role(uuid,text),public.admin_review_report(uuid,text,text),public.admin_cancel_event(uuid) to authenticated;
