-- Apply after session-security.sql and account-erasure-requests.sql.
-- A real CAPTCHA is verified by the Edge relay before this service-only write.
-- The transaction then rechecks Auth/session, quota and durable replay guards.
create table private.support_submission_receipts (
 user_id uuid not null references auth.users(id) on delete cascade,
 request_id uuid not null,
 payload_hash bytea not null check(octet_length(payload_hash)=32),
 ticket_id uuid not null references public.support_requests(id) on delete restrict,
 created_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null default clock_timestamp()+interval '24 hours',
 primary key(user_id,request_id),check(expires_at>created_at)
);
create index support_receipts_expiry_idx on private.support_submission_receipts(expires_at);
create index support_receipts_ticket_idx on private.support_submission_receipts(ticket_id);
create table private.support_captcha_redemptions (
 token_hash bytea primary key check(octet_length(token_hash)=32),
 user_id uuid references auth.users(id) on delete set null,
 request_id uuid not null,
 created_at timestamptz not null default clock_timestamp(),
 expires_at timestamptz not null default clock_timestamp()+interval '10 minutes',
 check(expires_at>created_at)
);
create index support_captcha_expiry_idx on private.support_captcha_redemptions(expires_at);
create index support_captcha_user_idx on private.support_captcha_redemptions(user_id);
alter table private.support_submission_receipts enable row level security;
alter table private.support_captcha_redemptions enable row level security;
revoke all on private.support_submission_receipts,private.support_captcha_redemptions from public,anon,authenticated,service_role;

create function public.authorize_support_submission()
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=(select auth.uid());s uuid;
begin
 if not public.is_email_confirmed() then raise exception 'unauthorized' using errcode='PT401';end if;
 begin s:=(auth.jwt()->>'session_id')::uuid;exception when invalid_text_representation then s:=null;end;
 if s is null then raise exception 'unauthorized' using errcode='PT401';end if;
 -- No can_play/account-lifecycle gate: a Free expiry must not remove support.
 return jsonb_build_object('user_id',u,'session_id',s);
end $$;
revoke all on function public.authorize_support_submission() from public,anon,authenticated;
grant execute on function public.authorize_support_submission() to authenticated;

create function public.submit_verified_support_request(
 p_user uuid,p_session uuid,p_request_id uuid,p_captcha_hash text,p_category text,p_subject text,p_details text,
 p_contact_allowed boolean,p_contact_name text,p_contact_email text,p_attach_account boolean
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
 v_now timestamptz:=clock_timestamp();v_day date;v_subject text:=btrim(p_subject);v_details text:=btrim(p_details);
 v_name text;v_email text;v_payload bytea;v_token bytea;v_ticket uuid;v_receipt private.support_submission_receipts%rowtype;
 v_count integer;v_window date;v_claimed boolean;
begin
 -- Consistent parent lock order serializes account revocation/deletion with
 -- this write. Statements already in flight may finish before a waiting logout.
 perform 1 from auth.users u where u.id=p_user and u.email_confirmed_at is not null
  and not coalesce(u.is_anonymous,false) and u.deleted_at is null
  and (u.banned_until is null or u.banned_until<=v_now) for share;
 if not found then raise exception 'unauthorized' using errcode='PT401';end if;
 perform 1 from auth.sessions s where s.id=p_session and s.user_id=p_user
  and (s.not_after is null or s.not_after>v_now) for share;
 if not found then raise exception 'unauthorized' using errcode='PT401';end if;
 if p_request_id is null or p_captcha_hash is null or p_captcha_hash!~'^[a-f0-9]{64}$'
  or p_category is null or p_category not in ('bug','account','event','safety','other')
  or v_subject is null or char_length(v_subject) not between 4 and 120
  or v_details is null or char_length(v_details) not between 20 and 4000
  or p_contact_allowed is null or p_attach_account is null then
  raise exception 'invalid_request' using errcode='22023';end if;
 if p_attach_account then
  perform 1 from public.profiles where id=p_user for share;
  if not found then raise exception 'profile_required' using errcode='PT403';end if;
 end if;
 if p_contact_allowed then
  v_name:=nullif(btrim(p_contact_name),'');v_email:=lower(btrim(p_contact_email));
  if coalesce(char_length(v_name),0)>80 or v_email is null or char_length(v_email)>254
   or v_email!~'^[^[:space:]@]+@[^[:space:]@]+\.[^[:space:]@]+$' then
   raise exception 'invalid_request' using errcode='22023';end if;
 end if;
 v_token:=decode(p_captcha_hash,'hex');
 v_payload:=extensions.digest(convert_to(jsonb_build_object('category',p_category,'subject',v_subject,'details',v_details,
  'contactAllowed',p_contact_allowed,'name',v_name,'email',v_email,'attachAccount',p_attach_account)::text,'UTF8'),'sha256');
 v_day:=(v_now at time zone 'UTC')::date;
 insert into public.support_submit_quota(user_id,window_day,submission_count) values(p_user,v_day,0) on conflict do nothing;
 select window_day,submission_count into v_window,v_count from public.support_submit_quota where user_id=p_user for update;
 if v_window<v_day then v_count:=0;elsif v_window>v_day then raise exception 'rate_limited' using errcode='PT429';end if;
 -- Opportunistic cleanup is bounded and does not delete tickets or accounts.
 delete from private.support_captcha_redemptions where token_hash in
  (select token_hash from private.support_captcha_redemptions where expires_at<=v_now order by expires_at limit 100 for update skip locked);
 delete from private.support_submission_receipts where (user_id,request_id) in
  (select user_id,request_id from private.support_submission_receipts where expires_at<=v_now order by expires_at limit 100 for update skip locked);
 delete from private.support_submission_receipts where user_id=p_user and request_id=p_request_id and expires_at<=v_now;
 select * into v_receipt from private.support_submission_receipts where user_id=p_user and request_id=p_request_id for update;
 if found and v_receipt.payload_hash<>v_payload then raise exception 'idempotency_conflict' using errcode='PT409';end if;
 if v_receipt.ticket_id is null and v_count>=5 then raise exception 'rate_limited' using errcode='PT429';end if;
 -- CAPTCHA redemption can be eventually consistent upstream. The local PK
 -- rejects the same token on another operation/user, including simultaneous calls.
 insert into private.support_captcha_redemptions(token_hash,user_id,request_id,created_at,expires_at)
  values(v_token,p_user,p_request_id,v_now,v_now+interval '10 minutes')
  on conflict(token_hash) do update set token_hash=excluded.token_hash
   where support_captcha_redemptions.user_id=excluded.user_id and support_captcha_redemptions.request_id=excluded.request_id
  returning true into v_claimed;
 if v_claimed is distinct from true then raise exception 'captcha_reused' using errcode='PT409';end if;
 if v_receipt.ticket_id is not null then return jsonb_build_object('ticketId',v_receipt.ticket_id,'reused',true);end if;
 insert into public.support_requests(requester_user_id,category,subject,details,contact_allowed,contact_name,contact_email)
  values(case when p_attach_account then p_user else null end,p_category,v_subject,v_details,p_contact_allowed,v_name,v_email)
  returning id into v_ticket;
 insert into private.support_submission_receipts(user_id,request_id,payload_hash,ticket_id,created_at,expires_at)
  values(p_user,p_request_id,v_payload,v_ticket,v_now,v_now+interval '24 hours');
 update public.support_submit_quota set window_day=v_day,submission_count=v_count+1 where user_id=p_user;
 return jsonb_build_object('ticketId',v_ticket,'reused',false);
end $$;
revoke all on function public.submit_verified_support_request(uuid,uuid,uuid,text,text,text,text,boolean,text,text,boolean) from public,anon,authenticated,service_role;
grant execute on function public.submit_verified_support_request(uuid,uuid,uuid,text,text,text,text,boolean,text,text,boolean) to service_role;

-- Reconcile the two explicit Auth FKs; unknown future cascades still block purge.
create or replace function private.account_deletion_dependencies_known()
returns boolean language sql stable security definer set search_path='' as $$
  with recursive targets(id) as (
    select 'auth.users'::regclass::oid union
    select c.conrelid from pg_catalog.pg_constraint c join targets t on c.confrelid=t.id
      where c.contype='f' and c.confdeltype='c'
  ), expected(parent,child,cols,action) as (values
    ('auth.users','public.profiles','id','c'),
    ('auth.users','public.support_request_audit','actor_id','a'),
    ('auth.users','public.support_submit_quota','user_id','c'),
    ('auth.users','private.support_submission_receipts','user_id','c'),
    ('auth.users','private.support_captcha_redemptions','user_id','n'),
    ('auth.users','private.platform_admins','user_id','c'),
    ('auth.users','private.admin_action_quota','user_id','c'),
    ('auth.users','private.admin_audit','actor_id','n'),
    ('auth.users','private.write_action_quotas','user_id','c'),
    ('public.profiles','public.verified_phones','user_id','c'),
    ('public.profiles','public.events','creator_id','a'),
    ('public.profiles','public.event_members','user_id','c'),
    ('public.profiles','public.pin_suggestions','user_id','a'),
    ('public.profiles','public.player_reports','reporter_id','a'),
    ('public.profiles','public.player_reports','subject_id','a'),
    ('public.profiles','public.support_requests','requester_user_id','n'),
    ('public.profiles','public.subscriptions','user_id','c'),
    ('public.profiles','public.phone_otp_quota','user_id','c'),
    ('public.profiles','public.phone_otp_pending','user_id','c'),
    ('public.profiles','public.notification_preferences','user_id','c'),
    ('public.profiles','public.push_subscriptions','user_id','c'),
    ('public.profiles','public.app_notifications','user_id','c'),
    ('public.profiles','public.notification_delivery_queue','user_id','c'),
    ('public.profiles','private.billing_accounts','user_id','c'),
    ('public.profiles','private.billing_quotas','user_id','c'),
    ('public.profiles','private.account_export_quota','user_id','c'),
    ('public.profiles','private.host_contact_quota','user_id','c'),
    ('public.profiles','private.account_lifecycle','user_id','c'),
    ('public.profiles','private.account_retention_holds','user_id','c'),
    ('private.billing_accounts','private.billing_states','user_id,mode','c'),
    ('private.billing_states','private.billing_invoices','mode,subscription_id','c'),
    ('private.billing_states','private.billing_holds','mode,subscription_id','c'),
    ('public.push_subscriptions','public.notification_delivery_queue','subscription_id','c'),
    ('public.app_notifications','public.notification_delivery_queue','notification_id','c')
  ) select not exists(select 1 from pg_catalog.pg_constraint c join targets t on t.id=c.confrelid
    join pg_catalog.pg_namespace ns on ns.oid=c.connamespace
    where c.contype='f' and ns.nspname<>'auth' and not exists(select 1 from expected e
      where pg_catalog.to_regclass(e.parent)=c.confrelid and pg_catalog.to_regclass(e.child)=c.conrelid
        and e.action=c.confdeltype::text and e.cols=(select string_agg(a.attname,',' order by k.n)
          from unnest(c.conkey) with ordinality k(num,n)
          join pg_catalog.pg_attribute a on a.attrelid=c.conrelid and a.attnum=k.num)))
$$;
revoke all on function private.account_deletion_dependencies_known() from public,anon,authenticated;

