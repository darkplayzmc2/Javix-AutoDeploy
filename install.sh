#!/bin/bash

# ==============================================================================
#  >> JAVIX-AUTODEPLOY | FINAL EDITION
#  >> FEATURES: Auto-FQDN, Auto-Wings Start, Clean Exit
# ==============================================================================

# --- 0. AUTO-ELEVATION ---
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

# --- 1. VISUALS ---
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
    echo -e "${GREEN}      :: SYSTEM ONLINE ::${NC}"
    echo ""
}

# --- 2. CLEANUP (Wipe old data) ---
clear
echo -e "${CYAN}[JAVIX]${NC} Cleaning up old installation..."
rm -rf /var/www/pterodactyl /etc/pterodactyl /usr/local/bin/wings
docker rm -f $(docker ps -a -q) >/dev/null 2>&1
echo -e "${GREEN}[DONE]${NC}"

# --- 3. GENERATE FQDN (TUNNEL) ---
echo -e "${CYAN}[JAVIX]${NC} Setting up Cloudflare Tunnel..."
apt-get update -q >/dev/null 2>&1
apt-get install -y curl tar unzip git jq certbot >/dev/null 2>&1

if ! command -v cloudflared &> /dev/null; then
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb >/dev/null 2>&1
    dpkg -i cloudflared.deb >/dev/null 2>&1
fi

# Start Tunnel & Wait for URL
cloudflared tunnel --url http://localhost:80 > tunnel.log 2>&1 &
echo -e "${YELLOW}Waiting for Auto-FQDN...${NC}"
sleep 10

# Capture URL
AUTO_URL=$(grep -o 'https://.*\.trycloudflare.com' tunnel.log | head -1)
CLEAN_FQDN=${AUTO_URL//https:\/\//}

if [ -z "$AUTO_URL" ]; then
    echo -e "${RED}Tunnel failed. Retrying...${NC}"
    pkill cloudflared
    sleep 2
    cloudflared tunnel --url http://localhost:80 > tunnel.log 2>&1 &
    sleep 10
    AUTO_URL=$(grep -o 'https://.*\.trycloudflare.com' tunnel.log | head -1)
    CLEAN_FQDN=${AUTO_URL//https:\/\//}
fi

# --- 4. INSTALL PANEL ---
echo -e "${CYAN}[JAVIX]${NC} Installing Panel on: ${YELLOW}${AUTO_URL}${NC}"

# Install Docker
if ! command -v docker &> /dev/null; then
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash >/dev/null 2>&1
fi
systemctl enable --now docker >/dev/null 2>&1

# Install DB & PHP
apt-get install -y mariadb-server mariadb-client php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} >/dev/null 2>&1
systemctl enable --now mariadb >/dev/null 2>&1

# Setup DB
mysql -u root -e "CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY 'javix123';"
mysql -u root -e "CREATE DATABASE IF NOT EXISTS panel;"
mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
mysql -u root -e "FLUSH PRIVILEGES;"

# Setup Panel Files
mkdir -p /var/www/pterodactyl
cd /var/www/pterodactyl
curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz >/dev/null 2>&1
tar -xzvf panel.tar.gz >/dev/null 2>&1
chmod -R 755 storage bootstrap/cache

# Install Composer
curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >/dev/null 2>&1
cp .env.example .env
composer install --no-dev --optimize-autoloader --no-interaction >/dev/null 2>&1
php artisan key:generate --force >/dev/null 2>&1

# Inject FQDN
sed -i 's/DB_PASSWORD=/DB_PASSWORD=javix123/g' .env
sed -i "s|APP_URL=http://localhost|APP_URL=${AUTO_URL}|g" .env
sed -i "s|APP_URL=https://panel.example.com|APP_URL=${AUTO_URL}|g" .env

php artisan migrate --seed --force >/dev/null 2>&1
php artisan p:user:make --email=admin@javix.com --username=admin --name=Admin --password=javix123 --admin=1 >/dev/null 2>&1

# Start Queue
php artisan queue:work --queue=high,standard,low --sleep=3 --tries=3 >/dev/null 2>&1 &

# --- 5. INSTALL WINGS ---
echo -e "${CYAN}[JAVIX]${NC} Installing Wings..."
mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" >/dev/null 2>&1
chmod u+x /usr/local/bin/wings

# --- 6. THE FINAL CONFIGURATION STEP ---
clear
echo -e "${CYAN}====================================================${NC}"
echo -e "${GREEN}      PANEL INSTALLED SUCCESSFULLY ${NC}"
echo -e "${CYAN}====================================================${NC}"
echo ""
echo -e "PANEL URL:    ${YELLOW}${AUTO_URL}${NC}"
echo -e "LOGIN:        ${GREEN}admin@javix.com${NC} / ${GREEN}javix123${NC}"
echo ""
echo -e "${YELLOW}--- ACTION REQUIRED ---${NC}"
echo "1. Login to your Panel (${AUTO_URL})"
echo "2. Go to Admin -> Nodes -> Create New"
echo -e "3. In 'FQDN' box, paste this: ${CYAN}${CLEAN_FQDN}${NC}"
echo "4. Click Create -> Click Configuration -> Copy the Command."
echo ""
echo -e "${CYAN}[INPUT] Paste the 'wings configure' command below and press ENTER:${NC}"
read WINGS_CMD

# --- 7. AUTO-EXECUTE & FINISH ---
echo -e "${YELLOW}Configuring Wings...${NC}"
eval "$WINGS_CMD"

echo -e "${YELLOW}Starting Wings in background...${NC}"
# Start Wings in background, detached so it doesn't die when script ends
wings --debug > wings.log 2>&1 &

# CLEAR AND SHOW FINAL LOGO
sleep 3
logo
echo -e "   ${GREEN}SUCCESS! JAVIX PANEL & WINGS ARE ONLINE.${NC}"
echo -e "   ${CYAN}You can now close this terminal window.${NC}"
echo ""
