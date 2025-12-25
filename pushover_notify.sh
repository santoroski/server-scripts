#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="/home/ubuntu/.server-scripts.conf"
# Fallback to repo config if present
if [ -f "$SCRIPT_DIR/.server-scripts.conf" ]; then
  CONFIG_FILE="$SCRIPT_DIR/.server-scripts.conf"
fi

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck source=/dev/null
  . "$CONFIG_FILE"
fi

PUSH_TOKEN="${PUSHOVER_API_TOKEN:-}"
PUSH_USER="${PUSHOVER_USER_KEY:-}"
LOG_DIR="${LOG_DIR:-/home/ubuntu/logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/pushover_notify.log"

usage() {
  cat <<EOF
Usage: $0 -t "Title" -m "Message" [--priority N] [--sound SOUND] [--html]

Environment: set PUSHOVER_API_TOKEN and PUSHOVER_USER_KEY in your config (~/.server-scripts.conf)
Priority: -2 (lowest) .. 2 (emergency)
Example: $0 -t "Backup failed" -m "mysqldump returned non-zero" --priority 1
EOF
  exit 1
}

if [ -z "$PUSH_TOKEN" ] || [ -z "$PUSH_USER" ]; then
  echo "ERROR: PUSHOVER_API_TOKEN or PUSHOVER_USER_KEY not set in $CONFIG_FILE" | tee -a "$LOG_FILE"
  exit 2
fi

# Parse args
TITLE=""
MESSAGE=""
PRIORITY=0
SOUND=""
HTML=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    -t|--title)
      TITLE="$2"; shift 2;;
    -m|--message)
      MESSAGE="$2"; shift 2;;
    --priority)
      PRIORITY="$2"; shift 2;;
    --sound)
      SOUND="$2"; shift 2;;
    --html)
      HTML=1; shift 1;;
    -h|--help)
      usage;;
    *)
      echo "Unknown arg: $1"; usage;;
  esac
done

if [ -z "$TITLE" ] || [ -z "$MESSAGE" ]; then
  usage
fi

send_payload() {
  local payload=(--form-string "token=$PUSH_TOKEN" --form-string "user=$PUSH_USER" --form-string "title=$TITLE" --form-string "message=$MESSAGE" --form-string "priority=$PRIORITY")
  [ -n "$SOUND" ] && payload+=(--form-string "sound=$SOUND")
  [ "$HTML" -eq 1 ] && payload+=(--form-string "html=1")

  curl -sS "https://api.pushover.net/1/messages.json" "${payload[@]}" -o /tmp/pushover_response.json
  cat /tmp/pushover_response.json >> "$LOG_FILE"
}

# Retry with backoff
MAX_RETRIES=3
for i in $(seq 1 $MAX_RETRIES); do
  if send_payload; then
    echo "$(date +%F_%T) - Pushover sent: title='$TITLE' priority=$PRIORITY" | tee -a "$LOG_FILE"
    rm -f /tmp/pushover_response.json
    exit 0
  else
    echo "$(date +%F_%T) - Pushover attempt $i failed" | tee -a "$LOG_FILE"
    sleep $((i * 2))
  fi
done

echo "$(date +%F_%T) - Pushover failed after $MAX_RETRIES attempts" | tee -a "$LOG_FILE"
exit 1
