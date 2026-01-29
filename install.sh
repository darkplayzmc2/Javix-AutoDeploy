#!/bin/bash

# ==============================================================================
#  >> JAVIX PERMISSION FIX EDITION
#  >> FEATURES: Chmod 777 on volumes, Database Reset, Crash Logs
# ==============================================================================

# 1. CLEANUP (WIPE EVERYTHING)
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

echo "Forcing Cleanup..."
cd /etc/javix 2>/dev/null
# Stop containers and delete volumes (Fixes corruption)
docker compose down -v 2>/dev/null
pkill cloudflared 2>/dev/null
fuser -k 8081/tcp >/dev/null 2>&1

# Fix missing tools
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if ! command -v curl &> /dev/null; then
    apt-get update -y -q
    apt-get install -y curl git
fi

# 2. VISUALS
CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
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
    echo -e "${GREEN}    :: PERMISSION FIX EDITION ::${NC}"
    echo ""
}

# --- 3. MENU SYSTEM ---
logo
echo -e "${YELLOW}--- ENVIRONMENT ---${NC}"
echo "1) Paid VPS"
echo "2) CodeSandbox (Tunnel Mode)"
echo -n "Select [1-2]: "
read ENV_TYPE

echo ""
echo -e "${YELLOW}--- INSTALL MODE ---${NC}"
echo "1) Full Stack"
echo "2) Wings Only"
echo -n "Select [1-2]: "
read INSTALL_MODE

# --- 4. CONFIGURATION ---
echo -e "${CYAN}[JAVIX]${NC} Preparing Workspace..."
mkdir -p /etc/javix
cd /etc/javix

# PRE-CREATE DATA FOLDERS TO FIX PERMISSIONS
mkdir -p /etc/javix/database
mkdir -p /etc/javix/var
mkdir -p /etc/javix/logs
mkdir -p /etc/javix/public

# FORCE 777 PERMISSIONS (The Fix)
echo -e "${YELLOW}Fixing Permissions (chmod 777)...${NC}"
chmod -R 777 /etc/javix

# If CodeSandbox, use placeholder URL
if [ "$ENV_TYPE" == "2" ]; then
    APP_URL="http://localhost"
else
    echo -e "${YELLOW}Enter Domain:${NC}"
    read FQDN
    APP_URL="https://${FQDN}"
fi

# GENERATE DOCKER COMPOSE
cat > docker-compose.yml <<EOF
version: '3.8'
services:
  database:
    image: mariadb:10.5
    restart: always
    command: --default-authentication-plugin=mysql_native_password --innodb-buffer-pool-size=10M --innodb-log-buffer-size=512K
    volumes:
      - "./database:/var/lib/mysql"
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
    ports:
      - "8081:80"
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
      - "./var/:/app/var/"
      - "./logs:/app/storage/logs"
      - "./public:/app/storage/app/public"
EOF

# --- 5. START UP ---
echo -e "${CYAN}[JAVIX]${NC} Starting Containers..."
docker compose up -d

echo -e "${YELLOW}Waiting for Panel to boot (Max 60s)...${NC}"
# Wait Loop
for i in {1..30}; do
    if curl -s http://localhost:8081 >/dev/null; then
        echo -e "${GREEN}Panel is ONLINE!${NC}"
        PANEL_READY=true
        break
    fi
    echo -n "."
    sleep 2
done

# IF PANEL FAILED, SHOW LOGS
if [ "$PANEL_READY" != "true" ]; then
    echo ""
    echo -e "${RED}PANEL FAILED TO START!${NC}"
    echo -e "${YELLOW}--- ERROR LOGS ---${NC}"
    docker compose logs panel | tail -n 20
    echo -e "${YELLOW}------------------${NC}"
    echo "Check the errors above."
    exit 1
fi

# --- 6. START TUNNEL ---
if [ "$ENV_TYPE" == "2" ]; then
    echo -e "${CYAN}[JAVIX]${NC} Starting Magic Tunnel..."
    if ! command -v cloudflared &> /dev/null; then
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb >/dev/null 2>&1
        dpkg -i cloudflared.deb >/dev/null 2>&1
    fi
    
    cloudflared tunnel --url http://localhost:8081 > tunnel.log 2>&1 &
    sleep 10
    TUNNEL_URL=$(grep -o 'https://.*\.trycloudflare.com' tunnel.log | head -1)
    
    # Retry if empty
    if [ -z "$TUNNEL_URL" ]; then
        pkill cloudflared
        sleep 2
        cloudflared tunnel --url http://localhost:8081 > tunnel.log 2>&1 &
        sleep 10
        TUNNEL_URL=$(grep -o 'https://.*\.trycloudflare.com' tunnel.log | head -1)
    fi
    
    echo -e "${CYAN}[JAVIX]${NC} Patching URL: ${TUNNEL_URL}"
    sed -i "s|APP_URL=http://localhost|APP_URL=${TUNNEL_URL}|g" docker-compose.yml
    docker compose up -d
    APP_URL="${TUNNEL_URL}"
fi

# --- 7. CREATE ADMIN ---
echo -e "${CYAN}[JAVIX]${NC} Creating Admin User..."
docker compose exec -T panel php artisan key:generate --force >/dev/null 2>&1
docker compose exec -T panel php artisan p:user:make --email=admin@javix.com --username=admin --name=Admin --password=javix123 --admin=1 >/dev/null 2>&1

# --- 8. WINGS ---
if [ "$INSTALL_MODE" == "1" ]; then
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" >/dev/null 2>&1
    chmod u+x /usr/local/bin/wings
fi

# --- 9. OUTPUT ---
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
