-- pgbouncer schema owner
select
  n.nspname as schema_name,
  r.rolname as owner
from
  pg_namespace n
join
  pg_roles r on n.nspowner = r.oid
where
  n.nspname = 'pgbouncer';

-- pgbouncer schema functions with owners
select
  n.nspname as schema_name,
  p.proname as function_name,
  r.rolname as owner
from
  pg_proc p
join
  pg_namespace n on p.pronamespace = n.oid
join
  pg_roles r on p.proowner = r.oid
where
  n.nspname = 'pgbouncer'
order by
  p.proname;

-- Tests role privileges on the pgbouncer objects
WITH schema_obj AS ( 
  SELECT oid, nspname 
  FROM pg_namespace 
  WHERE nspname = 'pgbouncer' 
) 
SELECT 
  s.nspname AS schema, 
  c.relname AS object_name, 
  acl.grantee::regrole::text AS grantee, 
  acl.privilege_type 
FROM pg_class c 
JOIN schema_obj s ON s.oid = c.relnamespace 
CROSS JOIN LATERAL aclexplode(c.relacl) AS acl 
WHERE c.relkind IN ('r', 'v', 'm', 'f', 'p') 
  AND acl.privilege_type <> 'MAINTAIN' 
UNION ALL 
SELECT 
  s.nspname AS schema, 
  p.proname AS object_name, 
  acl.grantee::regrole::text AS grantee, 
  acl.privilege_type 
FROM pg_proc p 
JOIN schema_obj s ON s.oid = p.pronamespace 
CROSS JOIN LATERAL aclexplode(p.proacl) AS acl 
ORDER BY object_name, grantee, privilege_type;

-- Ensure that pgbouncer.get_auth() function does not return an expired password
create role test_expired_user_password with login password 'expired_password' valid until '2000-01-01 00:00:00+00';
create role test_valid_user_password with login password 'valid_password' valid until '2100-01-01 00:00:00+00';
-- Update the pg_authid catalog directly to replace with a known SCRAM hash
update pg_authid set rolpassword = 'SCRAM-SHA-256$4096:testsaltbase64$storedkeybase64$serverkeybase64' where rolname = 'test_valid_user_password';

select pgbouncer.get_auth('test_expired_user_password');

select pgbouncer.get_auth('test_valid_user_password');

drop role test_expired_user_password;
drop role test_valid_user_password;
