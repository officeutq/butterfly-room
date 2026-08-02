\set ON_ERROR_STOP on

-- DANGER: THIS FILE CHANGES PRIVILEGES ON THE PRODUCTION DATABASE.
--
-- Run it only as a reviewed, manual operation from psql 18 while connected to
-- butterfly_room_production as the RDS master user postgres. Never invoke this
-- file from Terraform, deployment automation, Rails tasks, or EC2 User Data.
-- Existing sessions usually remain connected after REVOKE CONNECT, but every
-- new application connection can be affected. Check current production
-- connections and all application login roles before continuing.

DO $guard$
DECLARE
  production_owner text;
BEGIN
  IF current_database() <> 'butterfly_room_production' THEN
    RAISE EXCEPTION
      'Connect to butterfly_room_production before running this file (current: %)',
      current_database();
  END IF;

  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION
      'Run this file as the RDS master user postgres (current: %)',
      current_user;
  END IF;

  SELECT pg_get_userbyid(datdba)
    INTO production_owner
  FROM pg_database
  WHERE datname = 'butterfly_room_production';

  IF production_owner IS NULL THEN
    RAISE EXCEPTION 'butterfly_room_production does not exist';
  END IF;

  IF production_owner <> 'postgres' THEN
    RAISE EXCEPTION
      'Unexpected production database owner: % (expected postgres)',
      production_owner;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'butterfly_room_staging_user'
  ) THEN
    RAISE EXCEPTION 'butterfly_room_staging_user does not exist';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_roles WHERE rolname = 'rdsproxyadmin'
  ) THEN
    RAISE EXCEPTION 'rdsproxyadmin does not exist';
  END IF;

  IF NOT has_database_privilege(
    'postgres',
    'butterfly_room_production',
    'CONNECT'
  ) THEN
    RAISE EXCEPTION 'postgres cannot currently CONNECT to production';
  END IF;
END
$guard$;

\echo '=== BEFORE: production owner and ACL ==='
SELECT
  database.datname,
  pg_get_userbyid(database.datdba) AS owner,
  database.datacl
FROM pg_database database
WHERE database.datname = 'butterfly_room_production';

\echo '=== BEFORE: current production connections ==='
SELECT
  usename,
  application_name,
  client_addr,
  count(*) AS connections
FROM pg_stat_activity
WHERE datname = 'butterfly_room_production'
GROUP BY usename, application_name, client_addr
ORDER BY usename, application_name, client_addr;

\echo '=== BEFORE: login-capable roles ==='
SELECT rolname
FROM pg_roles
WHERE rolcanlogin
ORDER BY rolname;

\echo '=== BEFORE: relevant database privileges ==='
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
  ) AS rdsproxyadmin_connect,
  has_database_privilege(
    'butterfly_room_staging_user',
    'butterfly_room_production',
    'CONNECT'
  ) AS staging_connect,
  has_database_privilege(
    'butterfly_room_staging_user',
    'butterfly_room_production',
    'TEMPORARY'
  ) AS staging_temporary;

\echo 'STOP unless postgres is the confirmed production application role.'
\echo 'The next confirmation controls a production database privilege change.'
\prompt 'Type RESTRICT butterfly_room_production to continue: ' production_acl_confirmation
SELECT
  :'production_acl_confirmation' = 'RESTRICT butterfly_room_production'
    AS confirmed
\gset production_acl_

\if :production_acl_confirmed
  BEGIN;

  REVOKE CONNECT, TEMPORARY
    ON DATABASE butterfly_room_production
    FROM PUBLIC;

  GRANT CONNECT, TEMPORARY
    ON DATABASE butterfly_room_production
    TO postgres;

  GRANT CONNECT
    ON DATABASE butterfly_room_production
    TO rdsproxyadmin;

  COMMIT;

  \echo '=== AFTER: production owner and ACL ==='
  SELECT
    database.datname,
    pg_get_userbyid(database.datdba) AS owner,
    database.datacl
  FROM pg_database database
  WHERE database.datname = 'butterfly_room_production';

  \echo '=== AFTER: relevant database privileges ==='
  SELECT
    has_database_privilege(
      'butterfly_room_staging_user',
      'butterfly_room_production',
      'CONNECT'
    ) AS staging_connect,
    has_database_privilege(
      'butterfly_room_staging_user',
      'butterfly_room_production',
      'TEMPORARY'
    ) AS staging_temporary,
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

  \echo 'Expected: staging=false/false; postgres=true/true; rdsproxyadmin=true.'

  \echo '=== AFTER: production connections that must remain healthy ==='
  SELECT
    usename,
    application_name,
    client_addr,
    count(*) AS connections
  FROM pg_stat_activity
  WHERE datname = 'butterfly_room_production'
  GROUP BY usename, application_name, client_addr
  ORDER BY usename, application_name, client_addr;

  \echo 'Run a separate staging-user psql connection attempt; it must be rejected.'
\else
  \echo 'Confirmation did not match. No production privilege was changed.'
\endif
