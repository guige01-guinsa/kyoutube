\set ON_ERROR_STOP on
-- Use only in a newly-created disposable local database, never production.
create schema auth;
create table auth.users(id uuid primary key);
create function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub',true),'')::uuid
$$;
create function auth.role() returns text language sql stable as $$
  select current_setting('request.jwt.claim.role',true)
$$;
create function auth.jwt() returns jsonb language sql stable as $$ select '{}'::jsonb $$;
grant usage on schema auth to anon,authenticated,service_role;
create table public.profiles(id uuid primary key references auth.users(id) on delete cascade, role text not null);
create table public.ai_usage_reservations(
  id uuid primary key default gen_random_uuid(), user_id uuid references auth.users(id),
  endpoint text,plan_code text,status text,model text,request_tokens integer default 0,
  response_tokens integer default 0,created_at timestamptz default now(),completed_at timestamptz
);
