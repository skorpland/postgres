-- migrate:up

-- update owner for auth.uid, auth.role and auth.email functions
DO $$
BEGIN
    ALTER FUNCTION auth.uid owner to powerbase_auth_admin;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Error encountered when changing owner of auth.uid to powerbase_auth_admin';
END $$;

DO $$
BEGIN
    ALTER FUNCTION auth.role owner to powerbase_auth_admin;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Error encountered when changing owner of auth.role to powerbase_auth_admin';
END $$;

DO $$
BEGIN
    ALTER FUNCTION auth.email owner to powerbase_auth_admin;
EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'Error encountered when changing owner of auth.email to powerbase_auth_admin';
END $$;
-- migrate:down
