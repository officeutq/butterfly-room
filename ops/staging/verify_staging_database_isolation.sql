\set ON_ERROR_STOP on

-- Run as an authorized database administrator while initially connected to postgres.
-- This script is read-only. Review any unexpected true/false result before proceeding.

\echo 'Checking staging role existence and role attributes.'

SELECT EXISTS (
  SELECT 1
  FROM pg_roles
  WHERE rolname = 'butterfly_room_staging_user'
) AS staging_role_exists;

SELECT
  rolname,
  rolsuper,
  rolcreatedb,
  rolcreaterole,
  rolreplication,
  NOT (rolsuper OR rolcreatedb OR rolcreaterole OR rolreplication) AS restricted_attributes_ok
FROM pg_roles
WHERE rolname = 'butterfly_room_staging_user';

\echo 'Checking staging database ownership.'

SELECT
  EXISTS (
    SELECT 1
    FROM pg_database
    WHERE datname = 'butterfly_room_staging'
  ) AS staging_database_exists,
  COALESCE(
    (
      SELECT pg_get_userbyid(datdba) = 'butterfly_room_staging_user'
      FROM pg_database
      WHERE datname = 'butterfly_room_staging'
    ),
    false
  ) AS staging_owner_is_staging_user;

\echo 'Checking CONNECT privileges for staging and production databases.'

WITH target_role AS (
  SELECT oid
  FROM pg_roles
  WHERE rolname = 'butterfly_room_staging_user'
), target_databases(database_name) AS (
  VALUES
    ('butterfly_room_staging'::name),
    ('butterfly_room_production'::name)
)
SELECT
  target_databases.database_name,
  pg_database.oid IS NOT NULL AS database_exists,
  COALESCE(
    has_database_privilege(target_role.oid, pg_database.oid, 'CONNECT'),
    false
  ) AS can_connect
FROM target_databases
LEFT JOIN pg_database
  ON pg_database.datname = target_databases.database_name
LEFT JOIN target_role
  ON true
ORDER BY target_databases.database_name;

\connect butterfly_room_production

\echo 'Checking effective privileges on the production public schema.'

WITH target_oids AS (
  SELECT
    (
      SELECT oid
      FROM pg_roles
      WHERE rolname = 'butterfly_room_staging_user'
    ) AS role_oid,
    (
      SELECT oid
      FROM pg_namespace
      WHERE nspname = 'public'
    ) AS schema_oid
)
SELECT
  COALESCE(
    has_schema_privilege(role_oid, schema_oid, 'USAGE'),
    false
  ) AS can_use_production_public_schema,
  COALESCE(
    has_schema_privilege(role_oid, schema_oid, 'CREATE'),
    false
  ) AS can_create_in_production_public_schema
FROM target_oids;

\echo 'Summarizing effective DML privileges on production tables.'

WITH target_role AS (
  SELECT oid
  FROM pg_roles
  WHERE rolname = 'butterfly_room_staging_user'
), production_tables AS (
  SELECT
    pg_class.oid,
    pg_namespace.nspname AS schema_name,
    pg_class.relname AS table_name
  FROM pg_class
  JOIN pg_namespace
    ON pg_namespace.oid = pg_class.relnamespace
  WHERE pg_class.relkind IN ('r', 'p', 'v', 'm', 'f')
    AND pg_namespace.nspname <> 'information_schema'
    AND pg_namespace.nspname !~ '^pg_'
), effective_privileges AS (
  SELECT
    production_tables.schema_name,
    production_tables.table_name,
    COALESCE(
      has_table_privilege(target_role.oid, production_tables.oid, 'SELECT')
        OR has_any_column_privilege(target_role.oid, production_tables.oid, 'SELECT'),
      false
    ) AS can_select,
    COALESCE(
      has_table_privilege(target_role.oid, production_tables.oid, 'INSERT')
        OR has_any_column_privilege(target_role.oid, production_tables.oid, 'INSERT'),
      false
    ) AS can_insert,
    COALESCE(
      has_table_privilege(target_role.oid, production_tables.oid, 'UPDATE')
        OR has_any_column_privilege(target_role.oid, production_tables.oid, 'UPDATE'),
      false
    ) AS can_update,
    COALESCE(has_table_privilege(target_role.oid, production_tables.oid, 'DELETE'), false) AS can_delete
  FROM production_tables
  LEFT JOIN target_role
    ON true
)
SELECT
  COUNT(*) AS checked_table_count,
  COUNT(*) FILTER (
    WHERE can_select OR can_insert OR can_update OR can_delete
  ) AS tables_with_dml_privileges,
  COUNT(*) FILTER (
    WHERE can_select OR can_insert OR can_update OR can_delete
  ) = 0 AS no_production_table_dml_privileges
FROM effective_privileges;

\echo 'Listing production tables with unexpected effective DML privileges, if any.'

WITH target_role AS (
  SELECT oid
  FROM pg_roles
  WHERE rolname = 'butterfly_room_staging_user'
), production_tables AS (
  SELECT
    pg_class.oid,
    pg_namespace.nspname AS schema_name,
    pg_class.relname AS table_name
  FROM pg_class
  JOIN pg_namespace
    ON pg_namespace.oid = pg_class.relnamespace
  WHERE pg_class.relkind IN ('r', 'p', 'v', 'm', 'f')
    AND pg_namespace.nspname <> 'information_schema'
    AND pg_namespace.nspname !~ '^pg_'
), effective_privileges AS (
  SELECT
    production_tables.schema_name,
    production_tables.table_name,
    COALESCE(
      has_table_privilege(target_role.oid, production_tables.oid, 'SELECT')
        OR has_any_column_privilege(target_role.oid, production_tables.oid, 'SELECT'),
      false
    ) AS can_select,
    COALESCE(
      has_table_privilege(target_role.oid, production_tables.oid, 'INSERT')
        OR has_any_column_privilege(target_role.oid, production_tables.oid, 'INSERT'),
      false
    ) AS can_insert,
    COALESCE(
      has_table_privilege(target_role.oid, production_tables.oid, 'UPDATE')
        OR has_any_column_privilege(target_role.oid, production_tables.oid, 'UPDATE'),
      false
    ) AS can_update,
    COALESCE(has_table_privilege(target_role.oid, production_tables.oid, 'DELETE'), false) AS can_delete
  FROM production_tables
  LEFT JOIN target_role
    ON true
)
SELECT
  schema_name,
  table_name,
  can_select,
  can_insert,
  can_update,
  can_delete
FROM effective_privileges
WHERE can_select OR can_insert OR can_update OR can_delete
ORDER BY schema_name, table_name;

\echo 'Isolation verification completed. Review all results; this script makes no changes.'
