#!/bin/bash
set -euo pipefail

: "${SERVER_NAME:?SERVER_NAME is required}"
: "${DB_PORT:?DB_PORT is required}"
: "${USER_NAME:?USER_NAME is required}"
: "${PASSWORD:?PASSWORD is required}"
: "${ROTATE:?ROTATE (days) is required}"
: "${TELEGRAM_BOT_TOKEN:?TELEGRAM_BOT_TOKEN is required}"
: "${TELEGRAM_CHAT_ID:?TELEGRAM_CHAT_ID is required}"

if ! [[ "$ROTATE" =~ ^[0-9]+$ ]]; then
  echo "[ERROR] ROTATE must be a whole number of days, got: '$ROTATE'"
  exit 1
fi

export PGPASSWORD="$PASSWORD"

BACKUP_ROOT="/backups"
DATE=$(date +"%Y-%m-%d_%H%M%S")
START_TIME=$(date +%s)

FAILED_DBS=""
SUCCESS_DBS=""
SUMMARY_ROWS=""

# ── Helpers ──────────────────────────────────────────────────────────────────
html_escape() {
  printf '%s' "$1" | sed 's/&/\&amp;/g; s/</\&lt;/g; s/>/\&gt;/g'
}

send_telegram() {
  local message="$1"
  # --data-urlencode lets us send real newlines and any characters safely.
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    --data-urlencode "chat_id=${TELEGRAM_CHAT_ID}" \
    --data-urlencode "parse_mode=HTML" \
    --data-urlencode "text=${message}" > /dev/null \
    || echo "[WARN] Telegram notification failed"
}

echo "[$(date)] Starting backup from server: $SERVER_NAME"

# ── Write test ───────────────────────────────────────────────────────────────
if ! touch "${BACKUP_ROOT}/.write_test" 2>/dev/null; then
  send_telegram "❌ <b>pg-backup failed</b>
Cannot write to <code>${BACKUP_ROOT}</code> — permission denied!"
  echo "[ERROR] Cannot write to $BACKUP_ROOT"
  exit 1
fi
rm -f "${BACKUP_ROOT}/.write_test"

# ── Fetch databases ──────────────────────────────────────────────────────────
PSQL_ERR=$(mktemp)
if ! DATABASES=$(psql -h "$SERVER_NAME" -p "$DB_PORT" -U "$USER_NAME" -d postgres -t -A -c \
  "SELECT datname FROM pg_database WHERE datistemplate = false AND datname <> 'postgres';" \
  2>"$PSQL_ERR"); then
  send_telegram "❌ <b>pg-backup failed</b>
Cannot query databases on <code>${SERVER_NAME}:${DB_PORT}</code>
<pre>$(html_escape "$(cat "$PSQL_ERR")")</pre>"
  echo "[ERROR] psql failed: $(cat "$PSQL_ERR")"
  rm -f "$PSQL_ERR"
  exit 1
fi
rm -f "$PSQL_ERR"

if [ -z "$DATABASES" ]; then
  send_telegram "❌ <b>pg-backup failed</b>
No databases found on <code>${SERVER_NAME}</code>"
  echo "[$(date)] No databases found. Exiting."
  exit 1
fi

# ── Backup each database ─────────────────────────────────────────────────────
# Split the list on newlines only (names may contain spaces) and disable globbing.
OLD_IFS=$IFS
IFS=$'\n'
set -f
for DB in $DATABASES; do
  DB_DIR="${BACKUP_ROOT}/${DB}"
  mkdir -p "$DB_DIR"
  BACKUP_FILE="${DB_DIR}/${DB}_${DATE}.dump"
  DB_LABEL=$(html_escape "$DB")

  echo "[$(date)] Backing up: $DB → $BACKUP_FILE"
  DB_START=$(date +%s)

  if pg_dump -h "$SERVER_NAME" -p "$DB_PORT" -U "$USER_NAME" -Fc "$DB" > "$BACKUP_FILE" 2>/dev/null; then
    DB_END=$(date +%s)
    SIZE=$(du -h "$BACKUP_FILE" | cut -f1)
    DURATION=$((DB_END - DB_START))
    echo "[$(date)] ✔ Done: $BACKUP_FILE ($SIZE, ${DURATION}s)"
    SUCCESS_DBS="${SUCCESS_DBS} ${DB}"
    SUMMARY_ROWS="${SUMMARY_ROWS}✅ <code>${DB_LABEL}</code> — ${SIZE} in ${DURATION}s"$'\n'
  else
    echo "[$(date)] ✘ Failed: $DB"
    FAILED_DBS="${FAILED_DBS} ${DB}"
    SUMMARY_ROWS="${SUMMARY_ROWS}❌ <code>${DB_LABEL}</code> — failed"$'\n'
    rm -f "$BACKUP_FILE"
  fi
done
set +f
IFS=$OLD_IFS

# ── Rotate old backups ───────────────────────────────────────────────────────
echo "[$(date)] Rotating backups older than ${ROTATE} days..."
find "$BACKUP_ROOT" -type f -name "*.dump" -mtime +"$ROTATE" -exec rm -f {} \;
# Drop now-empty per-database directories.
find "$BACKUP_ROOT" -mindepth 1 -type d -empty -delete

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
