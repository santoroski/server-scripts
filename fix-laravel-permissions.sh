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

    # Top-level: app user owns code, group is www-data
    echo "  🔧 Setting code ownership..."
    chown -R $APP_USER:$WEB_GROUP .

    # Runtime dirs: web user owns storage & cache
    if [ -d "storage" ] && [ -d "bootstrap/cache" ]; then
        echo "  🔧 Setting storage + cache ownership..."
        chown -R $WEB_USER:$WEB_GROUP storage bootstrap/cache
        chmod -R 775 storage bootstrap/cache

        # Clean and recreate framework subdirs
        echo "  🧹 Resetting storage/framework subdirs..."
        rm -rf storage/framework/cache/data/* || true
        rm -rf storage/framework/sessions/* || true
        rm -rf storage/framework/views/* || true

        mkdir -p storage/framework/cache/data
        mkdir -p storage/framework/sessions
        mkdir -p storage/framework/views

        chown -R $WEB_USER:$WEB_GROUP storage/framework
        chmod -R 775 storage/framework
    else
        echo -e "${RED}❌ storage/ or bootstrap/cache missing in $app${NC}"
    fi

    echo -e "  ${GREEN}✅ $app permissions fixed${NC}\n"
}

# Ensure root
if [ "$EUID" -ne 0 ]; then
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
for app in "${APPS[@]}"; do
    fix_app_permissions "$app"
done

echo -e "${GREEN}🎉 All Laravel apps permissions fixed!${NC}"
echo ""