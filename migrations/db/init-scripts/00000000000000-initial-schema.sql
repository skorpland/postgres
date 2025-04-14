-- migrate:up

-- Set up realtime
-- defaults to empty publication
create publication powerbase_realtime;

-- Powerbase super admin
alter user  powerbase_admin with superuser createdb createrole replication bypassrls;

-- Powerbase replication user
create user powerbase_replication_admin with login replication;

-- Powerbase read-only user
create role powerbase_read_only_user with login bypassrls;
grant pg_read_all_data to powerbase_read_only_user;

-- Extension namespacing
create schema if not exists extensions;
create extension if not exists "uuid-ossp"      with schema extensions;
create extension if not exists pgcrypto         with schema extensions;
do $$
begin 
    if exists (select 1 from pg_available_extensions where name = 'pgjwt') then
        if not exists (select 1 from pg_extension where extname = 'pgjwt') then
            create extension if not exists pgjwt with schema "extensions" cascade;
        end if;
    end if;
end $$;


-- Set up auth roles for the developer
create role anon                nologin noinherit;
create role authenticated       nologin noinherit; -- "logged in" user: web_user, app_user, etc
create role service_role        nologin noinherit bypassrls; -- allow developers to create JWT's that bypass their policies

create user authenticator noinherit;
grant anon              to authenticator;
grant authenticated     to authenticator;
grant service_role      to authenticator;
grant powerbase_admin    to authenticator;

grant usage                     on schema public to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on tables to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on functions to postgres, anon, authenticated, service_role;
alter default privileges in schema public grant all on sequences to postgres, anon, authenticated, service_role;

-- Allow Extensions to be used in the API
grant usage                     on schema extensions to postgres, anon, authenticated, service_role;

-- Set up namespacing
alter user powerbase_admin SET search_path TO public, extensions; -- don't include the "auth" schema

-- These are required so that the users receive grants whenever "powerbase_admin" creates tables/function
alter default privileges for user powerbase_admin in schema public grant all
    on sequences to postgres, anon, authenticated, service_role;
alter default privileges for user powerbase_admin in schema public grant all
    on tables to postgres, anon, authenticated, service_role;
alter default privileges for user powerbase_admin in schema public grant all
    on functions to postgres, anon, authenticated, service_role;

-- Set short statement/query timeouts for API roles
alter role anon set statement_timeout = '3s';
alter role authenticated set statement_timeout = '8s';

-- migrate:down
