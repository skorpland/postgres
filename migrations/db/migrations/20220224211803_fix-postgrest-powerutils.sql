-- migrate:up

-- Note: powertils extension is not installed in docker image.

DO $$
DECLARE
  powerutils_exists boolean;
BEGIN
  powerutils_exists = (
      select count(*) = 1
      from pg_available_extensions
      where name = 'powerutils'
  );

  IF powerutils_exists
  THEN
  ALTER ROLE authenticator SET session_preload_libraries = powerutils, safeupdate;
  END IF;
END $$;

-- migrate:down
