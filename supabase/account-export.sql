-- Subject-access export: caller-owned records only, paginated without Auth
-- tokens, phone HMACs, invitation tokens or other participants' personal data.
create table private.account_export_quota (
 user_id uuid primary key references public.profiles(id) on delete cascade,
 window_at timestamptz not null, attempts integer not null
);
alter table private.account_export_quota enable row level security;
revoke all on private.account_export_quota from public,anon,authenticated;
create or replace function public.export_my_data(p_section text,p_after uuid default null)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=auth.uid(); sid uuid; rows jsonb; n integer;
begin
 if u is null or not public.is_email_confirmed() or not exists(select 1 from public.profiles where id=u) then
   raise exception 'authentication_required' using errcode='PT401'; end if;
 begin sid:=(auth.jwt()->>'session_id')::uuid; exception when invalid_text_representation then sid:=null; end;
 if sid is null or not exists(select 1 from auth.sessions where id=sid and user_id=u and (not_after is null or not_after>now())) then
   raise exception 'session_revoked' using errcode='PT401'; end if;
 if p_section is null or p_section not in ('profile','events','participations','reports','notifications','contacts','preferences','subscription','support') then
   raise exception 'invalid_section' using errcode='22023'; end if;
 insert into private.account_export_quota(user_id,window_at,attempts) values(u,now(),1)
 on conflict(user_id) do update set attempts=case when account_export_quota.window_at<now()-interval '1 minute' then 1 else account_export_quota.attempts+1 end,
   window_at=case when account_export_quota.window_at<now()-interval '1 minute' then now() else account_export_quota.window_at end returning attempts into n;
 if n>60 then raise exception 'export_rate_limited' using errcode='PT429'; end if;
 if p_section='profile' then
   select jsonb_build_array(jsonb_build_object('id',p.id,'username',p.username,'role',p.role,'email',a.email,
     'createdAt',p.created_at,'adultConfirmedAt',p.age_confirmed_at,'termsAcceptedAt',p.terms_accepted_at,
     'privacyAcknowledgedAt',p.privacy_notice_ack_at,'termsVersion',p.terms_version,'privacyVersion',p.privacy_notice_version,
     'phoneVerifiedAt',p.phone_verified_at,'googleName',a.raw_user_meta_data->>'full_name','googleAvatar',a.raw_user_meta_data->>'avatar_url')) into rows from public.profiles p join auth.users a on a.id=p.id where p.id=u and p_after is null;
 elsif p_section='events' then
   select jsonb_agg(x.data order by x.id) into rows from(select e.id,jsonb_build_object('id',e.id,'title',e.title,'format',e.format,
     'kind',e.kind,'startsAt',e.starts_at,'venue',e.venue,'city',e.city,'latitude',e.latitude,'longitude',e.longitude,
     'maxPlayers',e.max_players,'visibility',e.visibility,'admission',e.admission,'description',e.description,
     'costLabel',e.cost_label,'skill',e.skill,'status',e.status,'createdAt',e.created_at,'updatedAt',e.updated_at,
     'closedAt',to_jsonb(e)->'closed_at','archivedAt',to_jsonb(e)->'archived_at') as data
     from public.events e where e.creator_id=u and (p_after is null or e.id>p_after) order by e.id limit 100) x;
 elsif p_section='participations' then
   select jsonb_agg(x.data order by x.id) into rows from(select m.event_id as id,jsonb_build_object('id',m.event_id,
     'eventId',m.event_id,'state',m.state,'createdAt',m.created_at,'updatedAt',m.updated_at) as data
     from public.event_members m where m.user_id=u and (p_after is null or m.event_id>p_after) order by m.event_id limit 100) x;
 elsif p_section='reports' then
   select jsonb_agg(x.data order by x.id) into rows from(select r.id,jsonb_build_object('id',r.id,'eventId',r.event_id,
     'reason',r.reason,'details',r.details,'state',r.state,'createdAt',r.created_at,'reviewedAt',r.reviewed_at,'reviewNote',r.review_note) as data
     from public.player_reports r where r.reporter_id=u and (p_after is null or r.id>p_after) order by r.id limit 100) x;
 elsif p_section='notifications' then
   select jsonb_agg(x.data order by x.id) into rows from(select a.id,jsonb_build_object('id',a.id,'eventId',a.event_id,
     'type',a.type,'title',a.title,'body',a.body,'createdAt',a.created_at,'readAt',a.read_at) as data
     from public.app_notifications a where a.user_id=u and (p_after is null or a.id>p_after) order by a.id limit 100) x;
 elsif p_section='contacts' then
   select jsonb_agg(x.data order by x.id) into rows from(select c.event_id as id,jsonb_build_object('id',c.event_id,
     'phone',c.whatsapp_phone,'shareWithApproved',c.share_with_approved,'updatedAt',c.updated_at) as data
     from public.event_host_contacts c join public.events e on e.id=c.event_id where e.creator_id=u
       and (p_after is null or c.event_id>p_after) order by c.event_id limit 100) x;
 elsif p_section='support' then
   select jsonb_agg(x.data order by x.id) into rows from(select r.id,
     (to_jsonb(r)-'requester_user_id'-'search_document') as data from public.support_requests r
     where r.requester_user_id=u and (p_after is null or r.id>p_after) order by r.id limit 100) x;
 elsif p_section='preferences' then
   select jsonb_build_array(jsonb_build_object('id',n.user_id,'activityEnabled',n.activity_enabled,'remindersEnabled',n.reminders_enabled,
     'pushEnabled',n.push_enabled,'pushConsentAt',n.push_consent_at,'updatedAt',n.updated_at)) into rows
     from public.notification_preferences n where n.user_id=u and p_after is null;
 else
   select jsonb_build_array(jsonb_build_object('id',s.user_id,'plan',s.plan,'status',s.status,'currentPeriodEnd',s.current_period_end,
     'updatedAt',s.updated_at)) into rows from public.subscriptions s where s.user_id=u and p_after is null;
 end if;
 rows:=coalesce(rows,'[]'::jsonb);
 return jsonb_build_object('section',p_section,'rows',rows,'nextCursor',case when jsonb_array_length(rows)=100 then rows->99->>'id' else null end,
   'generatedAt',now(),'version',1);
end $$;
revoke all on function public.export_my_data(text,uuid) from public,anon;
grant execute on function public.export_my_data(text,uuid) to authenticated;
