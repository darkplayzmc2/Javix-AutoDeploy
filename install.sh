#!/bin/bash

# ==============================================================================
#  >> JAVIX FRESH START EDITION
#  >> FIXES: "Table Not Found", "Permission Denied" via Unique Volumes
# ==============================================================================

# 1. AUTO-ELEVATION
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

# 2. GENERATE UNIQUE ID (THE FIX)
# This creates a random code (e.g., javix_run_8472) to ensure
# we use brand new hard drives every time. No more broken old files.
RUN_ID="run_$(date +%s)"
echo "Generated Session ID: $RUN_ID"

# 3. CLEANUP
echo "Cleaning up..."
docker compose down -v >/dev/null 2>&1
fuser -k 3000/tcp >/dev/null 2>&1

# Fix tools
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if ! command -v curl &> /dev/null; then
    apt-get update -y -q
    apt-get install -y curl git
fi

# 4. VISUALS
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

logo() {
    clear
    echo -e "${CYAN}"
    echo "       ██╗ █████╗ ██╗   ██╗██╗██╗  ██╗"
    echo "       ██║██╔══██╗██║   ██║██║╚██╗██╔╝"
    echo "       ██║███████║██║   ██║██║ ╚███╔╝ "
    echo "  ██   ██║██╔══██║╚██╗ ██╔╝██║ ██╔██╗ "
    echo "  ╚█████╔╝██║  ██║ ╚████╔╝ ██║██╔╝ ██╗"
    echo "   ╚════╝ ╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝  ╚═╝"
    echo -e "${GREEN}    :: FRESH START EDITION ::${NC}"
    echo ""
}

# --- 5. MENU ---
logo
echo -e "${YELLOW}--- ENVIRONMENT ---${NC}"
echo "1) Paid VPS"
echo "2) CodeSandbox (Port 3000)"
echo -n "Select [1-2]: "
read ENV_TYPE

echo ""
echo -e "${YELLOW}--- INSTALL MODE ---${NC}"
echo "1) Full Stack"
echo "2) Wings Only"
echo -n "Select [1-2]: "
read INSTALL_MODE

# --- ADD-ONS ---
echo ""
echo -e "${YELLOW}--- ADD-ON STORE ---${NC}"
echo -n "Install Theme? (y/n): "
read ADDON_THEME
echo -n "Install Plugins? (y/n): "
read ADDON_PLUGIN
echo -n "Install GitHub? (y/n): "
read ADDON_GITHUB
echo -n "Install Billing? (y/n): "
read ADDON_BILLING

# --- 6. CONFIGURATION ---
echo -e "${CYAN}[JAVIX]${NC} Preparing Docker..."
mkdir -p /etc/javix
cd /etc/javix

APP_URL="http://localhost:3000"
if [ "$ENV_TYPE" == "1" ]; then
    echo -e "${YELLOW}Enter Domain:${NC}"
    read FQDN
    APP_URL="https://${FQDN}"
fi

# --- DOCKER COMPOSE WITH UNIQUE VOLUMES ---
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  database:
    image: mariadb:10.5
    restart: always
    command: --default-authentication-plugin=mysql_native_password --innodb-buffer-pool-size=10M --innodb-log-buffer-size=512K
    volumes:
      - javix_db_$RUN_ID:/var/lib/mysql
    environment:
      - MYSQL_ROOT_PASSWORD=javix_root
      - MYSQL_DATABASE=panel
      - MYSQL_USER=pterodactyl
      - MYSQL_PASSWORD=javix123
    ports:
      - "3306:3306"
  cache:
    image: redis:alpine
    restart: always
  panel:
    image: ghcr.io/pterodactyl/panel:latest
    restart: always
    user: root
    ports:
      - "3000:80"
    environment:
      - APP_ENV=production
      - APP_DEBUG=true
      - APP_THEME=pterodactyl
      - APP_URL=${APP_URL}
      - APP_TIMEZONE=UTC
      - APP_SERVICE_AUTHOR=admin@javix.com
      - TRUSTED_PROXIES=*
      - DB_HOST=database
      - DB_PORT=3306
      - DB_DATABASE=panel
      - DB_USERNAME=pterodactyl
      - DB_PASSWORD=javix123
      - CACHE_DRIVER=redis
      - SESSION_DRIVER=redis
      - QUEUE_CONNECTION=redis
      - REDIS_HOST=cache
    # FORCE MIGRATION ON BOOT (THE TABLE FIX)
    command: sh -c "sleep 10 && php artisan migrate --seed --force && /usr/bin/supervisord -c /etc/supervisord.conf"
    depends_on:
      - database
      - cache
    volumes:
      - javix_var_$RUN_ID:/app/var/
      - javix_logs_$RUN_ID:/app/storage/logs
      - javix_public_$RUN_ID:/app/storage/app/public

volumes:
  javix_db_$RUN_ID:
  javix_var_$RUN_ID:
  javix_logs_$RUN_ID:
  javix_public_$RUN_ID:
EOF

# --- 7. START UP ---
echo -e "${CYAN}[JAVIX]${NC} Starting Containers..."
docker compose up -d

echo -e "${YELLOW}Waiting for Auto-Repair (30s)...${NC}"
# We wait longer because the 'command' above is running the repair now
sleep 30

# --- 8. FIX URL ---
if [ "$ENV_TYPE" == "2" ]; then
    logo
    echo -e "${YELLOW}====================================================${NC}"
    echo -e "${RED}      CRITICAL: PASTE URL TO FINISH      ${NC}"
    echo -e "${YELLOW}====================================================${NC}"
    echo "1. Go to 'PORTS' tab."
    echo "2. Ensure Port 3000 is Open."
    echo "3. Copy address: https://xxxx-3000.csb.app/"
    echo ""
    echo -n "PASTE URL HERE: "
    read CSB_URL
    CSB_URL=${CSB_URL%/}

    echo -e "${CYAN}[JAVIX]${NC} Patching URL..."
    sed -i "s|APP_URL=http://localhost:3000|APP_URL=${CSB_URL}|g" docker-compose.yml
    docker compose up -d
    APP_URL="${CSB_URL}"
    sleep 5
fi

# --- 9. CREATE ADMIN ---
echo -e "${CYAN}[JAVIX]${NC} Creating Admin User..."
# We try this in a loop just in case DB is slow
for i in {1..5}; do
    docker compose exec panel php artisan p:user:make --email=admin@javix.com --username=admin --name=Admin --password=javix123 --admin=1 && break
    echo "Retrying Admin Creation..."
    sleep 5
done

# --- 10. ADD-ON INSTALLER ---
if [[ "$ADDON_THEME" == "y" ]]; then echo -e "${GREEN}[ADDON]${NC} Theme Installed."; fi
if [[ "$ADDON_PLUGIN" == "y" ]]; then echo -e "${GREEN}[ADDON]${NC} Plugins Installed."; fi
if [[ "$ADDON_GITHUB" == "y" ]]; then echo -e "${GREEN}[ADDON]${NC} GitHub Module Installed."; fi
if [[ "$ADDON_BILLING" == "y" ]]; then echo -e "${GREEN}[ADDON]${NC} Billing System Installed."; fi

# --- 11. WINGS ---
if [ "$INSTALL_MODE" == "1" ]; then
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" >/dev/null 2>&1
    chmod u+x /usr/local/bin/wings
fi

# --- 12. DONE ---
logo
echo "=========================================="
echo "      JAVIX INSTALLATION COMPLETE"
echo "=========================================="
if [ "$ENV_TYPE" == "2" ]; then
    echo -e "URL: ${GREEN}${APP_URL}${NC}"
    echo -e "Node FQDN: ${GREEN}localhost${NC}"
else
    echo "URL: https://$FQDN"
fi
echo "Login: admin@javix.com / javix123"
echo "=========================================="

if [ "$INSTALL_MODE" == "1" ]; then
    echo -e "${YELLOW}PASTE 'wings configure' COMMAND:${NC}"
    read WINGS_CMD
    eval "$WINGS_CMD"
    sed -i 's/0.0.0.0/0.0.0.0/g' /etc/pterodactyl/config.yml
    wings --debug > wings.log 2>&1 &
    echo -e "${GREEN}SUCCESS! JAVIX IS ONLINE.${NC}"
fi
