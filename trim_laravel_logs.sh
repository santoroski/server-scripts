#!/usr/bin/env bash
set -euo pipefail

LOCKFILE="/var/lock/trim_laravel_logs.lock"
LOGFILE="/home/blogger/trim_laravel_logs.log"

PROJECTS=( "gamenight" "tools" )
LOG_DIR_BASE="/var/www/laravel"
MAX_LINES=1000

# Acquire a non-blocking flock (prevents overlapping runs)
exec 9> "$LOCKFILE"
if ! flock -n 9; then
  echo "$(date +%F_%T) - Another instance is running; exiting" >> "$LOGFILE"
  exit 0
fi

for PROJECT in "${PROJECTS[@]}"; do
  LOG_FILE="${LOG_DIR_BASE}/${PROJECT}/storage/logs/laravel.log"
  if [ -f "$LOG_FILE" ]; then
    echo "$(date +%F_%T) - Trimming $LOG_FILE" | tee -a "$LOGFILE"
    TMP="$(mktemp "${LOG_FILE}.tmp.XXXX")"
    tail -n "$MAX_LINES" "$LOG_FILE" > "$TMP" && mv -f "$TMP" "$LOG_FILE"
    # Ensure ownership & permissions: owner=blogger, group=www-data, mode=0640
    chown blogger:www-data "$LOG_FILE" || true
    chmod 0640 "$LOG_FILE"
  else
    echo "$(date +%F_%T) - Log file not found for $PROJECT: $LOG_FILE" | tee -a "$LOGFILE"
  fi
done