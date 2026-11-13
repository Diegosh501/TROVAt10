-- Authenticated intake only. A ticket is not an erased/closed account.
-- Reuses the protected Admin support queue and its audit/update permissions.
alter table public.support_requests add column request_kind text not null default 'support'
  check(request_kind in ('support','account_erasure'));
create unique index support_one_open_erasure on public.support_requests(requester_user_id)
  where request_kind='account_erasure' and status not in ('resolved','closed');

create function public.my_account_erasure_request()
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=(select auth.uid()); result jsonb;
begin
  if not public.is_email_confirmed() then raise exception 'authentication_required' using errcode='PT401'; end if;
  select jsonb_build_object('id',r.id,'status',r.status,'requestedAt',r.created_at,
    'updatedAt',r.updated_at,'accountErased',false,'accessClosed',false) into result
    from public.support_requests r where r.requester_user_id=u and r.request_kind='account_erasure'
    order by r.created_at desc,r.id desc limit 1;
  return result;
end $$;

create function public.request_account_erasure(p_confirm boolean)
returns jsonb language plpgsql security definer set search_path='' as $$
declare u uuid:=(select auth.uid()); existing_id uuid; attempts integer;
begin
  if not public.is_email_confirmed() then raise exception 'authentication_required' using errcode='PT401'; end if;
  if p_confirm is distinct from true then raise exception 'confirmation_required' using errcode='22023'; end if;
  -- Same parent lock order as account retention. Only the caller supplies
  -- authority; no target user, email, plan or timestamp is accepted.
  perform 1 from auth.users where id=u for update;
  if not found or not public.has_live_session() then raise exception 'authentication_required' using errcode='PT401'; end if;
  perform 1 from public.profiles where id=u for update;
  if not found then raise exception 'profile_required' using errcode='PT401'; end if;
  select id into existing_id from public.support_requests where requester_user_id=u
    and request_kind='account_erasure' and status not in ('resolved','closed');
  if existing_id is null then
    select count(*) into attempts from public.support_requests where requester_user_id=u
      and request_kind='account_erasure' and created_at>now()-interval '24 hours';
    if attempts>=3 then raise exception 'request_rate_limited' using errcode='PT429'; end if;
    insert into public.support_requests(requester_user_id,request_kind,category,subject,details,created_at)
      values(u,'account_erasure','account','Richiesta cancellazione account',
        'Richiesta autenticata di cancellazione account. Verificare identità, partite condivise, acquisti e conservazione prima di chiudere accesso e cancellare dati.',clock_timestamp());
  end if;
  return public.my_account_erasure_request();
end $$;
revoke all on function public.my_account_erasure_request(),public.request_account_erasure(boolean) from public,anon;
grant execute on function public.my_account_erasure_request(),public.request_account_erasure(boolean) to authenticated;
-- No new FK: existing support requester SET NULL preserves the ticket and
-- existing retention hold protects open requests. No personal contacts copied.
-- Resolved/closed ticket status never asserts that Auth/Billing was deleted.
