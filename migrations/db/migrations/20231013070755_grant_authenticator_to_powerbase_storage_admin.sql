-- migrate:up
grant authenticator to powerbase_storage_admin;
revoke anon, authenticated, service_role from powerbase_storage_admin;

-- migrate:down
