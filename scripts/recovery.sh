#!/usr/bin/env bash
set -e

BACKUP_DIR="/srv/data/backups/lab-web"
CONTAINER="lab_mariadb"
PROJECT="/home/phuong/lab-web"

if [ -z "$1" ]; then
    echo "Usage: sudo $0 db-YYYYMMDD-HHMMSS.sql.gz"
    exit 1
fi

BACKUP_FILE="$BACKUP_DIR/$1"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "ERROR: Khong tim thay file backup: $BACKUP_FILE"
    exit 1
fi

if ! gzip -t "$BACKUP_FILE"; then
    echo "ERROR: File backup khong hop le."
    exit 1
fi

set -a
source "$PROJECT/.env"
set +a

echo "Backup: $BACKUP_FILE"
echo "Database: $DB_DATABASE"
read -r -p "Nhap RESTORE de xac nhan: " CONFIRM

if [ "$CONFIRM" != "RESTORE" ]; then
    echo "Da huy recovery."
    exit 1
fi

gzip -dc "$BACKUP_FILE" | docker exec -i \
    -e MYSQL_PWD="$DB_ROOT_PASSWORD" \
    "$CONTAINER" mariadb -uroot

echo "Recovery hoan tat."
