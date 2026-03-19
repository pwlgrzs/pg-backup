# pg-backup

> ⚠️ This project was created with AI assistance (Perplexity AI). Review all scripts before running in production.

A lightweight Docker container that automates full PostgreSQL server backups. Each database is dumped individually using `pg_dump`, stored in its own folder, rotated automatically, and a summary is sent to Telegram after every run.

---

## Features

- Dumps every non-system database to its own folder
- Backup files named `DB_NAME_DATE.dump` (compressed custom format)
- Automatic rotation of old backups by configurable number of days
- Telegram summary notification with per-database size and duration
- Cron schedule fully configurable via `.env`
- Timezone support
- Write permission check on startup
- Pre-built images via GitHub Container Registry

---

---

## Quick Start

### 1. Clone the repository

```bash
git clone https://github.com/pwlgrzs/pg-backup.git
cd pg-backup
```

### 2. Configure environment

```bash
cp .env.example .env
nano .env
```

### 3. Create the backup directory on the host

```bash
mkdir -p /your/backup/path
```

### 4. Start the container

```bash
docker compose up -d
docker compose logs -f
```

---

## Configuration

Copy `.env.example` to `.env` and fill in your values:

| Variable | Description | Example |
|---|---|---|
| `BACKUP_PATH` | Host path to store backups | `/volume1/Backup/pgsql_backup` |
| `SERVER_NAME` | PostgreSQL server hostname or IP | `192.168.88.202` |
| `DB_PORT` | PostgreSQL server port | `5433` |
| `USER_NAME` | PostgreSQL username | `postgres` |
| `PASSWORD` | PostgreSQL password | `supersecret` |
| `ROTATE` | Delete backups older than N days | `14` |
| `CRON_SCHEDULE` | Cron expression for backup schedule | `0 2 * * *` |
| `TZ` | Timezone for logs and cron | `Europe/Warsaw` |
| `TELEGRAM_BOT_TOKEN` | Telegram bot token | `123456:ABC-DEF...` |
| `TELEGRAM_CHAT_ID` | Telegram chat/user ID | `-1001234567890` |

---

## Backup Structure

Each database gets its own folder. Backups use PostgreSQL's compressed custom format (`.dump`), restorable with `pg_restore`.

---

## Telegram Notifications

After every run a summary is sent to your configured Telegram chat:

```
✅ pg-backup completed
🖥 Server: 192.168.88.202:5433
🕐 Duration: 42s
💾 Total backup size: 1.2G
🔄 Rotation: 14 days

✅ database — 24M in 8s
```

If any database fails, the status changes to ⚠️ and the failed database is marked with ❌.

---

## Running a Manual Backup

```bash
docker exec pg-backup-1 /usr/local/bin/backup.sh
```

---

## Restoring a Database

```bash
pg_restore \
  -h 192.168.88.202 \
  -p 5433 \
  -U postgres \
  -d target_database \
  /your/backup/path/authelia/authelia_2026-03-19_020001.dump
```

---

## Image

Pre-built images are available via GitHub Container Registry:

```bash
docker pull ghcr.io/pwlgrzs/pg-backup:latest
```

### Available Tags

| Tag | Description |
|---|---|
| `latest` | Latest build from `main` branch |
| `sha-abc1234` | Specific commit SHA |

---

## Requirements

- Docker & Docker Compose
- PostgreSQL client version **must match your server's major version**
  - This image uses `postgres:17-alpine` — compatible with PostgreSQL 17 servers
- Backup host directory must exist before starting the container

---

## Notes

- System databases (`postgres`, `template0`, `template1`) are excluded from backups
- `TZ` env var controls both log timestamps and cron schedule timing
- The container runs persistently as a cron daemon (`restart: unless-stopped`)
- Logs are available via `docker compose logs -f`

---

## License

MIT
```