#!/usr/bin/env bash
set -Eeuo pipefail

PROJECT="/home/phuong/lab-web"
DEST="/srv/data/backups/lab-web"
KEEP_DAYS=7
TIME=$(date +%Y%m%d-%H%M%S)

set -a
source "$PROJECT/.env"
set +a

: "${DB_DATABASE:?Missing DB_DATABASE}"
: "${DB_ROOT_PASSWORD:?Missing DB_ROOT_PASSWORD}"

mkdir -p "$DEST"

echo "[backup] Bat dau: $TIME"

tar -czf "$DEST/src-$TIME.tar.gz" \
    -C "$PROJECT" \
    src nginx php mariadb docker-compose.yml

echo "[backup] Source code: OK"

docker exec \
    -e MYSQL_PWD="$DB_ROOT_PASSWORD" \
    lab_mariadb \
    mariadb-dump -uroot \
    --single-transaction \
    --routines \
    --triggers \
    --databases "$DB_DATABASE" \
    | gzip > "$DEST/db-$TIME.sql.gz.tmp"

gzip -t "$DEST/db-$TIME.sql.gz.tmp"

mv "$DEST/db-$TIME.sql.gz.tmp" \
   "$DEST/db-$TIME.sql.gz"

echo "[backup] Database: OK"

find "$DEST" \
    -type f \
    -name '*.gz' \
    -mtime +"$KEEP_DAYS" \
    -delete

echo "[backup] Don dep backup cu: OK"
echo "[backup] Hoan tat: $TIME"

