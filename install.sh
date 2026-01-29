#!/bin/bash

# ==============================================================================
#  >> JAVIX INTERNAL STORAGE EDITION
#  >> FIXES: "Permission Denied" & "Table Not Found" by using Internal Volumes
# ==============================================================================

# 1. AUTO-ELEVATION
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

# 2. NUCLEAR CLEANUP
echo "Wiping all data to remove permission locks..."
docker compose down -v >/dev/null 2>&1
fuser -k 3000/tcp >/dev/null 2>&1

# Fix missing tools
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if ! command -v curl &> /dev/null; then
    apt-get update -y -q
    apt-get install -y curl git
fi

# 3. VISUALS
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
    echo -e "${GREEN}    :: INTERNAL STORAGE EDITION ::${NC}"
    echo ""
}

# --- 4. MENU ---
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

# --- 5. CONFIGURATION ---
echo -e "${CYAN}[JAVIX]${NC} Preparing Docker..."
mkdir -p /etc/javix
cd /etc/javix

APP_URL="http://localhost:3000"
APP_PORT="3000"

if [ "$ENV_TYPE" == "1" ]; then
    echo -e "${YELLOW}Enter Domain:${NC}"
    read FQDN
    APP_URL="https://${FQDN}"
    APP_PORT="80"
fi

# --- DOCKER COMPOSE (INTERNAL VOLUMES ONLY) ---
# We are NOT mapping volumes to ./var or ./logs.
# We are using named volumes "internal_logs" etc.
# This prevents CodeSandbox from blocking writes.

cat > docker-compose.yml <<EOF
version: '3.8'
services:
  database:
    image: mariadb:10.5
    restart: always
    command: --default-authentication-plugin=mysql_native_password --innodb-buffer-pool-size=20M --innodb-log-buffer-size=1M
    volumes:
      - internal_db:/var/lib/mysql
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
    user: root  # GOD MODE
    ports:
      - "${APP_PORT}:80"
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
    depends_on:
      - database
      - cache
    volumes:
      - internal_var:/app/var/
      - internal_logs:/app/storage/logs
      - internal_public:/app/storage/app/public

# DEFINING INTERNAL STORAGE
volumes:
  internal_db:
  internal_var:
  internal_logs:
  internal_public:
EOF

# --- 6. START UP ---
echo -e "${CYAN}[JAVIX]${NC} Starting Containers..."
docker compose up -d

echo -e "${YELLOW}Waiting for Internal Storage Setup (20s)...${NC}"
sleep 20

# --- 7. DEPENDENCY FIX & MIGRATION ---
logo
echo -e "${CYAN}[JAVIX]${NC} Installing Dependencies..."
docker compose exec panel apk update >/dev/null 2>&1
docker compose exec panel apk add --no-cache mysql-client mariadb-connector-c-dev

echo -e "${CYAN}[JAVIX]${NC} Creating Database Tables..."
# This will now work because logs are writing to internal memory, not blocked folders
docker compose exec panel php artisan migrate --seed --force

# --- 8. FIX URL (CodeSandbox Only) ---
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
logo
echo -e "${YELLOW}--- CREATE ADMIN USER ---${NC}"
echo -n "Enter Email: "
read ADMIN_EMAIL
echo -n "Enter Username: "
read ADMIN_USER
echo -n "Enter First Name: "
read ADMIN_FIRST
echo -n "Enter Last Name: "
read ADMIN_LAST
echo -n "Enter Password: "
read ADMIN_PASS

echo -e "${CYAN}[JAVIX]${NC} Creating User..."
docker compose exec panel php artisan p:user:make --email="$ADMIN_EMAIL" --username="$ADMIN_USER" --name="$ADMIN_FIRST" --name-last="$ADMIN_LAST" --password="$ADMIN_PASS" --admin=1

# --- 10. WINGS ---
if [ "$INSTALL_MODE" == "1" ]; then
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" >/dev/null 2>&1
    chmod u+x /usr/local/bin/wings
fi

# --- 11. DONE ---
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
echo "Login with the details you just entered."
echo "=========================================="

if [ "$INSTALL_MODE" == "1" ]; then
    echo -e "${YELLOW}PASTE 'wings configure' COMMAND:${NC}"
    read WINGS_CMD
    eval "$WINGS_CMD"
    sed -i 's/0.0.0.0/0.0.0.0/g' /etc/pterodactyl/config.yml
    sed -i 's/cd \/etc\/pterodactyl && sudo wings configure --panel-url//g' /etc/pterodactyl/config.yml 2>/dev/null
    
    echo "Starting Wings..."
    wings --debug > wings.log 2>&1 &
    echo -e "${GREEN}SUCCESS! JAVIX IS ONLINE.${NC}"
fi
