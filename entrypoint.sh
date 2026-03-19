#!/bin/bash
set -euo pipefail

# Make Docker env vars available to cron
printenv | grep -v "no_proxy" >> /etc/environment

# Build the crontab dynamically from CRON_SCHEDULE env var
echo "${CRON_SCHEDULE} root . /etc/environment; /usr/local/bin/backup.sh >> /var/log/pg-backup.log 2>&1" \
  > /etc/cron.d/pg-backup

chmod 0644 /etc/cron.d/pg-backup

# Pre-create log file so tail -f doesn't fail on empty start
touch /var/log/pg-backup.log

echo "[$(date)] Cron scheduled: ${CRON_SCHEDULE}"
echo "[$(date)] Container started, waiting for first run..."

# Run crond in FOREGROUND (-f) + pipe to stdout so Docker captures logs
crond -f -d 8 &
CRON_PID=$!

# Tail log to stdout so `docker logs` works
tail -F /var/log/pg-backup.log &
TAIL_PID=$!

# Trap SIGTERM/SIGINT for graceful shutdown
trap "echo 'Shutting down...'; kill $CRON_PID $TAIL_PID; exit 0" SIGTERM SIGINT

# Keep container alive by waiting on crond
wait $CRON_PID
