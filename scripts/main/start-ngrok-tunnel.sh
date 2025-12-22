#!/bin/bash

# ngrok tunnel starter
# Create public HTTPS access for the Hardhat RPC node

set -e

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_step() {
    echo -e "${GREEN}▶ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

clear
echo -e "${BLUE}================================================================${NC}"
echo -e "${BLUE}ngrok HTTPS tunnel - mobile MetaMask access${NC}"
echo -e "${BLUE}================================================================${NC}"
echo ""

# Check ngrok installation
if ! command -v ngrok &> /dev/null; then
    print_error "ngrok not installed"
    echo ""
    print_step "Installing ngrok..."

    cd /tmp
    wget -q https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-linux-amd64.tgz
    tar xzf ngrok-v3-stable-linux-amd64.tgz
    sudo mv ngrok /usr/local/bin/
    rm ngrok-v3-stable-linux-amd64.tgz

    print_success "ngrok installed"
    echo ""
fi

# Check authtoken
if [ ! -f ~/.config/ngrok/ngrok.yml ]; then
    print_info "First-time setup: configure ngrok authtoken"
    echo ""
    echo -e "${YELLOW}Visit https://dashboard.ngrok.com/get-started/your-authtoken${NC}"
    echo -e "${YELLOW}Sign up free and get your authtoken${NC}"
    echo ""
    read -p "Enter your ngrok authtoken: " NGROK_TOKEN

    if [ -n "$NGROK_TOKEN" ]; then
        ngrok config add-authtoken "$NGROK_TOKEN"
        print_success "authtoken configured"
    else
        print_error "No authtoken provided, exiting"
        exit 1
    fi
    echo ""
fi

# Check Hardhat node
print_step "Checking Hardhat node..."
if ! curl -s -X POST http://localhost:8545 \
    -H 'Content-Type: application/json' \
    -d '{"jsonrpc":"2.0","method":"eth_chainId","params":[],"id":1}' \
    | grep -q "0x7a69"; then
    print_error "Hardhat node is not running"
    echo "Start BRS system first: bash scripts/main/start-brs-system.sh"
    exit 1
fi
print_success "Hardhat node is running"
echo ""

# Start ngrok
print_step "Starting ngrok tunnel..."
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}ngrok started!${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${BLUE}📱 Configure in mobile MetaMask:${NC}"
echo ""
echo -e "  ${GREEN}1. Find the HTTPS URL in the 'Forwarding' line below${NC}"
echo -e "  ${GREEN}2. Copy the HTTPS address${NC}"
echo -e "  ${GREEN}3. Add a network in MetaMask:${NC}"
echo ""
echo -e "     ${BLUE}Network name:${NC} BRS ngrok"
echo -e "     ${BLUE}RPC URL:${NC} https://xxxx.ngrok.io (use forwarding URL)"
echo -e "     ${BLUE}Chain ID:${NC} 31337"
echo -e "     ${BLUE}Currency:${NC} ETH"
echo ""
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
print_info "Press Ctrl+C to stop the tunnel"
echo ""

# Start ngrok (forward 8545)
ngrok http 8545 --log stdout
