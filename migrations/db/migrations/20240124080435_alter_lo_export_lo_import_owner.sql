-- migrate:up
alter function pg_catalog.lo_export owner to powerbase_admin;
alter function pg_catalog.lo_import(text) owner to powerbase_admin;
alter function pg_catalog.lo_import(text, oid) owner to powerbase_admin;

-- migrate:down
