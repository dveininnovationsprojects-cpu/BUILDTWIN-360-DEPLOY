#!/usr/bin/env bash
# Nightly and pre-deploy PostgreSQL backup on the production VM.
# Cron example (as the deploy user):  0 2 * * *  /opt/buildtwin/prod/backup-prod.sh >> /var/log/buildtwin-backup.log 2>&1
# Set OFFSITE_CMD to copy the dump off the VM, e.g.  OFFSITE_CMD='aws s3 cp "$FILE" s3://your-bucket/buildtwin/'
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BACKUP_DIR="${BACKUP_DIR:-/var/backups/buildtwin}"
KEEP_DAYS="${KEEP_DAYS:-14}"
set -a; . "$ROOT/prod/.env.prod"; set +a
COMPOSE="docker compose --env-file $ROOT/prod/.env.prod -f $ROOT/prod/docker-compose.prod.yml"

mkdir -p "$BACKUP_DIR"
FILE="$BACKUP_DIR/buildtwin-$(date +%Y%m%d-%H%M%S).dump"
$COMPOSE exec -T postgres pg_dump -U "${POSTGRES_USER:-buildtwin}" -d "${POSTGRES_DB:-buildtwin}" -Fc > "$FILE"
[ -s "$FILE" ] || { echo "empty backup"; exit 1; }
$COMPOSE exec -T postgres pg_restore -l < "$FILE" | grep -q '^[0-9]*;' || { echo "backup archive has no entries"; exit 1; }
echo "BACKUP_OK $FILE ($(stat -c %s "$FILE") bytes, sha256 $(sha256sum "$FILE" | cut -d' ' -f1))"

if [ -n "${OFFSITE_CMD:-}" ]; then eval "$OFFSITE_CMD"; echo "OFFSITE_OK"; fi
find "$BACKUP_DIR" -name 'buildtwin-*.dump' -mtime +"$KEEP_DAYS" -delete
