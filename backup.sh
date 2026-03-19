#!/bin/bash
set -euo pipefail

: "${SERVER_NAME:?SERVER_NAME is required}"
: "${DB_PORT:?DB_PORT is required}"
: "${USER_NAME:?USER_NAME is required}"
: "${PASSWORD:?PASSWORD is required}"
: "${ROTATE:?ROTATE (days) is required}"

export PGPASSWORD="$PASSWORD"

BACKUP_ROOT="/backups"
DATE=$(date +"%Y-%m-%d_%H%M%S")

echo "[$(date)] Starting backup from server: $SERVER_NAME"
echo "[$(date)] Backup root: $BACKUP_ROOT"
echo "[$(date)] Disk space:"
df -h "$BACKUP_ROOT"

if ! touch "${BACKUP_ROOT}/.write_test" 2>/dev/null; then
  echo "[ERROR] Cannot write to $BACKUP_ROOT — permission denied!"
  ls -la "$BACKUP_ROOT"
  exit 1
fi
rm -f "${BACKUP_ROOT}/.write_test"

DATABASES=$(psql -h "$SERVER_NAME" -p "$DB_PORT" -U "$USER_NAME" -d postgres -t -A -c \
  "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres');")

if [ -z "$DATABASES" ]; then
  echo "[$(date)] No databases found. Exiting."
  exit 1
fi

for DB in $DATABASES; do
  DB_DIR="${BACKUP_ROOT}/${DB}"
  mkdir -p "$DB_DIR"

  BACKUP_FILE="${DB_DIR}/${DB}_${DATE}.dump"
  echo "[$(date)] Backing up database: $DB → $BACKUP_FILE"

  pg_dump \
    -h "$SERVER_NAME" \
    -p "$DB_PORT" \
    -U "$USER_NAME" \
    -Fc \
    "$DB" > "$BACKUP_FILE"

  SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
  echo "[$(date)] ✔ Done: $BACKUP_FILE ($SIZE)"
done

echo "[$(date)] Rotating backups older than ${ROTATE} days..."
find "$BACKUP_ROOT" -type f -name "*.dump" -mtime +"$ROTATE" -exec rm -f {} \;
echo "[$(date)] ✔ Rotation complete. Backup run finished."
