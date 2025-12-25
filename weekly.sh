#!/bin/bash
export HOME=/home/ubuntu
export AWS_PROFILE=default
export AWS_CONFIG_FILE="/home/ubuntu/.aws/config"
export AWS_SHARED_CREDENTIALS_FILE="/home/ubuntu/.aws/credentials"
export PATH=$PATH:/usr/local/bin

CONFIG_FILE="/home/ubuntu/.server-scripts.conf"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck source=/dev/null
    . "$CONFIG_FILE"
elif [ -f "$SCRIPT_DIR/.server-scripts.conf" ]; then
    # shellcheck source=/dev/null
    . "$SCRIPT_DIR/.server-scripts.conf"
fi

# === CONFIG ===
LOG_DIR="/home/ubuntu/logs"
LOG_FILE="$LOG_DIR/weekly_maintenance.log"
DB_USER="${DB_USER:-root}"
DB_PASS="${DB_PASS:-}"
DB_NAMES=("gamenight" "microblog" "tools" "cozy")
BACKUP_DIR="/home/ubuntu/backups"
LARAVEL_APPS=(
  "/var/www/laravel/gamenight"
  "/var/www/laravel/tools"
  "/var/www/laravel/microblog"
  "/var/www/laravel/cozy"
)
S3_BUCKET="gamenight-cc-my-sql-backups"

# === LOG FUNCTION ===
log() {
  echo "$1" | tee -a "$LOG_FILE"
}

# === START SCRIPT ===
mkdir -p "$LOG_DIR"
mkdir -p "$BACKUP_DIR"
log "========== Weekly Maintenance: $(date) =========="
log "Weekly script started"

if [ -z "$DB_PASS" ]; then
    log "ERROR: DB_PASS is not set. Please create $CONFIG_FILE with DB_PASS set and chmod 600 $CONFIG_FILE."
    exit 1
fi

# === APT UPDATE & UPGRADE ===
log "[APT] Updating and upgrading packages..."
apt-get update 2>&1 | tee -a "$LOG_FILE"
apt-get upgrade -y 2>&1 | tee -a "$LOG_FILE"

# === MYSQL BACKUPS ===
# Using %F_%H%M adds the time (e.g., 2025-12-08_1530) so files never overwrite
TIMESTAMP=$(date +%F_%H%M)

for DB_NAME in "${DB_NAMES[@]}"; do
    log "[MYSQL] Dumping database $DB_NAME..."
    mysqldump -u "$DB_USER" -p"$DB_PASS" "$DB_NAME" > "$BACKUP_DIR/${DB_NAME}_${TIMESTAMP}.sql" 2>>"$LOG_FILE"
done

# === UPLOAD BACKUPS TO S3 ===
# We switch to 'sync' (without --delete).
# This is smarter than 'cp': it only uploads NEW files. It won't re-upload old ones.
log "[S3] Syncing new backups to S3 bucket: $S3_BUCKET..."
aws s3 sync "$BACKUP_DIR" "s3://$S3_BUCKET/" 2>&1 | tee -a "$LOG_FILE"

# === CLEANUP LOCAL BACKUPS ===
# This logic still works perfectly with the new timestamps
log "[CLEANUP] Removing old local backups (keeping latest 2)..."
for DB_NAME in "${DB_NAMES[@]}"; do
    ls -tp "$BACKUP_DIR/${DB_NAME}_"*.sql 2>/dev/null | grep -v '/$' | tail -n +3 | xargs -r rm --
done

# === LARAVEL MAINTENANCE ===
for APP_PATH in "${LARAVEL_APPS[@]}"; do
    log "[LARAVEL] Cleaning $APP_PATH..."
    cd "$APP_PATH" || { log "Failed to cd into $APP_PATH"; continue; }
    php artisan cache:clear 2>&1 | tee -a "$LOG_FILE"
    php artisan config:clear 2>&1 | tee -a "$LOG_FILE"
    php artisan route:clear 2>&1 | tee -a "$LOG_FILE"
    php artisan view:clear 2>&1 | tee -a "$LOG_FILE"
    rm -f storage/logs/*.log 2>&1 | tee -a "$LOG_FILE"
done

# === LOGROTATE ===
# Make sure you have a proper config for your logs in /etc/logrotate.d/
# Example: /etc/logrotate.d/weekly_maintenance
# === ROTATE LOGS MANUALLY ===
MAX_LOGS=7
ls -1t "$LOG_DIR"/weekly_maintenance.log* | tail -n +$((MAX_LOGS+1)) | xargs -r rm -f

log "Weekly script finished"


log "[SYSTEM] Rebooting server..."
sudo reboot