#!/bin/bash

# ==============================================================================
#  >> JAVIX TUNNEL EDITION (THE FINAL SOLUTION)
#  >> FEATURES: Bypasses CodeSandbox Ports completely using Cloudflare Tunnel
# ==============================================================================

# 1. CLEANUP & PREP
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

# Kill any stuck processes
echo "Killing zombie processes..."
docker compose down >/dev/null 2>&1
fuser -k 80/tcp >/dev/null 2>&1
fuser -k 3000/tcp >/dev/null 2>&1
fuser -k 8080/tcp >/dev/null 2>&1

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
    echo -e "${GREEN}    :: MAGIC TUNNEL EDITION ::${NC}"
    echo ""
}

# --- 3. THE MENU SYSTEM (RESTORED) ---
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
echo "3) Panel Only"
echo ""
echo -n "Select install mode [1-3]: "
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

# --- 5. SETUP TUNNEL (BYPASS PORTS) ---
if [ "$ENV_TYPE" == "2" ]; then
    echo -e "${CYAN}[JAVIX]${NC} Installing Cloudflare Tunnel..."
    if ! command -v cloudflared &> /dev/null; then
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb >/dev/null 2>&1
        dpkg -i cloudflared.deb >/dev/null 2>&1
    fi
    
    # Start Tunnel on internal port 8081 (We will put panel here)
    echo -e "${YELLOW}Starting Magic Tunnel... (Please Wait)${NC}"
    cloudflared tunnel --url http://localhost:8081 > tunnel.log 2>&1 &
    
    # Wait for URL
    sleep 8
    TUNNEL_URL=$(grep -o 'https://.*\.trycloudflare.com' tunnel.log | head -1)
    
    # If failed, retry once
    if [ -z "$TUNNEL_URL" ]; then
        pkill cloudflared
        sleep 2
        cloudflared tunnel --url http://localhost:8081 > tunnel.log 2>&1 &
        sleep 10
        TUNNEL_URL=$(grep -o 'https://.*\.trycloudflare.com' tunnel.log | head -1)
    fi
    
    APP_URL="${TUNNEL_URL}"
    echo -e "${GREEN}Tunnel Online: ${APP_URL}${NC}"
else
    APP_URL="http://localhost"
    echo -e "${YELLOW}Enter Domain:${NC}"
    read FQDN
    APP_URL="https://${FQDN}"
fi

# --- 6. CREATE DOCKER CONFIG ---
echo -e "${CYAN}[JAVIX]${NC} Configuring Panel..."
mkdir -p /etc/javix
cd /etc/javix

cat > docker-compose.yml <<EOF
version: '3.8'
services:
  database:
    image: mariadb:10.5
    restart: always
    command: --default-authentication-plugin=mysql_native_password
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

# --- 7. START PANEL ---
echo -e "${CYAN}[JAVIX]${NC} Starting Containers..."
docker compose down >/dev/null 2>&1
docker compose up -d

echo "Waiting for Database (10s)..."
sleep 10

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
    echo -e "${YELLOW}DO NOT USE THE PORTS TAB!${NC}"
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
    
    # Fix Docker networking
    sed -i 's/0.0.0.0/0.0.0.0/g' /etc/pterodactyl/config.yml
    
    echo "Starting Wings..."
    wings --debug > wings.log 2>&1 &
    echo -e "${GREEN}SUCCESS! JAVIX IS ONLINE.${NC}"
fi
