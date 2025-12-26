#!/bin/bash
# filepath: /var/www/laravel/fix-laravel-permissions.sh

set -e  # Exit on any error

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Configuration
APP_USER="blogger"
WEB_USER="www-data"
WEB_GROUP="www-data"
BASE_PATH="/var/www/laravel"
APPS=("gamenight" "tools" "microblog" "cozy")

# Safety switches
# If your Laravel apps use the default file-based session driver, clearing
# storage/framework/sessions will log users out.
CLEAR_SESSIONS=0

DRY_RUN=0
TARGET_APP=""
for arg in "$@"; do
    case "$arg" in
        --clear-sessions)
            CLEAR_SESSIONS=1
            ;;
        --dry-run)
            DRY_RUN=1
            ;;
        --app=*)
            TARGET_APP="${arg#*=}"
            ;;
        -h|--help)
            echo "Usage: $0 [--clear-sessions] [--dry-run] [--app=<name>]"
            echo "  --clear-sessions  Also clears storage/framework/sessions (logs users out if using file sessions)"
            echo "  --dry-run         Show what would be done without making changes"
            echo "  --app=<name>      Run only for the named app (e.g. --app=cozy)"
            exit 0
            ;;
    esac
done

run_cmd() {
    # helper: show commands in dry-run, otherwise execute
    if [ "$DRY_RUN" -eq 1 ]; then
        echo "DRY-RUN: $*"
    else
        eval "$@"
    fi
}

echo -e "${YELLOW}=== Laravel Permission Fix Script ===${NC}"
echo "Fixing permissions for: ${APPS[@]}"
echo "App owner: $APP_USER"
echo "Web user/group: $WEB_USER:$WEB_GROUP"
echo ""

fix_app_permissions() {
    local app=$1
    local app_path="$BASE_PATH/$app"

    echo -e "${YELLOW}Processing: $app${NC}"

    if [ ! -d "$app_path" ]; then
        echo -e "${RED}❌ Directory $app_path does not exist!${NC}"
        return 1
    fi

    cd "$app_path"

    # helper wrapper for safety
    _run() { run_cmd "$1"; }

    # OPTIMIZATION 1: Only fix ownership on root files, not recursive (less IO)
    echo "  🔧 Setting base ownership (non-recursive)..."
    _run "chown $APP_USER:$WEB_GROUP ." || true

    # If you MUST recurse code, consider limiting to specific dirs to avoid node_modules / vendor
    # Example: chown -R $APP_USER:$WEB_GROUP ./app ./config ./public ./resources ./routes || true

    # Runtime dirs: web user owns storage & cache (recursive here is expected)
    if [ -d "storage" ] && [ -d "bootstrap/cache" ]; then
        echo "  🔧 Setting storage + cache ownership..."
        _run "chown -R $WEB_USER:$WEB_GROUP storage bootstrap/cache" || true
        _run "chmod -R 775 storage bootstrap/cache" || true

        # Clean and recreate framework subdirs
        echo "  🧹 Resetting storage/framework subdirs..."
        # Use find -delete to avoid shell glob expansion and memory spikes
        _run "find storage/framework/cache/data -mindepth 1 -delete 2>/dev/null" || true
        _run "find storage/framework/views -mindepth 1 -delete 2>/dev/null" || true

        if [ "$CLEAR_SESSIONS" -eq 1 ]; then
            echo "  ⚠️  Clearing sessions (may log users out)..."
            # Use find -delete for sessions as well (opt-in only)
            _run "find storage/framework/sessions -mindepth 1 -delete 2>/dev/null" || true
        fi

        # Re-ensure structure exists (in case find was too aggressive)
        _run "mkdir -p storage/framework/cache/data" || true
        _run "mkdir -p storage/framework/sessions" || true
        _run "mkdir -p storage/framework/views" || true

        # Ensure framework dir is owned & writable
        _run "chown -R $WEB_USER:$WEB_GROUP storage/framework" || true
        _run "chmod -R 775 storage/framework" || true
    else
        echo -e "${RED}❌ storage/ or bootstrap/cache missing in $app${NC}"
    fi

    echo -e "  ${GREEN}✅ $app permissions fixed${NC}\n"
}

# Ensure root (unless running in dry-run mode)
if [ "$DRY_RUN" -ne 1 ] && [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ Please run as root (use sudo)${NC}"
    exit 1
fi

# Ensure users exist
for u in "$APP_USER" "$WEB_USER"; do
    if ! id "$u" &>/dev/null; then
        echo -e "${RED}❌ User $u does not exist!${NC}"
        exit 1
    fi
done

# Process apps
if [ -n "$TARGET_APP" ]; then
    echo "Running for single app: $TARGET_APP"
    fix_app_permissions "$TARGET_APP"
else
    for app in "${APPS[@]}"; do
        fix_app_permissions "$app"
    done
fi

echo -e "${GREEN}🎉 All Laravel apps permissions fixed!${NC}"
echo ""