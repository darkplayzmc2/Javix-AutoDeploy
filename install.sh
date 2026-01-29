#!/bin/bash

# ==============================================================================
#  >> JAVIX STABILITY EDITION
#  >> FEATURES: Low-RAM Database, "Wait-for-Panel" Check, Tunnel Fix
# ==============================================================================

# 1. CLEANUP & PREP
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

# Kill old processes
echo "Cleaning up..."
docker compose down >/dev/null 2>&1
pkill cloudflared
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
    echo -e "${GREEN}    :: STABILITY EDITION ::${NC}"
    echo ""
}

# --- 3. THE MENU SYSTEM ---
logo
echo -e "${YELLOW}--- ENVIRONMENT SELECTION ---${NC}"
echo "1) Paid VPS (DigitalOcean, AWS)"
echo "2) CodeSandbox (Free - Uses Magic Tunnel)"
echo ""
echo -n "Select environment [1-2]: "
read ENV_TYPE

echo ""
echo -e "${YELLOW}--- COMPONENT SELECTION ---${NC}"
echo "1) Full Stack (Panel + Wings)"
echo "2) Wings Only"
echo ""
echo -n "Select install mode [1-2]: "
read INSTALL_MODE

# --- ADD-ONS ---
echo ""
echo -e "${YELLOW}--- ADD-ON STORE ---${NC}"
echo -n "Install 'Future UI' Theme? (y/n): "
read INSTALL_THEME
echo -n "Install Plugin Manager System? (y/n): "
read INSTALL_PLUGIN
echo -n "Install Minecraft Version Changer? (y/n): "
read INSTALL_MCVER

# --- 4. INSTALL DOCKER ---
logo
echo -e "${CYAN}[JAVIX]${NC} checking Docker..."
if ! command -v docker &> /dev/null; then
    curl -fsSL https://get.docker.com -o get-docker.sh
    sh get-docker.sh >/dev/null 2>&1
fi

# --- 5. CONFIGURATION ---
echo -e "${CYAN}[JAVIX]${NC} Configuring Low-RAM Mode..."
mkdir -p /etc/javix
cd /etc/javix

# If CodeSandbox, we use a placeholder URL first
if [ "$ENV_TYPE" == "2" ]; then
    APP_URL="http://localhost"
else
    echo -e "${YELLOW}Enter Domain:${NC}"
    read FQDN
    APP_URL="https://${FQDN}"
fi

cat > docker-compose.yml <<EOF
version: '3.8'
services:
  database:
    image: mariadb:10.5
    restart: always
    command: --default-authentication-plugin=mysql_native_password --innodb-buffer-pool-size=10M --innodb-log-buffer-size=512K
    volumes:
      - "/var/lib/javix/database:/var/lib/mysql"
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
      - APP_DEBUG=false
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
      - "/var/www/javix/var/:/app/var/"
      - "/var/www/javix/storage/logs:/app/storage/logs"
      - "/var/www/javix/storage/app/public:/app/storage/app/public"
EOF

# --- 6. START PANEL (WAIT FOR BOOT) ---
echo -e "${CYAN}[JAVIX]${NC} Starting Containers..."
docker compose down >/dev/null 2>&1
docker compose up -d

echo -e "${YELLOW}Waiting for Panel to boot (this fixes 502 error)...${NC}"
# Loop until port 8081 is active
for i in {1..30}; do
    if curl -s http://localhost:8081 >/dev/null; then
        echo -e "${GREEN}Panel is UP!${NC}"
        break
    fi
    echo -n "."
    sleep 2
done

# --- 7. START TUNNEL (ONLY IF PANEL IS UP) ---
if [ "$ENV_TYPE" == "2" ]; then
    echo -e "${CYAN}[JAVIX]${NC} Installing Cloudflare Tunnel..."
    if ! command -v cloudflared &> /dev/null; then
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb >/dev/null 2>&1
        dpkg -i cloudflared.deb >/dev/null 2>&1
    fi
    
    echo -e "${YELLOW}Starting Magic Tunnel...${NC}"
    cloudflared tunnel --url http://localhost:8081 > tunnel.log 2>&1 &
    
    sleep 8
    TUNNEL_URL=$(grep -o 'https://.*\.trycloudflare.com' tunnel.log | head -1)
    
    # Retry logic
    if [ -z "$TUNNEL_URL" ]; then
        pkill cloudflared
        sleep 2
        cloudflared tunnel --url http://localhost:8081 > tunnel.log 2>&1 &
        sleep 10
        TUNNEL_URL=$(grep -o 'https://.*\.trycloudflare.com' tunnel.log | head -1)
    fi
    
    # FIX PANEL URL
    echo -e "${CYAN}[JAVIX]${NC} Patching Panel URL to: ${TUNNEL_URL}"
    sed -i "s|APP_URL=http://localhost|APP_URL=${TUNNEL_URL}|g" docker-compose.yml
    docker compose up -d
    
    APP_URL="${TUNNEL_URL}"
fi

# --- 8. CREATE ADMIN ---
echo -e "${CYAN}[JAVIX]${NC} Creating Admin User..."
docker compose exec -T panel php artisan key:generate --force >/dev/null 2>&1
docker compose exec -T panel php artisan p:user:make --email=admin@javix.com --username=admin --name=Admin --password=javix123 --admin=1 >/dev/null 2>&1

# --- 9. INSTALL WINGS ---
if [ "$INSTALL_MODE" == "1" ] || [ "$INSTALL_MODE" == "2" ]; then
    echo "Installing Wings..."
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" >/dev/null 2>&1
    chmod u+x /usr/local/bin/wings
fi

# --- 10. FINAL OUTPUT ---
logo
echo "=========================================="
echo "      JAVIX INSTALLATION COMPLETE"
echo "=========================================="
if [ "$ENV_TYPE" == "2" ]; then
    echo -e "${YELLOW}DO NOT USE PORTS TAB!${NC}"
    echo -e "USE THIS URL: ${GREEN}${APP_URL}${NC}"
    echo -e "Node FQDN: ${GREEN}localhost${NC}"
else
    echo "URL: https://$FQDN"
fi
echo "=========================================="
echo "Login: admin@javix.com / javix123"
echo "=========================================="

if [ "$INSTALL_MODE" == "1" ] || [ "$INSTALL_MODE" == "2" ]; then
    echo -e "${YELLOW}PASTE 'wings configure' COMMAND:${NC}"
    read WINGS_CMD
    echo "Configuring..."
    eval "$WINGS_CMD"
    
    sed -i 's/0.0.0.0/0.0.0.0/g' /etc/pterodactyl/config.yml
    
    echo "Starting Wings..."
    wings --debug > wings.log 2>&1 &
    echo -e "${GREEN}SUCCESS! JAVIX IS ONLINE.${NC}"
fi
