\set ON_ERROR_STOP on

-- Run while connected to the existing RDS instance as an authorized database administrator.
-- The password is requested securely by psql and is never stored in this file.

SELECT format(
  'CREATE ROLE %I LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION',
  'butterfly_room_staging_user'
)
WHERE NOT EXISTS (
  SELECT 1 FROM pg_roles WHERE rolname = 'butterfly_room_staging_user'
) \gexec

ALTER ROLE butterfly_room_staging_user
  NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION;

\password butterfly_room_staging_user

SELECT format(
  'CREATE DATABASE %I OWNER %I',
  'butterfly_room_staging',
  'butterfly_room_staging_user'
)
WHERE NOT EXISTS (
  SELECT 1 FROM pg_database WHERE datname = 'butterfly_room_staging'
) \gexec

REVOKE ALL PRIVILEGES ON DATABASE butterfly_room_staging FROM PUBLIC;
GRANT CONNECT, TEMPORARY ON DATABASE butterfly_room_staging TO butterfly_room_staging_user;

\connect butterfly_room_staging

ALTER SCHEMA public OWNER TO butterfly_room_staging_user;
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
GRANT USAGE, CREATE ON SCHEMA public TO butterfly_room_staging_user;

ALTER DEFAULT PRIVILEGES FOR ROLE butterfly_room_staging_user IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER ON TABLES TO butterfly_room_staging_user;
ALTER DEFAULT PRIVILEGES FOR ROLE butterfly_room_staging_user IN SCHEMA public
  GRANT USAGE, SELECT, UPDATE ON SEQUENCES TO butterfly_room_staging_user;
ALTER DEFAULT PRIVILEGES FOR ROLE butterfly_room_staging_user IN SCHEMA public
  GRANT EXECUTE ON FUNCTIONS TO butterfly_room_staging_user;

\echo 'Staging database and role preparation completed.'
