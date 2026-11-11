-- Local PGlite-only approximation of the Supabase Auth boundary.
-- Application schema/functions/RLS are loaded unchanged after this fixture.
-- Identity creation, JWT verification, GoTrue, MFA exchanges and pg_cron are
-- not implemented here. Claims are synthetic PostgreSQL settings, as in the
-- existing staging regression scripts. Never apply this fixture to Supabase.
do $$ begin
  if pg_catalog.strpos(pg_catalog.version(),'PGlite')=0 then
    raise exception 'local_fixture_pglite_only';
  end if;
end $$;
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
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
