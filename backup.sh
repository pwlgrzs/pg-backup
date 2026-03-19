#!/bin/bash
set -euo pipefail

# ── env vars (injected via Docker) ──────────────────────────────────────────
: "${BACKUP_PATH:?BACKUP_PATH is required}"
: "${SERVER_NAME:?SERVER_NAME is required}"
: "${DB_PORT:?DB_PORT is required}"
: "${USER_NAME:?USER_NAME is required}"
: "${PASSWORD:?PASSWORD is required}"
: "${ROTATE:?ROTATE (days) is required}"

export PGPASSWORD="$PASSWORD"

DATE=$(date +"%Y-%m-%d_%H%M%S")

echo "[$(date)] Starting backup from server: $SERVER_NAME"

# ── Validate backup path ─────────────────────────────────────────────────────
echo "[$(date)] Backup root: $BACKUP_PATH"
echo "[$(date)] Disk space:"
df -h "$BACKUP_PATH"

if ! touch "${BACKUP_PATH}/.write_test" 2>/dev/null; then
  echo "[ERROR] Cannot write to $BACKUP_PATH — permission denied!"
  ls -la "$(dirname "$BACKUP_PATH")"
  exit 1
fi
rm -f "${BACKUP_PATH}/.write_test"
echo "[$(date)] ✔ Backup path is writable"

# ── Fetch all user databases (skip system ones) ──────────────────────────────
DATABASES=$(psql -h "$SERVER_NAME" -p "$DB_PORT" -U "$USER_NAME" -d postgres -t -A -c \
  "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres');")

if [ -z "$DATABASES" ]; then
  echo "[$(date)] No databases found. Exiting."
  exit 1
fi

# ── Backup each database ─────────────────────────────────────────────────────
for DB in $DATABASES; do
  DB_DIR="${BACKUP_PATH}/${DB}"
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

# ── Rotate old backups ───────────────────────────────────────────────────────
echo "[$(date)] Rotating backups older than ${ROTATE} days..."

find "$BACKUP_PATH" -type f -name "*.dump" -mtime +"$ROTATE" -exec rm -f {} \;

echo "[$(date)] ✔ Rotation complete. Backup run finished."
