#! /usr/bin/env bash

## This script is run on the newly launched instance which is to be promoted to
## become the primary database instance once the upgrade successfully completes.
## The following commands copy custom PG configs and enable previously disabled
## extensions, containing regtypes referencing system OIDs.

set -eEuo pipefail

SCRIPT_DIR=$(dirname -- "$0";)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

IS_CI=${IS_CI:-}
LOG_FILE="/var/log/pg-upgrade-complete.log"

function cleanup {
    UPGRADE_STATUS=${1:-"failed"}
    EXIT_CODE=${?:-0}

    echo "$UPGRADE_STATUS" > /tmp/pg-upgrade-status

    ship_logs "$LOG_FILE" || true

    exit "$EXIT_CODE"
}

function execute_extension_upgrade_patches {
    if [ -f "/var/lib/postgresql/extension/wrappers--0.3.1--0.4.1.sql" ] && [ ! -f "/usr/share/postgresql/15/extension/wrappers--0.3.0--0.4.1.sql" ]; then
        cp /var/lib/postgresql/extension/wrappers--0.3.1--0.4.1.sql /var/lib/postgresql/extension/wrappers--0.3.0--0.4.1.sql
        ln -s /var/lib/postgresql/extension/wrappers--0.3.0--0.4.1.sql /usr/share/postgresql/15/extension/wrappers--0.3.0--0.4.1.sql
    fi
}

function execute_wrappers_patch {
    # If upgrading to pgsodium-less Vault, Wrappers need to be updated so that
    # foreign servers use `vault.secrets.id` instead of `vault.secrets.key_id`
    UPDATE_WRAPPERS_SERVER_OPTIONS_QUERY=$(cat <<EOF
  DO \$\$
  DECLARE
    server_rec RECORD;
    option_rec RECORD;
    vault_secrets RECORD;
  BEGIN
    IF EXISTS (SELECT FROM pg_extension WHERE extname = 'wrappers')
      AND EXISTS (SELECT FROM pg_available_extension_versions WHERE name = 'wrappers' AND version NOT IN (
      '0.1.0',
      '0.1.1',
      '0.1.4',
      '0.1.5',
      '0.1.6',
      '0.1.7',
      '0.1.8',
      '0.1.9',
      '0.1.10',
      '0.1.11',
      '0.1.12',
      '0.1.14',
      '0.1.15',
      '0.1.16',
      '0.1.17',
      '0.1.18',
      '0.1.19',
      '0.2.0',
      '0.3.0',
      '0.3.1',
      '0.4.0',
      '0.4.1',
      '0.4.2',
      '0.4.3',
      '0.4.4',
      '0.4.5'
    ))
    THEN
      FOR server_rec IN
        SELECT srvname, srvoptions
        FROM pg_foreign_server
      LOOP
        FOR option_rec IN
          SELECT split_part(srvoption, '=', 1) AS option_name, split_part(srvoption, '=', 2) AS option_value
          FROM UNNEST(server_rec.srvoptions) AS srvoption
        LOOP
          IF EXISTS (SELECT FROM vault.secrets WHERE option_rec.option_value IN (id::text, key_id::text)) THEN
            EXECUTE format(
              'ALTER SERVER %I OPTIONS (SET %I %L)',
              server_rec.srvname,
              option_rec.option_name,
              (SELECT id FROM vault.secrets WHERE option_rec.option_value IN (id::text, key_id::text))
            );
          END IF;
        END LOOP;
      END LOOP;
    END IF;
  END;
  \$\$;
EOF
    )
    run_sql -c "$UPDATE_WRAPPERS_SERVER_OPTIONS_QUERY"
}

function execute_patches {
    # Patch pg_net grants
    PG_NET_ENABLED=$(run_sql -A -t -c "select count(*) > 0 from pg_extension where extname = 'pg_net';")

    if [ "$PG_NET_ENABLED" = "t" ]; then
        PG_NET_GRANT_QUERY=$(cat <<EOF
        GRANT USAGE ON SCHEMA net TO powerbase_functions_admin, postgres, anon, authenticated, service_role;

        ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;
        ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SECURITY DEFINER;

        ALTER function net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;
        ALTER function net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) SET search_path = net;

        REVOKE ALL ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;
        REVOKE ALL ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) FROM PUBLIC;

        GRANT EXECUTE ON FUNCTION net.http_get(url text, params jsonb, headers jsonb, timeout_milliseconds integer) TO powerbase_functions_admin, postgres, anon, authenticated, service_role;
        GRANT EXECUTE ON FUNCTION net.http_post(url text, body jsonb, params jsonb, headers jsonb, timeout_milliseconds integer) TO powerbase_functions_admin, postgres, anon, authenticated, service_role;
EOF
        )

        run_sql -c "$PG_NET_GRANT_QUERY"
    fi

    # Patching pg_cron ownership as it resets during upgrade
    HAS_PG_CRON_OWNED_BY_POSTGRES=$(run_sql -A -t -c "select count(*) > 0 from pg_extension where extname = 'pg_cron' and extowner::regrole::text = 'postgres';")

    if [ "$HAS_PG_CRON_OWNED_BY_POSTGRES" = "t" ]; then
        RECREATE_PG_CRON_QUERY=$(cat <<EOF
        begin;
        create temporary table cron_job as select * from cron.job;
        create temporary table cron_job_run_details as select * from cron.job_run_details;
        drop extension pg_cron;
        create extension pg_cron schema pg_catalog;
        insert into cron.job select * from cron_job;
        insert into cron.job_run_details select * from cron_job_run_details;
        select setval('cron.jobid_seq', coalesce(max(jobid), 0) + 1, false) from cron.job;
        select setval('cron.runid_seq', coalesce(max(runid), 0) + 1, false) from cron.job_run_details;
        update cron.job set username = 'postgres' where username = 'powerbase_admin';
        commit;
EOF
        )

        run_sql -c "$RECREATE_PG_CRON_QUERY"
    fi

    # Patching pgmq ownership as it resets during upgrade
    HAS_PGMQ=$(run_sql -A -t -c "select count(*) > 0 from pg_extension where extname = 'pgmq';")
    if [ "$HAS_PGMQ" = "t" ]; then
        PATCH_PGMQ_QUERY=$(cat <<EOF
        do \$\$
        declare
            tbl record;
            seq_name text;
            new_seq_name text;
            archive_table_name text;
        begin
            -- Loop through each table in the pgmq schema starting with 'q_'
            -- Rebuild the pkey column's default to avoid pg_dumpall segfaults
            for tbl in
                select c.relname as table_name
                from pg_catalog.pg_attribute a
                join pg_catalog.pg_class c on c.oid = a.attrelid
                join pg_catalog.pg_namespace n on n.oid = c.relnamespace
                where n.nspname = 'pgmq'
                    and c.relname like 'q_%'
                    and a.attname = 'msg_id'
                    and a.attidentity in ('a', 'd') -- 'a' for ALWAYS, 'd' for BY DEFAULT
            loop
                -- Check if msg_id is an IDENTITY column for idempotency
                -- Define sequence names
                seq_name := 'pgmq.' || format ('"%s_msg_id_seq"', tbl.table_name);
                new_seq_name := 'pgmq.' || format ('"%s_msg_id_seq2"', tbl.table_name);
                archive_table_name := regexp_replace(tbl.table_name, '^q_', 'a_');
                -- Execute dynamic SQL to perform the required operations
                execute format('
                    create sequence %s;
                    select setval(''%s'', nextval(''%s''));
                    alter table %s."%s" alter column msg_id drop identity;
                    alter table %s."%s" alter column msg_id set default nextval(''%s'');
                    alter sequence %s rename to "%s";',
                    -- Parameters for format placeholders
                    new_seq_name,
                    new_seq_name, seq_name,
                    'pgmq', tbl.table_name,
                    'pgmq', tbl.table_name,
                    new_seq_name,
                    -- alter seq
                    new_seq_name, 
                    tbl.table_name || '_msg_id_seq'
                );
            end loop;
            -- No tables should be owned by the extension.
            -- We want them to be included in logical backups
            for tbl in
                select c.relname as table_name
                from pg_class c
                join pg_depend d
                    on c.oid = d.objid
                join pg_extension e
                    on d.refobjid = e.oid
                where 
                c.relkind in ('r', 'p', 'u')
                and e.extname = 'pgmq'
                and (c.relname like 'q_%' or c.relname like 'a_%')
            loop
            execute format('
                alter extension pgmq drop table pgmq."%s";',
                tbl.table_name
            );
            end loop;
        end \$\$;
EOF
        )

        run_sql -c "$PATCH_PGMQ_QUERY"
        run_sql -c "update pg_extension set extowner = 'postgres'::regrole where extname = 'pgmq';"
    fi

    # Patch to handle upgrading to pgsodium-less Vault
    REENCRYPT_VAULT_SECRETS_QUERY=$(cat <<EOF
    DO \$\$
    BEGIN
      IF EXISTS (SELECT FROM pg_available_extension_versions WHERE name = 'powerbase_vault' AND version = '0.3.0')
        AND EXISTS (SELECT FROM pg_extension WHERE extname = 'powerbase_vault')
      THEN
        IF (SELECT extversion FROM pg_extension WHERE extname = 'powerbase_vault') != '0.2.8' THEN
          GRANT USAGE ON SCHEMA vault TO postgres WITH GRANT OPTION;
          GRANT SELECT, DELETE ON vault.secrets, vault.decrypted_secrets TO postgres WITH GRANT OPTION;
          GRANT EXECUTE ON FUNCTION vault.create_secret, vault.update_secret, vault._crypto_aead_det_decrypt TO postgres WITH GRANT OPTION;
        END IF;
        -- Do an explicit IF EXISTS check to avoid referencing pgsodium objects if the project already migrated away from using pgsodium.
        IF EXISTS (SELECT FROM vault.secrets WHERE key_id IS NOT NULL) THEN
          UPDATE vault.secrets s
          SET
            secret = encode(
              vault._crypto_aead_det_encrypt(
                message := pgsodium.crypto_aead_det_decrypt(decode(s.secret, 'base64'), convert_to(s.id || s.description || s.created_at || s.updated_at, 'utf8'), s.key_id, s.nonce),
                additional := convert_to(s.id::text, 'utf8'),
                key_id := 0,
                context := 'pgsodium'::bytea,
                nonce := s.nonce
              ),
              'base64'
            ),
            key_id = NULL
          WHERE
            key_id IS NOT NULL;
        END IF;
      END IF;
    END
    \$\$;
EOF
    )
    run_sql -c "$REENCRYPT_VAULT_SECRETS_QUERY"

    run_sql -c "grant pg_read_all_data, pg_signal_backend to postgres"
}

function complete_pg_upgrade {
    if [ -f /tmp/pg-upgrade-status ]; then
        echo "Upgrade job already started. Bailing."
        exit 0
    fi

    echo "running" > /tmp/pg-upgrade-status

    echo "1. Mounting data disk"
    if [ -z "$IS_CI" ]; then
        retry 8 mount -a -v
    else
        echo "Skipping mount -a -v"
    fi

    # copying custom configurations
    echo "2. Copying custom configurations"
    retry 3 copy_configs

    echo "3. Starting postgresql"
    if [ -z "$IS_CI" ]; then
        retry 3 service postgresql start
    else
        CI_start_postgres --new-bin
    fi

    execute_extension_upgrade_patches || true

    # For this to work we need `vault.secrets` from the old project to be
    # preserved, but `run_generated_sql` includes `ALTER EXTENSION
    # powerbase_vault UPDATE` which modifies that. So we need to run it
    # beforehand.
    echo "3.1. Patch Wrappers server options"
    execute_wrappers_patch

    echo "4. Running generated SQL files"
    retry 3 run_generated_sql

    echo "4.1. Applying patches"
    execute_patches || true

    run_sql -c "ALTER USER postgres WITH NOSUPERUSER;"

    echo "4.2. Applying authentication scheme updates"
    retry 3 apply_auth_scheme_updates

    sleep 5

    echo "5. Restarting postgresql"
    if [ -z "$IS_CI" ]; then
        retry 3 service postgresql restart
        
        echo "5.1. Restarting gotrue and postgrest"
        retry 3 service gotrue restart
        retry 3 service postgrest restart
    else
        retry 3 CI_stop_postgres || true
        retry 3 CI_start_postgres
    fi

    echo "6. Starting vacuum analyze"
    retry 3 start_vacuum_analyze
}

function copy_configs {
    cp -R /data/conf/* /etc/postgresql-custom/
    chown -R postgres:postgres /var/lib/postgresql/data
    chown -R postgres:postgres /data/pgdata
    chmod -R 0750 /data/pgdata
}

function run_generated_sql {
    if [ -d /data/sql ]; then
        for FILE in /data/sql/*.sql; do
            if [ -f "$FILE" ]; then
                run_sql -f "$FILE" || true
            fi
        done
    fi
}

# Projects which had their passwords hashed using md5 need to have their passwords reset
# Passwords for managed roles are already present in /etc/postgresql.schema.sql
function apply_auth_scheme_updates {
    PASSWORD_ENCRYPTION_SETTING=$(run_sql -A -t -c "SHOW password_encryption;")
    if [ "$PASSWORD_ENCRYPTION_SETTING" = "md5" ]; then
        run_sql -c "ALTER SYSTEM SET password_encryption TO 'scram-sha-256';"
        run_sql -c "SELECT pg_reload_conf();"

        if [ -z "$IS_CI" ]; then
            run_sql -f /etc/postgresql.schema.sql
        fi
    fi
}

function start_vacuum_analyze {
    echo "complete" > /tmp/pg-upgrade-status

    # shellcheck disable=SC1091
    if [ -f "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh" ]; then
        # shellcheck disable=SC1091
        source "/nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh"
    fi
    vacuumdb --all --analyze-in-stages -U powerbase_admin -h localhost -p 5432
    echo "Upgrade job completed"
}

trap cleanup ERR

echo "C.UTF-8 UTF-8" > /etc/locale.gen
echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

if [ -z "$IS_CI" ]; then
    complete_pg_upgrade >> $LOG_FILE 2>&1 &
else 
    CI_stop_postgres || true

    rm -f /tmp/pg-upgrade-status
    mv /data_migration /data

    rm -rf /var/lib/postgresql/data
    ln -s /data/pgdata /var/lib/postgresql/data

    complete_pg_upgrade
fi
