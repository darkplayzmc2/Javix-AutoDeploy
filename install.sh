#!/bin/bash

# ==============================================================================
#  >> JAVIX-AUTODEPLOY | CHEAT SHEET EDITION
#  >> FEATURE: Tells you exactly what to type in the Create Node page.
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
    echo -e "${GREEN}    :: CHEAT SHEET MODE ::${NC}"
    echo ""
}

# --- 2. CLEANUP ---
logo
echo -e "${CYAN}[JAVIX]${NC} Cleaning up old files..."
rm -rf /var/www/pterodactyl /etc/pterodactyl /usr/local/bin/wings
docker rm -f $(docker ps -a -q) >/dev/null 2>&1
echo -e "${GREEN}[DONE]${NC}"

# --- 3. INSTALL DEPENDENCIES ---
echo -e "${CYAN}[JAVIX]${NC} Installing System Requirements..."
apt-get update -q >/dev/null 2>&1
apt-get install -y curl tar unzip git jq certbot mariadb-server mariadb-client >/dev/null 2>&1
apt-get install -y php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} >/dev/null 2>&1

# Install Docker
if ! command -v docker &> /dev/null; then
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash >/dev/null 2>&1
fi
systemctl enable --now docker >/dev/null 2>&1
systemctl enable --now mariadb >/dev/null 2>&1

# --- 4. INSTALL PANEL (PORT 80) ---
echo -e "${CYAN}[JAVIX]${NC} Setting up Panel on Port 80..."

# Setup Database
mysql -u root -e "CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY 'javix123';"
mysql -u root -e "CREATE DATABASE IF NOT EXISTS panel;"
mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
mysql -u root -e "FLUSH PRIVILEGES;"

# Setup Files
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

# --- CONFIGURATION FOR CODESANDBOX ---
sed -i 's/DB_PASSWORD=/DB_PASSWORD=javix123/g' .env
sed -i "s|APP_URL=http://localhost|APP_URL=http://localhost|g" .env
sed -i "s|APP_URL=https://panel.example.com|APP_URL=http://localhost|g" .env

php artisan migrate --seed --force >/dev/null 2>&1
php artisan p:user:make --email=admin@javix.com --username=admin --name=Admin --password=javix123 --admin=1 >/dev/null 2>&1

# Serve the panel on Port 80
nohup php artisan serve --host=0.0.0.0 --port=80 > panel.log 2>&1 &

# --- 5. INSTALL WINGS ---
echo -e "${CYAN}[JAVIX]${NC} Installing Wings..."
mkdir -p /etc/pterodactyl
curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" >/dev/null 2>&1
chmod u+x /usr/local/bin/wings

# --- 6. THE CHEAT SHEET & WIZARD ---
logo
echo -e "${GREEN}PANEL INSTALLED!${NC}"
echo -e "Login: ${CYAN}admin@javix.com${NC} / ${CYAN}javix123${NC}"
echo ""
echo -e "${YELLOW}--- ACTION REQUIRED: CREATE YOUR NODE ---${NC}"
echo "1. Open the Panel (Check CodeSandbox 'PORTS' tab -> Port 80)."
echo "2. Go to Admin -> Locations -> Create New (Name it 'Home')."
echo "3. Go to Admin -> Nodes -> Create New."
echo ""
echo -e "${CYAN}--- COPY THESE EXACT VALUES INTO THE FORM ---${NC}"
echo -e "Name:                  ${GREEN}Javix-Node${NC}"
echo -e "Location:              ${GREEN}Home${NC}"
echo -e "FQDN:                  ${GREEN}localhost${NC}   <-- IMPORTANT!"
echo -e "Communicate Over SSL:  ${GREEN}Use HTTP Connection${NC} (Select the Right Option)"
echo -e "Behind Proxy:          ${GREEN}Not Behind Proxy${NC}"
echo -e "Total Memory:          ${GREEN}4096${NC}"
echo -e "Total Disk:            ${GREEN}10000${NC}"
echo -e "Daemon Port:           ${GREEN}8080${NC}"
echo -e "Daemon SFTP Port:      ${GREEN}2022${NC}"
echo -e "${CYAN}---------------------------------------------${NC}"
echo ""
echo "4. Click 'Create Node'."
echo "5. Click the 'Configuration' tab."
echo ""

# WIZARD INPUTS
echo -e "${YELLOW}--- NOW PASTE THE INFO HERE ---${NC}"

# 1. Ask for Panel URL
echo -e "${CYAN}1. Enter your Panel URL (Copy from browser address bar):${NC}"
read -r INPUT_URL

# 2. Ask for Token
echo -e "${CYAN}2. Enter the Token (The long text starting with 'ptla_'):${NC}"
read -r INPUT_TOKEN

# 3. Ask for UUID 
echo -e "${CYAN}3. Enter the Node UUID (e.g. 848d7s...):${NC}"
read -r INPUT_UUID

echo ""
echo -e "${YELLOW}Applying Configuration...${NC}"

# Manually run the configure command using the inputs
wings configure --panel-url "$INPUT_URL" --token "$INPUT_TOKEN" --node "$INPUT_UUID" --allow-cors-origins "*" 

# --- 7. START WINGS & SHOW FINAL SCREEN ---
echo -e "${YELLOW}Starting Wings...${NC}"
wings --debug > wings.log 2>&1 &

sleep 3
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
echo -e "   Status: ${GREEN}WINGS RUNNING ON LOCALHOST${NC}"
echo ""
echo -e "   ${YELLOW}Note: If the node shows a red heart in the panel,${NC}"
echo -e "   ${YELLOW}restart the CodeSandbox devbox once.${NC}"
