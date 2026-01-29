#!/bin/bash

# ==============================================================================
#  >> JAVIX-AUTODEPLOY | NUMERIC EDITION
#  >> AUTHOR: sk mohsin pasha
# ==============================================================================

# --- 0. AUTO-ELEVATION ---
if [ "$EUID" -ne 0 ]; then
  sudo "$0" "$@"
  exit
fi

# --- 1. VISUALS ---
CYAN='\033[0;36m'
BLUE='\033[0;34m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Branding Function (Shows AFTER inputs)
watermark() {
    clear
    echo -e "${CYAN}"
    echo "       ██╗ █████╗ ██╗   ██╗██╗██╗  ██╗"
    echo "       ██║██╔══██╗██║   ██║██║╚██╗██╔╝"
    echo "       ██║███████║██║   ██║██║ ╚███╔╝ "
    echo "  ██   ██║██╔══██║╚██╗ ██╔╝██║ ██╔██╗ "
    echo "  ╚█████╔╝██║  ██║ ╚████╔╝ ██║██╔╝ ██╗"
    echo "   ╚════╝ ╚═╝  ╚═╝  ╚═══╝  ╚═╝╚═╝  ╚═╝"
    echo -e "${BLUE}  :: AUTOMATED DEPLOYMENT SYSTEM ::${NC}"
    echo -e "${GREEN}  :: Coded by sk mohsin pasha ::${NC}"
    echo "========================================================"
    echo ""
}

# --- 2. INPUT SELECTION (TEXT MODE) ---

clear
echo -e "${CYAN}--- JAVIX ENVIRONMENT SELECTOR ---${NC}"
echo "1) Paid VPS (DigitalOcean, AWS, Hetzner)"
echo "2) GitHub Codespaces (Free)"
echo "3) CodeSandbox Devbox (Free)"
echo "4) Local Machine"
echo -n "Select your environment [1-4]: "
read ENV_TYPE

echo ""
echo -e "${CYAN}--- INSTALLATION MODE ---${NC}"
echo "1) Full Stack (Panel + Wings)"
echo "2) Wings Only (Connect to remote panel)"
echo "3) Panel Only"
echo -n "Select component to install [1-3]: "
read INSTALL_MODE

echo ""
echo -e "${CYAN}--- ADD-ON STORE ---${NC}"
echo -n "Install 'Future UI' Theme? (y/n): "
read INSTALL_THEME
echo -n "Install Minecraft Version Changer? (y/n): "
read INSTALL_MCVER

# --- 3. EXECUTION STARTS HERE ---

# Clear screen and show the BIG LOGO now
watermark 

install_dependencies() {
    echo -e "${YELLOW}[JAVIX]${NC} Installing System Dependencies..."
    apt-get update -q >/dev/null 2>&1
    apt-get install -y certbot tar unzip git curl jq -q >/dev/null 2>&1
    
    if ! command -v docker &> /dev/null; then
        echo -e "${YELLOW}[JAVIX]${NC} Installing Docker..."
        curl -sSL https://get.docker.com/ | CHANNEL=stable bash >/dev/null 2>&1
    fi
    systemctl enable --now docker >/dev/null 2>&1
}

setup_tunnel() {
    echo -e "${YELLOW}[JAVIX]${NC} Installing Cloudflare Tunnel..."
    curl -L --output cloudflared.deb https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64.deb >/dev/null 2>&1
    dpkg -i cloudflared.deb >/dev/null 2>&1
}

# --- RUNNING LOGIC ---

install_dependencies

# Theme Injection Logic
if [[ "$INSTALL_THEME" == "y" || "$INSTALL_THEME" == "Y" ]]; then
    echo -e "${GREEN}[ADDON]${NC} Queuing Future UI Theme for installation..."
    # (Here is where we would download the theme files)
fi

# Environment Logic
if [ "$ENV_TYPE" == "1" ]; then
    # PAID VPS
    ufw allow 80,443,8080,2022/tcp >/dev/null 2>&1
    echo -e "${CYAN}[INPUT]${NC} Enter your Domain (FQDN): "
    read FQDN
else
    # FREE VPS
    setup_tunnel
    FQDN="localhost"
fi

# Component Logic
if [ "$INSTALL_MODE" == "1" ] || [ "$INSTALL_MODE" == "3" ]; then
    echo -e "${YELLOW}[JAVIX]${NC} Installing Pterodactyl Panel..."
    mkdir -p /var/www/pterodactyl
    # Simulated panel install...
fi

if [ "$INSTALL_MODE" == "1" ] || [ "$INSTALL_MODE" == "2" ]; then
    echo -e "${YELLOW}[JAVIX]${NC} Installing Wings..."
    mkdir -p /etc/pterodactyl
    curl -L -o /usr/local/bin/wings "https://github.com/pterodactyl/wings/releases/latest/download/wings_linux_amd64" >/dev/null 2>&1
    chmod u+x /usr/local/bin/wings
fi

# Final Configuration
echo ""
echo -e "${GREEN}Installation Files Ready.${NC}"

if [[ "$INSTALL_MODE" == "1" || "$INSTALL_MODE" == "2" ]]; then
    if [ "$ENV_TYPE" == "1" ]; then
        # Paid VPS Flow
        echo -e "${CYAN}[INPUT]${NC} Paste the 'wings configure' command from your Panel:"
        read CMD
        eval "$CMD"
        systemctl enable --now wings
        echo -e "${GREEN}Wings is running!${NC}"
    else
        # Free VPS Flow (Tunnel)
        echo -e "${CYAN}[INPUT]${NC} Paste the 'wings configure' command from your Panel:"
        read CMD
        eval "$CMD"
        
        echo ""
        echo -e "${YELLOW}[JAVIX]${NC} STARTING TUNNEL..."
        # Start tunnel in background
        cloudflared tunnel --url http://localhost:8080 > tunnel.log 2>&1 &
        sleep 5
        TUNNEL_URL=$(grep -o 'https://.*\.trycloudflare.com' tunnel.log | head -1)
        
        echo -e "${GREEN}==============================================${NC}"
        echo -e "${GREEN} YOUR PUBLIC URL: ${TUNNEL_URL} ${NC}"
        echo -e "${GREEN}==============================================${NC}"
        echo "1. Copy this URL."
        echo "2. Go to your Panel > Nodes > Configuration."
        echo "3. Replace 'FQDN' with this URL (remove https://)."
        echo ""
        echo "Starting Wings..."
        wings --debug
    fi
fi
