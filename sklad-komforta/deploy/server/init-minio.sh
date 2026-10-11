#!/bin/sh
# Повторный запуск не открывает bucket для анонимного доступа.
set -eu
mc alias set local http://minio:9000 sklad-root "$MINIO_ROOT_PASSWORD" >/dev/null
mc mb --ignore-existing local/sklad-komforta
mc anonymous set none local/sklad-komforta
mc admin user add local sklad-app "$S3_SECRET_KEY"
mc admin policy create local sklad-app /setup/storage-policy.json
mc admin policy attach local sklad-app --user sklad-app
