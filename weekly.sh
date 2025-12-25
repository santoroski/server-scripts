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

# === WEEKLY BACKUP (delegated) ===
log "[BACKUP] Delegating database backups to weekly_backup.sh..."
if [ -x "$SCRIPT_DIR/weekly_backup.sh" ]; then
    "$SCRIPT_DIR/weekly_backup.sh" 2>&1 | tee -a "$LOG_FILE"
else
    log "weekly_backup.sh not found or not executable; skipping weekly DB backups"
fi


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

# Reboot only when explicitly allowed (pass --reboot or create /home/ubuntu/ALLOW_REBOOT)
if [ "$1" = "--reboot" ] || [ -f /home/ubuntu/ALLOW_REBOOT ]; then
  log "[SYSTEM] Rebooting server..."
  sudo reboot
else
  log "[SYSTEM] Reboot skipped (no --reboot and /home/ubuntu/ALLOW_REBOOT not present)"
fi