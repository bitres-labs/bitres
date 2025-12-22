#!/bin/bash

# Nginx reverse proxy setup script
# Automatically install and configure Nginx as HTTPS proxy for Hardhat node

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

BRS_DIR="/home/biostar/work/brs"
CONFIG_DIR="$BRS_DIR/config"
SSL_DIR="$CONFIG_DIR/ssl"
NGINX_CONFIG="$CONFIG_DIR/nginx-hardhat-proxy.conf"

print_step() {
    echo -e "${GREEN}▶ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}Nginx HTTPS reverse proxy setup${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# Step 1: Check and install Nginx if needed
print_step "Checking Nginx installation..."
if ! command -v nginx &> /dev/null; then
    print_warning "Nginx not found, installing..."

    # Check for root or sudo
    if [ "$EUID" -ne 0 ]; then
        if ! sudo -n true 2>/dev/null; then
            print_error "sudo privileges required to install Nginx"
            echo "Run: sudo apt update && sudo apt install -y nginx"
            exit 1
        fi
    fi

    sudo apt update
    sudo apt install -y nginx

    print_success "Nginx installation complete"
else
    print_success "Nginx already installed"
    nginx -v
fi

echo ""

# Step 2: Generate SSL cert
print_step "Checking SSL certificate..."
if [ ! -f "$SSL_DIR/hardhat-rpc.crt" ] || [ ! -f "$SSL_DIR/hardhat-rpc.key" ]; then
    print_warning "SSL certificate not found, generating..."
    bash "$BRS_DIR/scripts/setup-ssl-cert.sh"
else
    print_success "SSL certificate already present"
    openssl x509 -in "$SSL_DIR/hardhat-rpc.crt" -noout -dates 2>/dev/null || true
fi

echo ""

# Step 3: Configure Nginx
print_step "Configuring Nginx reverse proxy..."

# Detect Nginx config directory
if [ -d "/etc/nginx/sites-available" ]; then
    # Debian/Ubuntu style
    NGINX_AVAILABLE="/etc/nginx/sites-available/hardhat-rpc"
    NGINX_ENABLED="/etc/nginx/sites-enabled/hardhat-rpc"
    NGINX_STYLE="debian"
elif [ -d "/etc/nginx/conf.d" ]; then
    # RedHat/CentOS style
    NGINX_AVAILABLE="/etc/nginx/conf.d/hardhat-rpc.conf"
    NGINX_STYLE="redhat"
else
    print_error "Unknown Nginx directory layout"
    exit 1
fi

# Copy config file
print_step "Installing Nginx config..."
sudo cp "$NGINX_CONFIG" "$NGINX_AVAILABLE"

# Create symlink (Debian/Ubuntu)
if [ "$NGINX_STYLE" == "debian" ]; then
    if [ ! -L "$NGINX_ENABLED" ]; then
        sudo ln -sf "$NGINX_AVAILABLE" "$NGINX_ENABLED"
    fi
fi

print_success "Config installed to: $NGINX_AVAILABLE"

echo ""

# Step 4: Test config
print_step "Testing Nginx config..."
if sudo nginx -t 2>/dev/null; then
    print_success "Config syntax OK"
else
    print_error "Config contains errors"
    sudo nginx -t
    exit 1
fi

echo ""

# Step 5: Restart Nginx
print_step "Restarting Nginx..."
if sudo systemctl restart nginx; then
    print_success "Nginx restarted"
else
    print_error "Nginx restart failed"
    sudo systemctl status nginx
    exit 1
fi

# Check Nginx status
if sudo systemctl is-active --quiet nginx; then
    print_success "Nginx is running"
else
    print_error "Nginx is not running"
    exit 1
fi

echo ""

# Step 6: Check port
print_step "Checking port 8546..."
sleep 2

if ss -tuln | grep -q ":8546"; then
    print_success "HTTPS proxy port 8546 is listening"
else
    print_warning "Port 8546 is not listening; please check config"
fi

echo ""
echo -e "${BLUE}================================================================${NC}"
echo -e "${GREEN}✨ Nginx HTTPS reverse proxy ready!${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

echo -e "${GREEN}📡 Service info:${NC}"
echo "  HTTP:  http://localhost:8545  (Hardhat direct)"
echo "  HTTPS: https://localhost:8546 (Nginx proxy)"
echo ""

LOCAL_IP=$(hostname -I | awk '{print $1}')
echo -e "${GREEN}🌐 External access:${NC}"
echo "  HTTPS: https://${LOCAL_IP}:8546"
echo ""

echo -e "${YELLOW}📋 Test commands:${NC}"
echo "  curl -k https://localhost:8546/health"
echo "  curl -k -X POST https://localhost:8546 -H 'Content-Type: application/json' -d '{\"jsonrpc\":\"2.0\",\"method\":\"eth_blockNumber\",\"params\":[],\"id\":1}'"
echo ""

echo -e "${YELLOW}🔧 Admin commands:${NC}"
echo "  Check Nginx status:  sudo systemctl status nginx"
echo "  Restart Nginx:       sudo systemctl restart nginx"
echo "  View logs:           tail -f /tmp/brs-logs/nginx-hardhat-*.log"
echo "  Access log:          tail -f /tmp/brs-logs/nginx-hardhat-access.log"
echo "  Error log:           tail -f /tmp/brs-logs/nginx-hardhat-error.log"
echo ""

print_warning "Self-signed certs trigger browser warnings; this is expected."
echo "  Trust the cert manually when accessing via browser."
echo ""

print_success "Setup complete!"
