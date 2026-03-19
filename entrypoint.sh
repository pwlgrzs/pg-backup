#!/bin/bash
set -euo pipefail

# ── Validate backup path is mounted and writable ─────────────────────────────
echo "[$(date)] Checking mount at /backups..."

if [ ! -d "/backups" ]; then
  echo "[ERROR] /backups directory does not exist — volume not mounted!"
  exit 1
fi

if ! touch /backups/.write_test 2>/dev/null; then
  echo "[ERROR] /backups is not writable — check permissions on the host path!"
  echo "[ERROR] Current mount info:"
  mount | grep backups || echo "(no mount entry found for /backups)"
  echo "[ERROR] Directory listing of /:"
  ls -la / | grep backups
  exit 1
fi

rm -f /backups/.write_test
echo "[$(date)] ✔ /backups is mounted and writable"

# Make Docker env vars available to cron
printenv | grep -v "no_proxy" >> /etc/environment

# Write crontab directly — Alpine busybox crond doesn't use /etc/cron.d
echo "${CRON_SCHEDULE} . /etc/environment; /usr/local/bin/backup.sh >> /var/log/pg-backup.log 2>&1" \
  | crontab -

# Pre-create log file so tail -F doesn't fail on empty start
touch /var/log/pg-backup.log

echo "[$(date)] Cron scheduled: ${CRON_SCHEDULE}"
echo "[$(date)] Container started, waiting for first run..."

# Run crond in foreground
crond -f -d 8 &
CRON_PID=$!

# Tail log to stdout so `docker logs` works
tail -F /var/log/pg-backup.log &
TAIL_PID=$!

# Trap SIGTERM/SIGINT for graceful shutdown
trap "echo 'Shutting down...'; kill $CRON_PID $TAIL_PID; exit 0" SIGTERM SIGINT

wait $CRON_PID
