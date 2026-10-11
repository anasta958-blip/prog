#!/bin/sh
# Только первая инициализация пустого PostgreSQL volume.
set -eu
psql -v ON_ERROR_STOP=1 --username postgres --dbname sklad_komforta \
  --set=app_password="$APP_DATABASE_PASSWORD" <<'SQL'
CREATE ROLE sklad LOGIN PASSWORD :'app_password' NOSUPERUSER NOCREATEDB NOCREATEROLE;
ALTER DATABASE sklad_komforta OWNER TO sklad;
SQL
for migration in /migrations/public/*.sql; do
  psql -v ON_ERROR_STOP=1 --username sklad --dbname sklad_komforta --file "$migration"
done
