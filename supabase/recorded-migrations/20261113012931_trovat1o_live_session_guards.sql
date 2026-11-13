-- Apply after the existing application modules; do not reapply schema.sql.
-- Supabase JWT signatures/expiry are checked by the API gateway. A signed JWT
-- may outlive logout, so ordinary authenticated data access also checks its
-- exact Auth session. No metadata claim supplies identity or permission here.
-- See https://supabase.com/docs/guides/auth/sessions and /auth/signout.
create or replace function public.has_live_session()
returns boolean language plpgsql stable security definer set search_path='' as $$
declare v_session uuid; v_user uuid:=(select auth.uid());
begin
  if v_user is null then return false; end if;
  begin v_session:=(auth.jwt()->>'session_id')::uuid;
  exception when invalid_text_representation then return false; end;
  if v_session is null then return false; end if;
  return exists(select 1 from auth.sessions s join auth.users u on u.id=s.user_id
    where s.id=v_session and s.user_id=v_user
      and (s.not_after is null or s.not_after>pg_catalog.now())
      and not coalesce(u.is_anonymous,false) and u.deleted_at is null
      and (u.banned_until is null or u.banned_until<=pg_catalog.now()));
end $$;
revoke all on function public.has_live_session() from public,anon,authenticated;
grant execute on function public.has_live_session() to authenticated;

-- Existing ordinary SECURITY DEFINER RPCs use these gates. Looking up the
-- live user/session also stops old tokens after bans and account deletion.
create or replace function public.is_email_confirmed()
returns boolean language sql stable security definer set search_path='' as $$
  select public.has_live_session() and exists(select 1 from auth.users u
    where u.id=(select auth.uid()) and u.email_confirmed_at is not null)
$$;
create or replace function public.is_google_verified()
returns boolean language sql stable security definer set search_path='' as $$
  select public.is_email_confirmed() and exists(select 1 from auth.identities i
    where i.user_id=(select auth.uid()) and i.provider='google'
      and i.identity_data->>'email_verified'='true')
$$;
create or replace function public.is_phone_verified()
returns boolean language sql stable security definer set search_path='' as $$
  select public.has_live_session() and exists(select 1 from public.profiles p
    where p.id=(select auth.uid()) and p.phone_verified_at is not null)
$$;
create or replace function public.is_event_member(p_event uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select public.has_live_session() and exists(select 1 from public.event_members m
    where m.event_id=p_event and m.user_id=(select auth.uid()) and m.state='approved')
$$;
create or replace function public.is_event_owner(p_event uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select public.has_live_session() and exists(select 1 from public.events e
    where e.id=p_event and e.creator_id=(select auth.uid()))
$$;
revoke all on function public.is_email_confirmed(),public.is_google_verified(),
  public.is_phone_verified(),public.is_event_member(uuid),public.is_event_owner(uuid) from public,anon;
grant execute on function public.is_email_confirmed(),public.is_google_verified(),
  public.is_phone_verified(),public.is_event_member(uuid),public.is_event_owner(uuid) to authenticated;

-- Restrictive policies AND with existing ownership/history rules. In
-- particular, self-row policies must not accept a revoked but unexpired JWT.
-- Unconfirmed email accounts keep their own profile/preferences access while
-- their real session is live. Service role BYPASSRLS and trusted jobs retain
-- their existing narrow grants and do not require a user session.
do $$ declare v_table text; begin
  foreach v_table in array array['profiles','subscriptions','event_members',
    'event_host_contacts','event_invites','pin_suggestions','player_reports',
    'notification_preferences','push_subscriptions','app_notifications'] loop
    execute pg_catalog.format('drop policy if exists require_live_session on public.%I',v_table);
    execute pg_catalog.format('create policy require_live_session on public.%I as restrictive for all to authenticated using ((select public.has_live_session())) with check ((select public.has_live_session()))',v_table);
  end loop;
end $$;

-- event_feed retains its anonymous public path and its authenticated
-- is_email_confirmed gate. get_event_invitation remains a masked bearer-link
-- preview for anon/authenticated, not authority to join or read a roster.
-- No client gains access to auth.sessions, private tables or service RPCs.
-- New READ COMMITTED statements observe a completed session revocation. This
-- is not cancellation of an in-flight statement or an old MVCC snapshot.
