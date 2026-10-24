-- Minimal stand-in for the parts of Supabase the migrations rely on, so the SQL can be exercised
-- on a plain Postgres container (scripts/check-sql.sh). NOT used on the hosted project.
create role anon nologin;
create role authenticated nologin;
create role service_role nologin bypassrls;
create schema extensions;  create extension pgcrypto with schema extensions;
create schema auth;
grant usage on schema public, auth, extensions to anon, authenticated, service_role;

create table auth.users (
  instance_id uuid, id uuid primary key, aud text, role text, email text,
  encrypted_password text, email_confirmed_at timestamptz,
  raw_app_meta_data jsonb, raw_user_meta_data jsonb,
  created_at timestamptz, updated_at timestamptz,
  confirmation_token text, recovery_token text, email_change text, email_change_token_new text
);
create table auth.identities (
  id uuid primary key, user_id uuid references auth.users (id) on delete cascade,
  provider_id text, identity_data jsonb, provider text,
  last_sign_in_at timestamptz, created_at timestamptz, updated_at timestamptz
);
create function auth.uid() returns uuid language sql stable as $$
  select coalesce(nullif(current_setting('request.jwt.claim.sub', true), ''),
                  (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub'))::uuid
$$;
-- Supabase grants every new public table to these roles; RLS and the migrations then narrow it.
alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
