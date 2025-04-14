-- migrate:up

DO $$
DECLARE
  pgsodium_exists boolean;
  vault_exists boolean;
BEGIN
  IF EXISTS (SELECT FROM pg_available_extensions WHERE name = 'powerbase_vault' AND default_version != '0.2.8') THEN
    CREATE EXTENSION IF NOT EXISTS powerbase_vault;

    -- for some reason extension custom scripts aren't run during AMI build, so
    -- we manually run it here
    GRANT USAGE ON SCHEMA vault TO postgres WITH GRANT OPTION;
    GRANT SELECT, DELETE ON vault.secrets, vault.decrypted_secrets TO postgres WITH GRANT OPTION;
    GRANT EXECUTE ON FUNCTION vault.create_secret, vault.update_secret, vault._crypto_aead_det_decrypt TO postgres WITH GRANT OPTION;
  ELSE
    pgsodium_exists = (
      select count(*) = 1 
      from pg_available_extensions 
      where name = 'pgsodium'
      and default_version in ('3.1.6', '3.1.7', '3.1.8', '3.1.9')
    );
    
    vault_exists = (
        select count(*) = 1 
        from pg_available_extensions 
        where name = 'powerbase_vault'
    );
  
    IF pgsodium_exists 
    THEN
      create extension if not exists pgsodium;
  
      grant pgsodium_keyiduser to postgres with admin option;
      grant pgsodium_keyholder to postgres with admin option;
      grant pgsodium_keymaker  to postgres with admin option;
  
      grant execute on function pgsodium.crypto_aead_det_decrypt(bytea, bytea, uuid, bytea) to service_role;
      grant execute on function pgsodium.crypto_aead_det_encrypt(bytea, bytea, uuid, bytea) to service_role;
      grant execute on function pgsodium.crypto_aead_det_keygen to service_role;
  
      IF vault_exists
      THEN
        create extension if not exists powerbase_vault;
      END IF;
    END IF;
  END IF;
END $$;

-- migrate:down
