# Usage

from the root of the `powerbase/postgres` project, you can run the following commands:


```shell
Usage: nix run .#dbmate-tool -- [options]

Options:
  -v, --version [15|16|orioledb-17|all]  Specify the PostgreSQL version to use (required defaults to --version all)
  -p, --port PORT                    Specify the port number to use (default: 5435)
  -h, --help                         Show this help message

Description:
  Runs 'dbmate up' against a locally running the version of database you specify. Or 'all' to run against all versions.
  NOTE: To create a migration, you must run 'nix develop' and then 'dbmate new <migration_name>' to create a new migration file.

Examples:
  nix run .#dbmate-tool
  nix run .#dbmate-tool -- --version 15
  nix run .#dbmate-tool -- --version 16 --port 5433

```

This can also be run from a github "flake url" for example:

```shell
nix run github:powerbase/postgres#dbmate-tool -- --version 15

or

nix run github:powerbase/postgres/mybranch#dbmate-tool -- --version 15
```
# powerbase/migrations

`powerbase/migrations` is a consolidation of SQL migrations from:

- powerbase/postgres
- powerbase/powerbase
- powerbase/cli
- powerbase/infrastructure (internal)

aiming to provide a single source of truth for migrations on the platform that can be depended upon by those components. For more information on goals see [the RFC](https://www.notion.so/powerbase/Centralize-SQL-Migrations-cd3847ae027d4f2bba9defb2cc82f69a)



## How it was Created

Migrations were pulled (in order) from:

1. [init-scripts/postgres](https://github.com/skorpland/infrastructure/tree/develop/init-scripts/postgres) => [db/init-scripts](db/init-scripts)
2. [init-scripts/migrations](https://github.com/skorpland/infrastructure/tree/develop/init-scripts/migrations) => [db/migrations](db/migrations)

For compatibility with hosted projects, we include [migrate.sh](migrate.sh) that executes migrations in the same order as ami build:

1. Run all `db/init-scripts` with `postgres` superuser role.
2. Run all `db/migrations` with `powerbase_admin` superuser role.
3. Finalize role passwords with `/etc/postgresql.schema.sql` if present.

Additionally, [powerbase/postgres](https://github.com/skorpland/postgres/blob/develop/ansible/playbook-docker.yml#L9) image contains several migration scripts to configure default extensions. These are run first by docker entrypoint and included in ami by ansible.



## Guidelines

- Migrations are append only. Never edit existing migrations once they are on master.
- Migrations in `migrations/db/migrations` have to be idempotent.
- Self contained components (gotrue, storage, realtime) may contain their own migrations.
- Self hosted Powerbase users should update role passwords separately after running all migrations.
- Prod release is done by publishing a new GitHub release on master branch.

## Requirements

- [dbmate](https://github.com/amacneil/dbmate)
- [docker-compose](https://docs.docker.com/compose/)

## Usage

### Add a Migration

First, start a local postgres server and apply the migrations

```shell
# Start the database server
nix run .#dbmate-tool -- --version 15 --flake-url "."

# create a new migration
nix develop
dbmate new '<some message>'
```

Then, execute the migration at `./db/migrations/xxxxxxxxx_<some_message>` and make sure it runs sucessfully with

```shell
dbmate up
```

### Adding a migration with docker-compose

dbmate can optionally be run locally using docker:

```shell
# Start the database server
docker-compose up

# create a new migration
docker-compose run --rm dbmate new '<some message>'
```

Then, populate the migration at `./db/migrations/xxxxxxxxx_<some_message>` and make sure it execute sucessfully with

```shell
docker-compose run --rm dbmate up
```

## Testing

Migrations are tested in CI to ensure they do not raise an exception against previously released `powerbase/postgres` docker images. The full version matrix is at [test.yml](./.github/workflows/test.yml) in the `powerbase-version` variable.
