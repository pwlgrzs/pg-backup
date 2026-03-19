#!/bin/bash
set -euo pipefail

# Make Docker env vars available to cron
printenv | grep -v "no_proxy" >> /etc/environment

# Build the crontab dynamically from CRON_SCHEDULE env var
echo "${CRON_SCHEDULE} root . /etc/environment; /usr/local/bin/backup.sh >> /var/log/pg-backup.log 2>&1" \
  > /etc/cron.d/pg-backup

chmod 0644 /etc/cron.d/pg-backup
crontab /etc/cron.d/pg-backup

echo "[$(date)] Cron scheduled: ${CRON_SCHEDULE}"
echo "[$(date)] Waiting for first run..."

# Run cron in foreground + tail logs
touch /var/log/pg-backup.log
cron && tail -f /var/log/pg-backup.log
