#!/bin/bash
set -e

# Configuration
TIMESTAMP=$(date +%F)
BUCKET="s3://gamenight-cc-my-sql-backups"
BACKUP_DIR="/tmp/server_backup_$TIMESTAMP"
APP_DIR="/var/www/html"

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

# Check dependencies
if ! command -v aws &> /dev/null; then
    log "Error: aws-cli is not installed or not in PATH."
    exit 1
fi

log "Starting backup process..."
mkdir -p "$BACKUP_DIR"

# SERVER CONFIGS
log "Backing up Configs..."
mkdir -p "$BACKUP_DIR/configs"

# Installed software list
if dpkg --get-selections > "$BACKUP_DIR/installed_packages.txt"; then
    log "Saved installed packages list."
else
    log "Warning: Failed to save installed packages list."
fi

# Nginx & PHP
# Using strict folders to avoid permission errors during tar
if [ -d "/etc/nginx" ]; then
    cp -r /etc/nginx "$BACKUP_DIR/configs/nginx"
else
    log "Warning: /etc/nginx not found."
fi

if [ -d "/etc/php" ]; then
    cp -r /etc/php "$BACKUP_DIR/configs/php"
else
    log "Warning: /etc/php not found."
fi

# Cron Jobs
if crontab -l > "$BACKUP_DIR/root_crontab.txt" 2>/dev/null; then
    log "Saved root crontab."
else
    log "Warning: No root crontab found or permission denied."
fi

# APP DATA
log "Backing up App State..."
mkdir -p "$BACKUP_DIR/app_data"

if [ -f "$APP_DIR/.env" ]; then
    cp "$APP_DIR/.env" "$BACKUP_DIR/app_data/env_production"
    log "Backed up .env file."
else
    log "Warning: .env file not found at $APP_DIR/.env"
fi

if [ -d "$APP_DIR/storage" ]; then
    tar -czf "$BACKUP_DIR/app_data/storage_dir.tar.gz" -C "$APP_DIR" storage
    log "Backed up storage directory."
else
    log "Warning: storage directory not found at $APP_DIR/storage"
fi

# SHIP TO S3
log "Uploading to S3..."
# Compressing the entire backup directory
tar -czf - -C /tmp "server_backup_$TIMESTAMP" | aws s3 cp - "$BUCKET/$TIMESTAMP-configs-bundle.tar.gz"

# CLEANUP
log "Cleaning up..."
rm -rf "$BACKUP_DIR"

log "Backup completed successfully."