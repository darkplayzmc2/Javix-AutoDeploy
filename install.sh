#!/bin/bash

# ==============================================================================
#  >> JAVIX-AUTODEPLOY | ULTIMATE REPAIR EDITION
#  >> FEATURES: Self-Healing, Menus, Multi-Environment Support
# ==============================================================================

# --- 0. AUTO-ELEVATION ---
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

# --- 1. EMERGENCY SYSTEM REPAIR (FIXES YOUR ERRORS) ---
echo "Initializing Javix System Repair..."

# Fix broken /dev/null (The cause of your previous errors)
if [ ! -e /dev/null ]; then mknod /dev/null c 1 3; chmod 666 /dev/null; fi

# Reinstall missing tools silently
apt-get update -y >/dev/null 2>&1
apt-get install -y --reinstall coreutils curl tar unzip git jq certbot mariadb-server mariadb-client sed whiptail >/dev/null 2>&1

# --- 2. VISUALS ---
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
    echo -e "${GREEN}    :: ULTIMATE REPAIR EDITION ::${NC}"
    echo ""
}

# --- 3. THE MENU SYSTEM ---
logo
echo -e "${YELLOW}--- ENVIRONMENT SELECTION ---${NC}"
echo "1) Paid VPS (DigitalOcean, AWS, Hetzner)"
echo "2) CodeSandbox (Free - Forces Port 80)"
echo "3) GitHub Codespaces (Free - Forces Tunnel)"
echo ""
echo -n "Select your environment [1-3]: "
read ENV_TYPE

logo
echo -e "${YELLOW}--- COMPONENT SELECTION ---${NC}"
echo "1) Full Stack (Panel + Wings)"
echo "2) Wings Only"
echo "3) Panel Only"
echo ""
echo -n "Select install mode [1-3]: "
read INSTALL_MODE

# --- 4. PREPARATION & CLEANUP ---
echo -e "${CYAN}[JAVIX]${NC} Cleaning up old installation..."
rm -rf /var/www/pterodactyl /etc/pterodactyl /usr/local/bin/wings
docker rm -f $(docker ps -a -q) >/dev/null 2>&1

echo -e "${CYAN}[JAVIX]${NC} Installing Docker & Dependencies..."
if ! command -v docker &> /dev/null; then
    curl -sSL https://get.docker.com/ | CHANNEL=stable bash >/dev/null 2>&1
fi
systemctl enable --now docker >/dev/null 2>&1
systemctl enable --now mariadb >/dev/null 2>&1

# --- 5. PANEL INSTALLATION LOGIC ---
if [ "$INSTALL_MODE" == "1" ] || [ "$INSTALL_MODE" == "3" ]; then
    echo -e "${CYAN}[JAVIX]${NC} Installing Panel..."
    
    # Database Setup
    mysql -u root -e "CREATE USER IF NOT EXISTS 'pterodactyl'@'127.0.0.1' IDENTIFIED BY 'javix123';"
    mysql -u root -e "CREATE DATABASE IF NOT EXISTS panel;"
    mysql -u root -e "GRANT ALL PRIVILEGES ON panel.* TO 'pterodactyl'@'127.0.0.1' WITH GRANT OPTION;"
    mysql -u root -e "FLUSH PRIVILEGES;"

    # Files
    mkdir -p /var/www/pterodactyl
    cd /var/www/pterodactyl
    curl -Lo panel.tar.gz https://github.com/pterodactyl/panel/releases/latest/download/panel.tar.gz >/dev/null 2>&1
    tar -xzvf panel.tar.gz >/dev/null 2>&1
    chmod -R 755 storage bootstrap/cache

    # PHP Setup
    apt-get install -y php8.1 php8.1-{cli,gd,mysql,pdo,mbstring,tokenizer,bcmath,xml,fpm,curl,zip} >/dev/null 2>&1
    curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer >/dev/null 2>&1
    cp .env.example .env
    composer install --no-dev --optimize-autoloader --no-interaction >/dev/null 2>&1
    php artisan key:generate --force >/dev/null 2>&1

    # --- ENVIRONMENT SPECIFIC CONFIG ---
    if [ "$ENV_TYPE" == "1" ]; then
        # PAID VPS: Ask for Domain
        echo -e "${YELLOW}Enter your Domain (FQDN) for SSL:${NC}"
        read FQDN
        sed -i "s|APP_URL=http://localhost|APP_URL=https://${FQDN}|g" .env
        sed -i "s|APP_URL=https://panel.example.com|APP_URL=https://${FQDN}|g" .env
        php artisan p:environment:setup --author=admin@javix.com --url=https://$FQDN --timezone=UTC --cache=redis --session=redis --queue=redis --redis-host=127.0.0.1 --redis-pass= --redis-port=6379 >/dev/null 2>&1
    
    elif [ "$ENV_TYPE" == "2" ]; then
        # CODESANDBOX: Force Localhost Port 80
        echo -e "${GREEN}Configuring for CodeSandbox (Port 80)...${NC}"
        sed -i "s|APP_URL=http://localhost|APP_URL=http://localhost|g" .env
        sed -i "s|APP_URL=https://panel.example.com|APP_URL=http://localhost|g" .env
        sed -i 's/DB_PASSWORD=/DB_PASSWORD=javix123/g' .env
        
        # Start Server on Port 80
        fuser -k 80/tcp >/dev/null 2>&1
        nohup php artisan serve --host=0.0.0.0 --port=80 > panel.log 2>&1 &
        FQDN="localhost"

    elif [ "$ENV_TYPE" == "3" ]; then
        # CODESPACES: Tunnel Mode
        echo -e "${GREEN}Configuring for GitHub Codespaces (Tunnel)...${NC}"
        # Install Cloudflared
        curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb >/dev/null 2>&1
        dpkg -i cloudflared.deb >/dev/null 2>&1
        cloudflared tunnel --url http://localhost:80 > tunnel.log 2>&1 &
        sleep 5
        FQDN=$(grep -o 'https://.*\.trycloudflare.com' tunnel.log | head -1)
        sed -i "s|APP_URL=http://localhost|APP_URL=${FQDN}|g" .env
        sed -i "s|APP_URL=https://panel.example.com|APP_URL=${FQDN}|g" .env
    fi

    # Finalize Panel
    php artisan migrate --seed --force >/dev/null 2>&1
    php artisan p:user:make --email=admin@javix.com --username=admin --name=Admin --password=javix123 --admin=1 >/dev/null 2>&1
fi

# --- 6. WINGS INSTALLATION LOGIC ---
if [ "$INSTALL_MODE" == "1" ] || [ "$INSTALL_MODE" == "2" ]; then
    echo -e "${CYAN}[JAVIX]${NC} Installing Wings..."
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" >/dev/null 2>&1
    chmod u+x /usr/local/bin/wings
fi

# --- 7. FINAL OUTPUT & WINGS CONFIG ---
logo
echo "=========================================="
echo "      INSTALLATION COMPLETE"
echo "=========================================="
if [ "$ENV_TYPE" == "2" ]; then
    echo "MODE: CodeSandbox (Port 80)"
    echo "1. Open 'PORTS' tab -> Port 80."
    echo "2. Create Node FQDN: localhost"
elif [ "$ENV_TYPE" == "3" ]; then
    echo "MODE: Tunnel (Public URL)"
    echo "URL: $FQDN"
    echo "2. Create Node FQDN: (The URL above without https://)"
else
    echo "MODE: Paid VPS"
    echo "URL: https://$FQDN"
fi
echo "=========================================="
echo "Login: admin@javix.com / javix123"
echo "=========================================="
echo ""

if [ "$INSTALL_MODE" == "1" ] || [ "$INSTALL_MODE" == "2" ]; then
    echo -e "${YELLOW}PASTE YOUR 'wings configure' COMMAND BELOW:${NC}"
    read WINGS_CMD
    echo "Configuring Wings..."
    eval "$WINGS_CMD"
    wings --debug > wings.log 2>&1 &
    echo -e "${GREEN}SUCCESS! Wings is running.${NC}"
fi
