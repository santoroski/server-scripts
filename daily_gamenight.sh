#!/bin/bash
# Daily gamenight DB dump -> S3

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
BACKUP_DIR="${BACKUP_DIR:-/home/ubuntu/backups}/daily"
mkdir -p "$LOG_DIR" "$BACKUP_DIR"
LOG_FILE="$LOG_DIR/daily_gamenight.log"

TIMESTAMP=$(date +%F_%H%M)
DB_NAME="gamenight"
DUMP_FILE="$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.sql"
GZ_FILE="$DUMP_FILE.gz"

# Requirements
command -v mysqldump >/dev/null 2>&1 || { echo "mysqldump not found" | tee -a "$LOG_FILE"; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "aws cli not found" | tee -a "$LOG_FILE"; exit 1; }

if [ -z "$DB_PASS" ]; then
  echo "ERROR: DB_PASS is not set in $CONFIG_FILE" | tee -a "$LOG_FILE"
  exit 1
fi

echo "[${TIMESTAMP}] [DAILY] Dumping $DB_NAME to $DUMP_FILE" | tee -a "$LOG_FILE"
mysqldump -u "${DB_USER:-root}" -p"$DB_PASS" "$DB_NAME" > "$DUMP_FILE" 2>>"$LOG_FILE" || { echo "mysqldump failed" | tee -a "$LOG_FILE"; rm -f "$DUMP_FILE"; exit 2; }

gzip -9 "$DUMP_FILE"

# Determine S3 destination (use S3_BUCKET; daily objects go under /daily/)
if [ -n "$S3_BUCKET" ]; then
  S3_DEST="s3://$S3_BUCKET/daily"
else
  echo "ERROR: No S3 destination configured (set S3_BUCKET in config)." | tee -a "$LOG_FILE"
  exit 1
fi

echo "[${TIMESTAMP}] [S3] Uploading $GZ_FILE to $S3_DEST/" | tee -a "$LOG_FILE"
aws s3 cp "$GZ_FILE" "$S3_DEST/" 2>&1 | tee -a "$LOG_FILE" || { echo "S3 upload failed" | tee -a "$LOG_FILE"; exit 3; }

# Keep only last 7 daily backups
echo "[${TIMESTAMP}] [CLEANUP] Rotating daily backups (keep 7)" | tee -a "$LOG_FILE"
ls -1t "$BACKUP_DIR"/${DB_NAME}_*.sql.gz 2>/dev/null | tail -n +8 | xargs -r rm -f

echo "[${TIMESTAMP}] Daily gamenight backup completed" | tee -a "$LOG_FILE"
