-- get a list of security definer functions owned by powerbase_admin
-- this list should be vetted to ensure the functions are safe to use as security definer
select
    n.nspname, p.proname
from pg_catalog.pg_proc p
    left join pg_catalog.pg_namespace n ON n.oid = p.pronamespace
where p.proowner = (select oid from pg_catalog.pg_roles where rolname = 'powerbase_admin')
        and p.prosecdef = true
order by 1,2;
