#!/bin/bash
set -e

# Cron compatibility (ensure AWS CLI checks /home/ubuntu for creds)
export HOME=/home/ubuntu
# Optional: Ensure /usr/local/bin etc is in path if needed, usually passed by cron or shell
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Configuration
TIMESTAMP=$(date +%F)
BUCKET="s3://gamenight-cc-my-sql-backups"
BACKUP_DIR="/tmp/server_backup_$TIMESTAMP"
APP_ROOT="/var/www/laravel"
PROJECTS=("gamenight" "microblog" "tools" "cozy")

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

for PROJECT in "${PROJECTS[@]}"; do
    PROJECT_DIR="$APP_ROOT/$PROJECT"
    PROJECT_BACKUP_DIR="$BACKUP_DIR/app_data/$PROJECT"
    
    log "Processing project: $PROJECT"
    
    if [ ! -d "$PROJECT_DIR" ]; then
        log "Warning: Project directory $PROJECT_DIR not found. Skipping."
        continue
    fi

    mkdir -p "$PROJECT_BACKUP_DIR"

    if [ -f "$PROJECT_DIR/.env" ]; then
        cp "$PROJECT_DIR/.env" "$PROJECT_BACKUP_DIR/.env"
        log "  Backed up .env file."
    else
        log "  Warning: .env file not found at $PROJECT_DIR/.env"
    fi

    if [ -d "$PROJECT_DIR/storage" ]; then
        tar -czf "$PROJECT_BACKUP_DIR/storage_dir.tar.gz" -C "$PROJECT_DIR" storage
        log "  Backed up storage directory."
    else
        log "  Warning: storage directory not found at $PROJECT_DIR/storage"
    fi
done

# SHIP TO S3
log "Uploading to S3..."
# Compressing the entire backup directory
# Using Day of Week (e.g. "Monday", "Tuesday") to keep a rolling 7-day backup and save space.
DAY_OF_WEEK=$(date +%A)
tar -czf - -C /tmp "server_backup_$TIMESTAMP" | aws s3 cp - "$BUCKET/daily-configs-$DAY_OF_WEEK.tar.gz"

# CLEANUP
log "Cleaning up..."
rm -rf "$BACKUP_DIR"

log "Backup completed successfully."