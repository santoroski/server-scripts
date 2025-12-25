#!/bin/bash
# weekly_backup.sh — gzip'd weekly DB dumps -> S3 (keeps backups separate under /weekly/)

set -euo pipefail
export HOME=/home/ubuntu
export AWS_PROFILE="${AWS_PROFILE:-default}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/home/ubuntu/.server-scripts.conf"
# fallback to repo config location if present
if [ -f "$SCRIPT_DIR/.server-scripts.conf" ]; then
  CONFIG_FILE="$SCRIPT_DIR/.server-scripts.conf"
fi

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  . "$CONFIG_FILE"
else
  echo "ERROR: Config file not found at $CONFIG_FILE" >&2
  exit 1
fi

LOG_DIR="${LOG_DIR:-/home/ubuntu/logs}"
BACKUP_DIR="${BACKUP_DIR:-/home/ubuntu/backups}/weekly"
mkdir -p "$LOG_DIR" "$BACKUP_DIR"
LOG_FILE="$LOG_DIR/weekly_backup.log"

log() { echo "[$(date +%F_%H%M)] [WEEKLY_BACKUP] $*" | tee -a "$LOG_FILE"; }

# Notification helper (uses pushover_notify.sh from repo if available)
notify() {
  if [ -x "$SCRIPT_DIR/pushover_notify.sh" ]; then
    "$SCRIPT_DIR/pushover_notify.sh" -t "$1" -m "$2" --priority "${3:-1}" || true
  else
    log "notify: $1 - $2"
  fi
}

TIMESTAMP=$(date +%F_%H%M)
DB_NAMES=("gamenight" "microblog" "tools" "cozy")

# Requirements
command -v mysqldump >/dev/null 2>&1 || { echo "mysqldump not found" | tee -a "$LOG_FILE"; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "aws CLI not found" | tee -a "$LOG_FILE"; exit 1; }

for DB_NAME in "${DB_NAMES[@]}"; do
  log "Dumping and compressing database: $DB_NAME"
  OUT_FILE="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.sql.gz"

  # Stream dump directly into gzip to avoid large temp files
  if mysqldump -u "${DB_USER:-root}" -p"$DB_PASS" "$DB_NAME" 2>>"$LOG_FILE" | gzip -9 > "$OUT_FILE" 2>>"$LOG_FILE"; then
    log "Created $OUT_FILE"
  else
    log "ERROR: backup failed for $DB_NAME"
    notify "Weekly backup failed" "Backup failed for $DB_NAME on $(hostname) at $TIMESTAMP" 1
    rm -f "$OUT_FILE"
    continue
  fi
done

# Upload to S3 under weekly/ prefix
S3_DEST="s3://$S3_BUCKET/weekly"
log "Syncing backups to $S3_DEST"
if ! aws s3 sync "$BACKUP_DIR" "$S3_DEST/" 2>&1 | tee -a "$LOG_FILE"; then
  log "ERROR: S3 sync failed"
  notify "Weekly backup upload failed" "Failed to sync backups to $S3_DEST on $(hostname) at $TIMESTAMP" 1
  exit 2
fi

# Rotate local .sql.gz backups - keep latest 2 per DB
log "Rotating local backups (keeping 2)..."
for DB_NAME in "${DB_NAMES[@]}"; do
  ls -tp "$BACKUP_DIR/${DB_NAME}_"*.sql.gz 2>/dev/null | grep -v '/$' | tail -n +3 | xargs -r rm --
done

log "Weekly backup finished"

# Send a success summary notification
notify "Weekly backup completed" "Backups completed for: ${DB_NAMES[*]}. Uploaded to ${S3_DEST}/ on $(hostname) at ${TIMESTAMP}" 0
