#!/usr/bin/env bash
# Runs once on first PostgreSQL container start (empty data volume).
# Creates least-privilege roles and databases for API, Keycloak, and LiteLLM.
set -euo pipefail

: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${DB_USER_API:?DB_USER_API is required}"
: "${DB_PASSWORD_API:?DB_PASSWORD_API is required}"
: "${DB_USER_KC:?DB_USER_KC is required}"
: "${DB_PASSWORD_KC:?DB_PASSWORD_KC is required}"
: "${DB_USER_LITELLM:?DB_USER_LITELLM is required}"
: "${DB_PASSWORD_LITELLM:?DB_PASSWORD_LITELLM is required}"

psql_admin() {
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" "$@"
}

create_or_update_role() {
    local role_name="$1"
    local role_password="$2"

    psql_admin --dbname postgres \
        --set role_name="$role_name" \
        --set role_password="$role_password" <<-'EOSQL'
SELECT format('CREATE ROLE %I LOGIN PASSWORD %L', :'role_name', :'role_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = :'role_name') \gexec
ALTER ROLE :"role_name" WITH LOGIN PASSWORD :'role_password';
EOSQL
}

create_database_if_missing() {
    local db_name="$1"
    local owner_name="$2"

    psql_admin --dbname postgres \
        --set db_name="$db_name" \
        --set owner_name="$owner_name" <<-'EOSQL'
SELECT format('CREATE DATABASE %I OWNER %I', :'db_name', :'owner_name')
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = :'db_name') \gexec
ALTER DATABASE :"db_name" OWNER TO :"owner_name";
EOSQL
}

grant_database_basics() {
    local db_name="$1"
    local owner_name="$2"

    psql_admin --dbname "$db_name" \
        --set db_name="$db_name" \
        --set owner_name="$owner_name" <<-'EOSQL'
ALTER SCHEMA public OWNER TO :"owner_name";
GRANT CONNECT, TEMPORARY ON DATABASE :"db_name" TO :"owner_name";
GRANT USAGE, CREATE ON SCHEMA public TO :"owner_name";
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO :"owner_name";
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO :"owner_name";
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO :"owner_name";
EOSQL
}

create_or_update_role "$DB_USER_API" "$DB_PASSWORD_API"
create_or_update_role "$DB_USER_KC" "$DB_PASSWORD_KC"
create_or_update_role "$DB_USER_LITELLM" "$DB_PASSWORD_LITELLM"

create_database_if_missing "$POSTGRES_DB" "$DB_USER_API"
create_database_if_missing "keycloak" "$DB_USER_KC"
create_database_if_missing "litellm" "$DB_USER_LITELLM"

psql_admin --dbname "$POSTGRES_DB" \
    --set db_name="$POSTGRES_DB" \
    --set api_user="$DB_USER_API" <<-'EOSQL'
CREATE EXTENSION IF NOT EXISTS vector;
ALTER SCHEMA public OWNER TO :"api_user";
GRANT CONNECT, TEMPORARY ON DATABASE :"db_name" TO :"api_user";
GRANT USAGE, CREATE ON SCHEMA public TO :"api_user";
EOSQL

grant_database_basics "keycloak" "$DB_USER_KC"
grant_database_basics "litellm" "$DB_USER_LITELLM"

echo "init-dbs.sh: databases and roles ready; pgvector enabled on ${POSTGRES_DB}."
