#!/bin/bash
set -euo pipefail

: "${SERVER_NAME:?SERVER_NAME is required}"
: "${DB_PORT:?DB_PORT is required}"
: "${USER_NAME:?USER_NAME is required}"
: "${PASSWORD:?PASSWORD is required}"
: "${ROTATE:?ROTATE (days) is required}"
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN is required}"
: "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID is required}"

export PGPASSWORD="$PASSWORD"

BACKUP_ROOT="/backups"
DATE=$(date +"%Y-%m-%d_%H%M%S")
START_TIME=$(date +%s)

FAILED_DBS=""
SUCCESS_DBS=""
SUMMARY_ROWS=""

# ── Telegram helper ──────────────────────────────────────────────────────────
send_telegram() {
  local message="$1"
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="${TELEGRAM_CHAT_ID}" \
    -d parse_mode="HTML" \
    -d text="$message" > /dev/null
}

echo "[$(date)] Starting backup from server: $SERVER_NAME"

# ── Write test ───────────────────────────────────────────────────────────────
if ! touch "${BACKUP_ROOT}/.write_test" 2>/dev/null; then
  MSG="❌ <b>pg-backup failed</b>%0ACannot write to $BACKUP_ROOT — permission denied!"
  send_telegram "$MSG"
  echo "[ERROR] Cannot write to $BACKUP_ROOT"
  exit 1
fi
rm -f "${BACKUP_ROOT}/.write_test"

# ── Fetch databases ──────────────────────────────────────────────────────────
DATABASES=$(psql -h "$SERVER_NAME" -p "$DB_PORT" -U "$USER_NAME" -d postgres -t -A -c \
  "SELECT datname FROM pg_database WHERE datistemplate = false AND datname NOT IN ('postgres');")

if [ -z "$DATABASES" ]; then
  send_telegram "❌ <b>pg-backup failed</b>%0ANo databases found on $SERVER_NAME"
  echo "[$(date)] No databases found. Exiting."
  exit 1
fi

# ── Backup each database ─────────────────────────────────────────────────────
for DB in $DATABASES; do
  DB_DIR="${BACKUP_ROOT}/${DB}"
  mkdir -p "$DB_DIR"
  BACKUP_FILE="${DB_DIR}/${DB}_${DATE}.dump"

  echo "[$(date)] Backing up: $DB → $BACKUP_FILE"
  DB_START=$(date +%s)

  if pg_dump -h "$SERVER_NAME" -p "$DB_PORT" -U "$USER_NAME" -Fc "$DB" > "$BACKUP_FILE" 2>/dev/null; then
    DB_END=$(date +%s)
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    DURATION=$((DB_END - DB_START))
    echo "[$(date)] ✔ Done: $BACKUP_FILE ($SIZE, ${DURATION}s)"
    SUCCESS_DBS="${SUCCESS_DBS} ${DB}"
    SUMMARY_ROWS="${SUMMARY_ROWS}✅ <code>${DB}</code> — ${SIZE} in ${DURATION}s%0A"
  else
    echo "[$(date)] ✘ Failed: $DB"
    FAILED_DBS="${FAILED_DBS} ${DB}"
    SUMMARY_ROWS="${SUMMARY_ROWS}❌ <code>${DB}</code> — failed%0A"
    rm -f "$BACKUP_FILE"
  fi
done

# ── Rotate old backups ───────────────────────────────────────────────────────
echo "[$(date)] Rotating backups older than ${ROTATE} days..."
find "$BACKUP_ROOT" -type f -name "*.dump" -mtime +"$ROTATE" -exec rm -f {} \;

# ── Summary ──────────────────────────────────────────────────────────────────
END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))
TOTAL_SIZE=$(du -sh "$BACKUP_ROOT" | cut -f1)

if [ -z "$FAILED_DBS" ]; then
  STATUS="✅ <b>pg-backup completed</b>"
else
  STATUS="⚠️ <b>pg-backup completed with errors</b>"
fi

MESSAGE="${STATUS}
🖥 Server: <code>${SERVER_NAME}:${DB_PORT}</code>
🕐 Duration: ${TOTAL_DURATION}s
💾 Total backup size: ${TOTAL_SIZE}
🔄 Rotation: ${ROTATE} days

${SUMMARY_ROWS}"

send_telegram "$MESSAGE"
echo "[$(date)] ✔ Backup run finished in ${TOTAL_DURATION}s."
