-- Isolated PostgreSQL 17 CI only. Never run on Supabase or a user database.
-- The driver creates a fresh random database on the loopback-only test service.
-- Auth/JWT/MFA are synthetic boundaries; no provider exchange is simulated.
do $$ begin
 if current_database() !~ '^trovat1o_ci_[a-f0-9]{12}$'
  or current_setting('trovat1o.isolated_fixture',true) is distinct from 'true'
  or current_setting('server_version_num')::integer not between 170000 and 179999
  or exists(select 1 from pg_namespace where nspname='auth') then
   raise exception 'isolated_postgres_fixture_required';end if;
end $$;
do $$ declare r text; b boolean; begin
 foreach r in array array['anon','authenticated','service_role'] loop
  b:=(r='service_role');
  if not exists(select 1 from pg_roles where rolname=r) then
   execute format('create role %I nologin nosuperuser %s',r,case when b then 'bypassrls' else 'nobypassrls' end);
  elsif exists(select 1 from pg_roles where rolname=r and (rolcanlogin or rolsuper or rolbypassrls<>b)) then
   raise exception 'unexpected_test_role';
  end if;
 end loop;
end $$;
create schema auth;
create schema extensions;
create extension pgcrypto with schema extensions;

create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text,
  email_confirmed_at timestamptz,
  raw_app_meta_data jsonb not null default '{}'::jsonb,
  raw_user_meta_data jsonb not null default '{}'::jsonb,
  is_anonymous boolean not null default false,
  banned_until timestamptz,
  deleted_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table auth.identities (
  id uuid primary key default gen_random_uuid(),
  provider_id text not null,
  user_id uuid not null references auth.users(id) on delete cascade,
  identity_data jsonb not null default '{}'::jsonb,
  provider text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique(provider_id,provider)
);
create table auth.mfa_factors (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  factor_type text not null,
  status text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create table auth.sessions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  factor_id uuid references auth.mfa_factors(id) on delete set null,
  aal text,
  not_after timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create function auth.jwt() returns jsonb language sql stable set search_path='' as $$
  select coalesce(nullif(pg_catalog.current_setting('request.jwt.claims',true),''),'{}')::jsonb
$$;
create function auth.uid() returns uuid language sql stable set search_path='' as $$
  select coalesce(nullif(pg_catalog.current_setting('request.jwt.claim.sub',true),''),auth.jwt()->>'sub')::uuid
$$;
create function auth.role() returns text language sql stable set search_path='' as $$
  select coalesce(nullif(pg_catalog.current_setting('request.jwt.claim.role',true),''),auth.jwt()->>'role')
$$;
grant usage on schema auth,public,extensions to anon,authenticated,service_role;
revoke all on all tables in schema auth from public,anon,authenticated;
grant execute on function auth.uid(),auth.jwt(),auth.role() to anon,authenticated,service_role;

-- Only the historical first migration's REVOKE needs this platform signature.
-- No event trigger is installed; application tables must enable their own RLS.
create function public.rls_auto_enable() returns event_trigger language plpgsql as $$begin null;end$$;
