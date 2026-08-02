\set ON_ERROR_STOP on

-- Read-only verification. Run as the RDS master user (postgres), initially
-- connected to the postgres database. This file intentionally contains no
-- CREATE, ALTER, GRANT, REVOKE, or DROP statements.

\echo '=== Staging role attributes ==='
SELECT
  rolname,
  rolcanlogin,
  rolsuper,
  rolcreatedb,
  rolcreaterole,
  rolreplication
FROM pg_roles
WHERE rolname = 'butterfly_room_staging_user';

\echo 'Expected: one row; LOGIN=true and all four elevated attributes=false.'

\echo '=== Database owners and database-level privileges ==='
SELECT
  database.datname,
  pg_get_userbyid(database.datdba) AS owner,
  database.datacl
FROM pg_database database
WHERE database.datname IN (
  'butterfly_room_staging',
  'butterfly_room_production'
)
ORDER BY database.datname;

SELECT
  has_database_privilege(
    'butterfly_room_staging_user',
    'butterfly_room_staging',
    'CONNECT'
  ) AS staging_connect,
  has_database_privilege(
    'butterfly_room_staging_user',
    'butterfly_room_staging',
    'TEMPORARY'
  ) AS staging_temporary,
  has_database_privilege(
    'butterfly_room_staging_user',
    'butterfly_room_production',
    'CONNECT'
  ) AS production_connect,
  has_database_privilege(
    'butterfly_room_staging_user',
    'butterfly_room_production',
    'TEMPORARY'
  ) AS production_temporary,
  has_database_privilege(
    'butterfly_room_staging_user',
    'butterfly_room_production',
    'CREATE'
  ) AS production_create;

\echo 'Expected: staging CONNECT/TEMPORARY=true; production all=false.'

\echo '=== Production access retained for required service roles ==='
SELECT
  has_database_privilege(
    'postgres',
    'butterfly_room_production',
    'CONNECT'
  ) AS postgres_connect,
  has_database_privilege(
    'postgres',
    'butterfly_room_production',
    'TEMPORARY'
  ) AS postgres_temporary,
  has_database_privilege(
    'rdsproxyadmin',
    'butterfly_room_production',
    'CONNECT'
  ) AS rdsproxyadmin_connect;

\echo 'Expected: all three values=true.'

\echo '=== Temporary administrator membership cleanup ==='
SELECT
  current_user AS administrator,
  NOT EXISTS (
    SELECT 1
    FROM pg_auth_members membership
    JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
    JOIN pg_roles member_role ON member_role.oid = membership.member
    WHERE granted_role.rolname = 'butterfly_room_staging_user'
      AND member_role.rolname = current_user
  ) AS no_direct_membership_remains;

SELECT
  granted_role.rolname AS granted_role,
  member_role.rolname AS member_role,
  grantor_role.rolname AS grantor_role,
  membership.admin_option,
  membership.inherit_option,
  membership.set_option
FROM pg_auth_members membership
JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
JOIN pg_roles member_role ON member_role.oid = membership.member
JOIN pg_roles grantor_role ON grantor_role.oid = membership.grantor
WHERE granted_role.rolname = 'butterfly_room_staging_user'
ORDER BY member_role.rolname;

\echo 'Expected: no temporary postgres membership; investigate any unexpected row.'

\connect butterfly_room_staging

\echo '=== Staging public schema privileges ==='
SELECT
  schema_name,
  schema_owner,
  has_schema_privilege(
    'butterfly_room_staging_user',
    schema_name,
    'USAGE'
  ) AS staging_user_usage,
  has_schema_privilege(
    'butterfly_room_staging_user',
    schema_name,
    'CREATE'
  ) AS staging_user_create
FROM information_schema.schemata
WHERE schema_name = 'public';

\echo 'Expected: owner=butterfly_room_staging_user; USAGE/CREATE=true.'

\connect butterfly_room_production

\echo '=== Production public schema privileges ==='
SELECT
  schema_name,
  schema_owner,
  has_schema_privilege(
    'butterfly_room_staging_user',
    schema_name,
    'USAGE'
  ) AS staging_user_usage,
  has_schema_privilege(
    'butterfly_room_staging_user',
    schema_name,
    'CREATE'
  ) AS staging_user_create
FROM information_schema.schemata
WHERE schema_name = 'public';

\echo 'Review these values. Database CONNECT denial is the primary isolation boundary.'

\echo '=== Production table DML privileges ==='
WITH production_tables AS (
  SELECT
    table_class.oid,
    namespace.nspname AS schema_name,
    table_class.relname AS object_name
  FROM pg_class table_class
  JOIN pg_namespace namespace ON namespace.oid = table_class.relnamespace
  WHERE table_class.relkind IN ('r', 'p', 'v', 'm', 'f')
    AND namespace.nspname NOT IN ('pg_catalog', 'information_schema')
    AND namespace.nspname !~ '^pg_toast'
), privilege_checks AS (
  SELECT
    schema_name,
    object_name,
    privilege_name,
    has_table_privilege(
      'butterfly_room_staging_user',
      oid,
      privilege_name
    ) AS allowed
  FROM production_tables
  CROSS JOIN (
    VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')
  ) AS privileges(privilege_name)
)
SELECT
  count(*) FILTER (WHERE allowed) AS granted_checks,
  count(*) AS total_checks,
  COALESCE(bool_and(NOT allowed), true) AS no_table_dml_privileges
FROM privilege_checks;

WITH production_tables AS (
  SELECT
    table_class.oid,
    namespace.nspname AS schema_name,
    table_class.relname AS object_name
  FROM pg_class table_class
  JOIN pg_namespace namespace ON namespace.oid = table_class.relnamespace
  WHERE table_class.relkind IN ('r', 'p', 'v', 'm', 'f')
    AND namespace.nspname NOT IN ('pg_catalog', 'information_schema')
    AND namespace.nspname !~ '^pg_toast'
), privilege_checks AS (
  SELECT
    schema_name,
    object_name,
    privilege_name,
    has_table_privilege(
      'butterfly_room_staging_user',
      oid,
      privilege_name
    ) AS allowed
  FROM production_tables
  CROSS JOIN (
    VALUES ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE')
  ) AS privileges(privilege_name)
)
SELECT
  schema_name,
  object_name,
  privilege_name
FROM privilege_checks
WHERE allowed
ORDER BY schema_name, object_name, privilege_name;

\echo 'Expected: granted_checks=0, no_table_dml_privileges=true, and zero detail rows.'

\echo '=== Production sequence privileges ==='
WITH production_sequences AS (
  SELECT
    sequence_class.oid,
    namespace.nspname AS schema_name,
    sequence_class.relname AS object_name
  FROM pg_class sequence_class
  JOIN pg_namespace namespace ON namespace.oid = sequence_class.relnamespace
  WHERE sequence_class.relkind = 'S'
    AND namespace.nspname NOT IN ('pg_catalog', 'information_schema')
    AND namespace.nspname !~ '^pg_toast'
), privilege_checks AS (
  SELECT
    schema_name,
    object_name,
    privilege_name,
    has_sequence_privilege(
      'butterfly_room_staging_user',
      oid,
      privilege_name
    ) AS allowed
  FROM production_sequences
  CROSS JOIN (
    VALUES ('USAGE'), ('SELECT'), ('UPDATE')
  ) AS privileges(privilege_name)
)
SELECT
  count(*) FILTER (WHERE allowed) AS granted_checks,
  count(*) AS total_checks,
  COALESCE(bool_and(NOT allowed), true) AS no_sequence_privileges
FROM privilege_checks;

WITH production_sequences AS (
  SELECT
    sequence_class.oid,
    namespace.nspname AS schema_name,
    sequence_class.relname AS object_name
  FROM pg_class sequence_class
  JOIN pg_namespace namespace ON namespace.oid = sequence_class.relnamespace
  WHERE sequence_class.relkind = 'S'
    AND namespace.nspname NOT IN ('pg_catalog', 'information_schema')
    AND namespace.nspname !~ '^pg_toast'
), privilege_checks AS (
  SELECT
    schema_name,
    object_name,
    privilege_name,
    has_sequence_privilege(
      'butterfly_room_staging_user',
      oid,
      privilege_name
    ) AS allowed
  FROM production_sequences
  CROSS JOIN (
    VALUES ('USAGE'), ('SELECT'), ('UPDATE')
  ) AS privileges(privilege_name)
)
SELECT
  schema_name,
  object_name,
  privilege_name
FROM privilege_checks
WHERE allowed
ORDER BY schema_name, object_name, privilege_name;

\echo 'Expected: granted_checks=0, no_sequence_privileges=true, and zero detail rows.'

\echo '=== Production function and procedure EXECUTE privileges ==='
WITH production_routines AS (
  SELECT
    routine.oid,
    namespace.nspname AS schema_name,
    routine.proname AS object_name,
    pg_get_function_identity_arguments(routine.oid) AS identity_arguments
  FROM pg_proc routine
  JOIN pg_namespace namespace ON namespace.oid = routine.pronamespace
  WHERE namespace.nspname NOT IN ('pg_catalog', 'information_schema')
    AND namespace.nspname !~ '^pg_toast'
), privilege_checks AS (
  SELECT
    schema_name,
    object_name,
    identity_arguments,
    has_function_privilege(
      'butterfly_room_staging_user',
      oid,
      'EXECUTE'
    ) AS allowed
  FROM production_routines
)
SELECT
  count(*) FILTER (WHERE allowed) AS granted_checks,
  count(*) AS total_checks,
  COALESCE(bool_and(NOT allowed), true) AS no_routine_execute_privileges
FROM privilege_checks;

WITH production_routines AS (
  SELECT
    routine.oid,
    namespace.nspname AS schema_name,
    routine.proname AS object_name,
    pg_get_function_identity_arguments(routine.oid) AS identity_arguments
  FROM pg_proc routine
  JOIN pg_namespace namespace ON namespace.oid = routine.pronamespace
  WHERE namespace.nspname NOT IN ('pg_catalog', 'information_schema')
    AND namespace.nspname !~ '^pg_toast'
), privilege_checks AS (
  SELECT
    schema_name,
    object_name,
    identity_arguments,
    has_function_privilege(
      'butterfly_room_staging_user',
      oid,
      'EXECUTE'
    ) AS allowed
  FROM production_routines
)
SELECT
  schema_name,
  object_name,
  identity_arguments
FROM privilege_checks
WHERE allowed
ORDER BY schema_name, object_name, identity_arguments;

\echo 'Expected: granted_checks=0 and no_routine_execute_privileges=true.'
\echo 'PostgreSQL may grant EXECUTE to PUBLIC by default; report unexpected rows for human review.'

\echo 'Read-only staging database isolation verification completed.'
