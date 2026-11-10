create index if not exists pin_suggestions_event_idx on public.pin_suggestions(event_id,created_at desc);
create index if not exists pin_suggestions_user_idx on public.pin_suggestions(user_id,created_at desc);
create index if not exists player_reports_event_idx on public.player_reports(event_id,created_at desc);
create index if not exists player_reports_reporter_idx on public.player_reports(reporter_id,created_at desc);
create index if not exists player_reports_subject_idx on public.player_reports(subject_id,created_at desc);
create index if not exists support_requests_requester_idx on public.support_requests(requester_user_id,created_at desc);
create index if not exists support_request_audit_ticket_idx on public.support_request_audit(ticket_id,created_at desc);
create index if not exists support_request_audit_actor_idx on public.support_request_audit(actor_id,created_at desc);
create or replace function public.is_support()
returns boolean language sql stable set search_path = '' as $$
  select coalesce((select auth.jwt()->'app_metadata'->>'role')='support',false)
$$;
revoke all on function public.is_event_member(uuid),public.is_event_owner(uuid),public.is_phone_verified() from anon;
create policy verified_phones_deny_clients on public.verified_phones for all to anon,authenticated using (false) with check (false);
create policy support_requests_deny_clients on public.support_requests for all to anon,authenticated using (false) with check (false);
create policy support_request_audit_deny_clients on public.support_request_audit for all to anon,authenticated using (false) with check (false);
create policy support_submit_quota_deny_clients on public.support_submit_quota for all to anon,authenticated using (false) with check (false);
create policy phone_otp_quota_deny_clients on public.phone_otp_quota for all to anon,authenticated using (false) with check (false);
create policy phone_otp_pending_deny_clients on public.phone_otp_pending for all to anon,authenticated using (false) with check (false);