\set ON_ERROR_STOP on

-- Run this file as the RDS master user (postgres), connected to the postgres DB.
-- The password is entered only through psql's hidden-input \password command.
--
-- CREATE DATABASE ... OWNER requires the administrator to be able to SET ROLE
-- to the owner role. Amazon RDS's postgres user is not a PostgreSQL superuser,
-- so this script grants SET TRUE membership only when it is needed. It restores
-- the exact pre-existing direct-membership state after all owner operations.
--
-- CREATE DATABASE cannot run in a transaction. If this script stops before the
-- cleanup block, follow the recovery procedure in ops/staging/README.md before
-- running it again.

DO $guard$
BEGIN
  IF current_database() <> 'postgres' THEN
    RAISE EXCEPTION
      'Connect to the postgres database before running this script (current: %)',
      current_database();
  END IF;

  IF current_user <> 'postgres' THEN
    RAISE EXCEPTION
      'Run this script as the RDS master user postgres (current: %)',
      current_user;
  END IF;
END
$guard$;

SELECT format(
  'CREATE ROLE butterfly_room_staging_user LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION'
)
WHERE NOT EXISTS (
  SELECT 1
  FROM pg_roles
  WHERE rolname = 'butterfly_room_staging_user'
)
\gexec

ALTER ROLE butterfly_room_staging_user
  WITH LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

\echo 'Set or update the staging database password using hidden input.'
\echo 'psql may return directly to the prompt without printing a success message.'
\password butterfly_room_staging_user

DO $guard$
DECLARE
  database_owner text;
BEGIN
  SELECT pg_get_userbyid(datdba)
    INTO database_owner
  FROM pg_database
  WHERE datname = 'butterfly_room_staging';

  IF database_owner IS NOT NULL
     AND database_owner <> 'butterfly_room_staging_user' THEN
    RAISE EXCEPTION
      'Existing butterfly_room_staging owner is %, expected butterfly_room_staging_user',
      database_owner;
  END IF;
END
$guard$;

-- Save the state that must be restored after the owner operations. A direct
-- membership can exist with SET FALSE, while an indirect membership can still
-- make pg_has_role(..., 'SET') true; both cases are handled separately.
SELECT
  current_user AS administrator,
  pg_has_role(
    current_user,
    'butterfly_room_staging_user',
    'SET'
  ) AS can_set_role,
  EXISTS (
    SELECT 1
    FROM pg_auth_members membership
    JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
    JOIN pg_roles member_role ON member_role.oid = membership.member
    WHERE granted_role.rolname = 'butterfly_room_staging_user'
      AND member_role.rolname = current_user
  ) AS direct_membership_exists,
  COALESCE((
    SELECT membership.set_option
    FROM pg_auth_members membership
    JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
    JOIN pg_roles member_role ON member_role.oid = membership.member
    WHERE granted_role.rolname = 'butterfly_room_staging_user'
      AND member_role.rolname = current_user
  ), false) AS direct_set_option
\gset membership_before_

\echo 'Membership state before staging owner operations:'
SELECT
  :'membership_before_administrator' AS administrator,
  :'membership_before_can_set_role'::boolean AS can_set_role,
  :'membership_before_direct_membership_exists'::boolean AS direct_membership_exists,
  :'membership_before_direct_set_option'::boolean AS direct_set_option;

\set membership_added_by_script false
\set membership_set_enabled_by_script false

\if :membership_before_can_set_role
  \echo 'Administrator can already SET ROLE; no membership change is required.'
\else
  \if :membership_before_direct_membership_exists
    GRANT butterfly_room_staging_user TO CURRENT_USER WITH SET TRUE;
    \set membership_set_enabled_by_script true
  \else
    GRANT butterfly_room_staging_user TO CURRENT_USER WITH SET TRUE;
    \set membership_added_by_script true
  \endif
\endif

SELECT EXISTS (
  SELECT 1
  FROM pg_database
  WHERE datname = 'butterfly_room_staging'
) AS exists
\gset staging_database_

\if :staging_database_exists
  \echo 'butterfly_room_staging already exists; CREATE DATABASE is skipped.'
\else
  CREATE DATABASE butterfly_room_staging
    OWNER butterfly_room_staging_user;
\endif

-- Execute ACL changes as the database owner. This also makes reruns converge on
-- the intended staging-only database privileges.
SET ROLE butterfly_room_staging_user;

REVOKE ALL PRIVILEGES
  ON DATABASE butterfly_room_staging
  FROM PUBLIC;

GRANT CONNECT, TEMPORARY
  ON DATABASE butterfly_room_staging
  TO butterfly_room_staging_user;

RESET ROLE;

\connect butterfly_room_staging

SET ROLE butterfly_room_staging_user;

ALTER SCHEMA public OWNER TO butterfly_room_staging_user;

REVOKE ALL PRIVILEGES
  ON SCHEMA public
  FROM PUBLIC;

GRANT USAGE, CREATE
  ON SCHEMA public
  TO butterfly_room_staging_user;

ALTER DEFAULT PRIVILEGES FOR ROLE butterfly_room_staging_user IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE
  ON TABLES
  TO butterfly_room_staging_user;

ALTER DEFAULT PRIVILEGES FOR ROLE butterfly_room_staging_user IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE
  ON SEQUENCES
  TO butterfly_room_staging_user;

ALTER DEFAULT PRIVILEGES FOR ROLE butterfly_room_staging_user IN SCHEMA public
  GRANT EXECUTE
  ON FUNCTIONS
  TO butterfly_room_staging_user;

RESET ROLE;

\connect postgres

-- Restore only the state changed by this script. A membership that existed
-- before execution is never revoked.
\if :membership_added_by_script
  REVOKE butterfly_room_staging_user FROM CURRENT_USER;
\elif :membership_set_enabled_by_script
  GRANT butterfly_room_staging_user TO CURRENT_USER WITH SET FALSE;
\endif

\echo 'Membership state after cleanup (compare with the pre-operation row above):'
SELECT
  current_user AS administrator,
  pg_has_role(
    current_user,
    'butterfly_room_staging_user',
    'SET'
  ) AS can_set_role,
  EXISTS (
    SELECT 1
    FROM pg_auth_members membership
    JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
    JOIN pg_roles member_role ON member_role.oid = membership.member
    WHERE granted_role.rolname = 'butterfly_room_staging_user'
      AND member_role.rolname = current_user
  ) AS direct_membership_exists,
  COALESCE((
    SELECT membership.set_option
    FROM pg_auth_members membership
    JOIN pg_roles granted_role ON granted_role.oid = membership.roleid
    JOIN pg_roles member_role ON member_role.oid = membership.member
    WHERE granted_role.rolname = 'butterfly_room_staging_user'
      AND member_role.rolname = current_user
  ), false) AS direct_set_option;

\echo 'Staging database setup completed.'
\echo 'Verify a real login separately; \password can succeed without a completion message.'
