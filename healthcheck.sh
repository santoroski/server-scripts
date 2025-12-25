#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/home/ubuntu/.server-scripts.conf"
if [ -f "$SCRIPT_DIR/.server-scripts.conf" ]; then
  CONFIG_FILE="$SCRIPT_DIR/.server-scripts.conf"
fi
if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  . "$CONFIG_FILE"
fi

LOG_DIR="${LOG_DIR:-/home/ubuntu/logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/healthcheck.log"

# thresholds (configurable via ~/.server-scripts.conf)
MAX_DAILY_AGE_HOURS="${MAX_DAILY_AGE_HOURS:-36}"
MAX_WEEKLY_AGE_DAYS="${MAX_WEEKLY_AGE_DAYS:-8}"
DISK_USAGE_THRESHOLD="${DISK_USAGE_THRESHOLD:-90}"  # percent

notify() {
  if [ -x "$SCRIPT_DIR/pushover_notify.sh" ]; then
    "$SCRIPT_DIR/pushover_notify.sh" -t "$1" -m "$2" --priority "${3:-1}" || true
  else
    echo "$(date +%F_%H%M) - notify: $1 - $2" | tee -a "$LOG_FILE"
  fi
}

log() { echo "[$(date +%F_%H%M)] [HEALTHCHECK] $*" | tee -a "$LOG_FILE"; }

fail() {
  log "CRITICAL: $1"
  notify "Healthcheck failed" "$1" 2
  exit 2
}

ok() { log "OK: $1"; }

# 1) Check latest daily backup age in S3
if command -v aws >/dev/null 2>&1 && [ -n "${S3_BUCKET:-}" ]; then
  LATEST_DAILY_LINE=$(aws s3 ls "s3://$S3_BUCKET/daily/" | tail -n 1 || true)
  if [ -z "$LATEST_DAILY_LINE" ]; then
    fail "No daily backups found in s3://$S3_BUCKET/daily/"
  else
    # parse date/time
    FILE_DATE=$(echo "$LATEST_DAILY_LINE" | awk '{print $1" "$2}')
    FILE_EPOCH=$(date -d "$FILE_DATE" +%s)
    NOW_EPOCH=$(date +%s)
    AGE_HOURS=$(( (NOW_EPOCH - FILE_EPOCH) / 3600 ))
    if [ $AGE_HOURS -gt $MAX_DAILY_AGE_HOURS ]; then
      fail "Latest daily backup is $AGE_HOURS hours old (threshold: ${MAX_DAILY_AGE_HOURS}h)"
    else
      ok "Latest daily backup is $AGE_HOURS hours old"
    fi
  fi
else
  log "WARN: aws cli or S3_BUCKET not configured; skipping S3 daily check"
fi

# 2) Check latest weekly backup age in S3
if command -v aws >/dev/null 2>&1 && [ -n "${S3_BUCKET:-}" ]; then
  LATEST_WEEKLY_LINE=$(aws s3 ls "s3://$S3_BUCKET/weekly/" | tail -n 1 || true)
  if [ -z "$LATEST_WEEKLY_LINE" ]; then
    fail "No weekly backups found in s3://$S3_BUCKET/weekly/"
  else
    FILE_DATE=$(echo "$LATEST_WEEKLY_LINE" | awk '{print $1" "$2}')
    FILE_EPOCH=$(date -d "$FILE_DATE" +%s)
    NOW_EPOCH=$(date +%s)
    AGE_DAYS=$(( (NOW_EPOCH - FILE_EPOCH) / 86400 ))
    if [ $AGE_DAYS -gt $MAX_WEEKLY_AGE_DAYS ]; then
      fail "Latest weekly backup is $AGE_DAYS days old (threshold: ${MAX_WEEKLY_AGE_DAYS}d)"
    else
      ok "Latest weekly backup is $AGE_DAYS days old"
    fi
  fi
else
  log "WARN: aws cli or S3_BUCKET not configured; skipping S3 weekly check"
fi

# 3) Check disk usage on /
USAGE=$(df -P / | tail -n1 | awk '{print $5}' | tr -d '%')
if [ -n "$USAGE" ] && [ "$USAGE" -ge "$DISK_USAGE_THRESHOLD" ]; then
  fail "Root disk usage is ${USAGE}% (threshold ${DISK_USAGE_THRESHOLD}%)"
else
  ok "Root disk usage is ${USAGE}%"
fi

# 4) Check critical services (if present)
for svc in mysql nginx; do
  if systemctl list-units --type=service --all | grep -q "^$svc"; then
    if ! systemctl is-active --quiet "$svc"; then
      fail "Service $svc is not active"
    else
      ok "Service $svc is active"
    fi
  else
    log "INFO: Service $svc not present; skipping"
  fi
done

# All checks passed
log "All health checks passed"
exit 0
