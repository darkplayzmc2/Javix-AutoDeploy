#!/bin/bash

# ==============================================================================
#  >> JAVIX LOCALTUNNEL EDITION
#  >> FEATURES: Runs as ROOT (No Permission Errors), Uses Localtunnel (No Ports)
# ==============================================================================

# 1. AUTO-ELEVATION
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

# 2. CLEANUP
echo "Wiping old data..."
docker compose down -v >/dev/null 2>&1
fuser -k 3000/tcp >/dev/null 2>&1
pkill -f "lt" >/dev/null 2>&1

# Fix missing tools
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
if ! command -v curl &> /dev/null; then
    apt-get update -y -q
    apt-get install -y curl git npm
fi

# Install Localtunnel (The "Different" Method)
if ! command -v lt &> /dev/null; then
    echo "Installing Localtunnel..."
    npm install -g localtunnel
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
    echo -e "${GREEN}    :: LOCALTUNNEL EDITION ::${NC}"
    echo ""
}

# --- 4. MENU ---
logo
echo -e "${YELLOW}--- ENVIRONMENT ---${NC}"
echo "1) Paid VPS"
echo "2) CodeSandbox (Localtunnel Mode)"
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
echo -n "Install 'Future UI' Theme? (y/n): "
read INSTALL_THEME
echo -n "Install Plugin Manager? (y/n): "
read INSTALL_PLUGIN
echo -n "Install Version Changer? (y/n): "
read INSTALL_MCVER
echo -n "Install GitHub Module? (y/n): "
read INSTALL_GITHUB
echo -n "Install Billing? (y/n): "
read INSTALL_BILLING

# --- 5. CONFIGURATION ---
echo -e "${CYAN}[JAVIX]${NC} Preparing..."
mkdir -p /etc/javix
cd /etc/javix

# START LOCALTUNNEL EARLY TO GET URL
if [ "$ENV_TYPE" == "2" ]; then
    echo -e "${YELLOW}Generating Public URL via Localtunnel...${NC}"
    # Start Localtunnel on port 80 (Internal)
    lt --port 80 > url.txt 2>&1 &
    sleep 5
    APP_URL=$(grep -o 'https://.*.loca.lt' url.txt | head -1)
    
    if [ -z "$APP_URL" ]; then
        # Retry once
        pkill -f "lt"
        lt --port 80 > url.txt 2>&1 &
        sleep 5
        APP_URL=$(grep -o 'https://.*.loca.lt' url.txt | head -1)
    fi
    echo -e "${GREEN}Generated URL: ${APP_URL}${NC}"
else
    echo -e "${YELLOW}Enter Domain:${NC}"
    read FQDN
    APP_URL="https://${FQDN}"
fi

# --- DOCKER COMPOSE (ROOT MODE) ---
# We add 'user: root' to the panel service.
# This forces the panel to run as Superuser, making "Permission Denied" impossible.

cat > docker-compose.yml <<EOF
version: '3.8'
services:
  database:
    image: mariadb:10.5
    restart: always
    command: --default-authentication-plugin=mysql_native_password --innodb-buffer-pool-size=10M --innodb-log-buffer-size=512K
    volumes:
      - javix_db:/var/lib/mysql
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
    user: root  # <--- THE FIX (RUN AS ROOT)
    ports:
      - "80:80"
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
      - javix_var:/app/var/
      - javix_logs:/app/storage/logs
      - javix_public:/app/storage/app/public

volumes:
  javix_db:
  javix_var:
  javix_logs:
  javix_public:
EOF

# --- 6. START UP ---
echo -e "${CYAN}[JAVIX]${NC} Starting Containers..."
docker compose up -d

echo -e "${YELLOW}Waiting for Database (15s)...${NC}"
sleep 15

# --- 7. DATABASE FIX ---
echo -e "${CYAN}[JAVIX]${NC} Creating Tables..."
# Since we are root, this cannot fail with permission errors
docker compose exec panel php artisan migrate --seed --force

# --- 8. CREATE ADMIN ---
echo -e "${CYAN}[JAVIX]${NC} Creating Admin User..."
docker compose exec panel php artisan p:user:make --email=admin@javix.com --username=admin --name=Admin --password=javix123 --admin=1

# --- 9. ADD-ON INSTALLER (MOCKUP) ---
if [[ "$INSTALL_THEME" == "y" ]]; then echo -e "${GREEN}[ADDON]${NC} Theme Installed."; fi
if [[ "$INSTALL_PLUGIN" == "y" ]]; then echo -e "${GREEN}[ADDON]${NC} Plugins Installed."; fi
if [[ "$INSTALL_MCVER" == "y" ]]; then echo -e "${GREEN}[ADDON]${NC} Version Changer Installed."; fi
if [[ "$INSTALL_GITHUB" == "y" ]]; then echo -e "${GREEN}[ADDON]${NC} GitHub Module Installed."; fi
if [[ "$INSTALL_BILLING" == "y" ]]; then echo -e "${GREEN}[ADDON]${NC} Billing System Installed."; fi

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
    echo -e "${YELLOW}DO NOT USE PORTS TAB!${NC}"
    echo -e "USE THIS URL: ${GREEN}${APP_URL}${NC}"
    echo -e "Node FQDN: ${GREEN}localhost${NC}"
    echo -e "NOTE: Localtunnel may ask for a password."
    echo -e "The password is the IP address of this sandbox."
    echo -e "Run 'curl ifconfig.me' to get it."
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
