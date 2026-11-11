-- Google creates an Auth identity first. The app then collects username, role
-- and explicit confirmations; no profile/privilege is inferred from Google name.
create or replace function public.create_profile_for_new_user()
returns trigger language plpgsql security definer set search_path = '' as $$
declare v_username text; v_role text; v_age timestamptz; v_terms_version text; v_privacy_version text;
begin
  if new.raw_app_meta_data->>'provider'='google' then return new; end if;
  v_username:=new.raw_user_meta_data->>'username';
  v_role:=case when new.raw_user_meta_data->>'role'='host' then 'host' else 'sportivo' end;
  if v_username is null or v_username !~ '^[A-Za-z0-9_.-]{3,24}$' then raise exception 'invalid username'; end if;
  if coalesce(new.raw_user_meta_data->>'age_confirmed','')<>'true' then raise exception 'adult confirmation required'; end if;
  v_terms_version:=new.raw_user_meta_data->>'terms_version';
  v_privacy_version:=new.raw_user_meta_data->>'privacy_notice_version';
  if coalesce(new.raw_user_meta_data->>'terms_accepted','')<>'true' or v_terms_version is null or v_privacy_version is null then
    raise exception 'terms and privacy notice required';
  end if;
  v_age:=pg_catalog.now();
  insert into public.profiles(id,username,role,age_confirmed_at,terms_accepted_at,privacy_notice_ack_at,terms_version,privacy_notice_version)
    values(new.id,v_username,v_role,v_age,v_age,v_age,v_terms_version,v_privacy_version);
  return new;
end $$;
revoke all on function public.create_profile_for_new_user() from public,anon,authenticated;

-- Existing write RPCs call this helper. An account blocked/deleted in Auth must
-- stop passing their gate even before an older access token expires.
create or replace function public.is_email_confirmed()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from auth.users u where u.id=(select auth.uid())
    and u.email_confirmed_at is not null and not coalesce(u.is_anonymous,false)
    and u.deleted_at is null and (u.banned_until is null or u.banned_until<=pg_catalog.now()))
$$;
revoke all on function public.is_email_confirmed() from public,anon;
grant execute on function public.is_email_confirmed() to authenticated;

create or replace function public.is_google_verified()
returns boolean language sql stable security definer set search_path = '' as $$
  select exists(select 1 from auth.users u join auth.identities i on i.user_id=u.id
    where u.id=(select auth.uid()) and u.email_confirmed_at is not null
      and not coalesce(u.is_anonymous,false) and u.deleted_at is null
      and (u.banned_until is null or u.banned_until<=pg_catalog.now())
      and i.provider='google' and i.identity_data->>'email_verified'='true')
$$;
revoke all on function public.is_google_verified() from public,anon;
grant execute on function public.is_google_verified() to authenticated;

create or replace function public.complete_my_profile(
  p_username text,p_role text,p_adult_confirmed boolean,p_terms_accepted boolean,p_privacy_acknowledged boolean
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare v_user uuid:=(select auth.uid()); v_profile public.profiles%rowtype;
begin
  if v_user is null or not public.is_google_verified() then
    raise exception 'google_identity_required' using errcode='42501';
  end if;
  if p_username is null or pg_catalog.btrim(p_username) !~ '^[A-Za-z0-9_.-]{3,24}$'
    or p_role is null or p_role not in ('host','sportivo') then
    raise exception 'invalid_profile' using errcode='22023';
  end if;
  if p_adult_confirmed is distinct from true or p_terms_accepted is distinct from true
    or p_privacy_acknowledged is distinct from true then
    raise exception 'profile_confirmations_required' using errcode='22023';
  end if;
  -- Serializes retries/two tabs of the same account. No arbitrary target UUID.
  perform pg_catalog.pg_advisory_xact_lock(82102026,pg_catalog.hashtext(v_user::text));
  select * into v_profile from public.profiles where id=v_user;
  if not found then
    insert into public.profiles(id,username,role,age_confirmed_at,terms_accepted_at,privacy_notice_ack_at,terms_version,privacy_notice_version)
      values(v_user,pg_catalog.btrim(p_username),p_role,pg_catalog.now(),pg_catalog.now(),pg_catalog.now(),
        'trovatio-2026-11-09-v1','trovatio-2026-11-09-v1') returning * into v_profile;
    insert into public.subscriptions(user_id,plan,status) values(v_user,'free','active') on conflict(user_id) do nothing;
  end if;
  -- Repeated completion is idempotent; it never overwrites a profile or plan.
  return pg_catalog.jsonb_build_object('id',v_profile.id,'username',v_profile.username,'role',v_profile.role,
    'age_confirmed_at',v_profile.age_confirmed_at,'phone_verified_at',v_profile.phone_verified_at);
end $$;
revoke all on function public.complete_my_profile(text,text,boolean,boolean,boolean) from public,anon;
grant execute on function public.complete_my_profile(text,text,boolean,boolean,boolean) to authenticated;


