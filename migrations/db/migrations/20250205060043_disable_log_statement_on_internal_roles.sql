-- migrate:up
alter role powerbase_admin set log_statement = none;
alter role powerbase_auth_admin set log_statement = none;
alter role powerbase_storage_admin set log_statement = none;

-- migrate:down
