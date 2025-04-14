BEGIN;
SELECT plan(2);

-- the setting doesn't exist when powerutils is not loaded
SELECT throws_ok($$
  select current_setting('powerutils.privileged_extensions', false)
$$);

LOAD 'powerutils';

-- now it does
SELECT ok(
  current_setting('powerutils.privileged_extensions', false) = ''
);

SELECT * FROM finish();
ROLLBACK;
