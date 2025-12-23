#!/bin/bash

# BRS Local Development Environment Startup Script
#
# This script starts the complete BRS local development environment:
# 1. Hardhat node (with external access for WSL)
# 2. Contract deployment via Ignition
# 3. System initialization (prices, pools, test tokens)
# 4. Frontend config update
# 5. Guardian auto-mining
# 6. Frontend dev server
#
# Usage: ./start-local.sh [--no-frontend]
#
# For WSL: Access from Windows at http://<WSL_IP>:3000

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Directories
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONTRACTS_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
INTERFACE_DIR="$(cd "$CONTRACTS_DIR/../interface" && pwd)"
LOG_DIR="/tmp/brs-logs"

# Configuration
HARDHAT_HOST="0.0.0.0"
HARDHAT_PORT=8545
FRONTEND_PORT=3000
SKIP_FRONTEND=false

# Parse arguments
for arg in "$@"; do
  case $arg in
    --no-frontend)
      SKIP_FRONTEND=true
      shift
      ;;
  esac
done

# Get WSL IP for display
get_wsl_ip() {
  hostname -I | awk '{print $1}'
}

WSL_IP=$(get_wsl_ip)

mkdir -p "$LOG_DIR"

# Cleanup function
cleanup() {
  echo -e "\n${YELLOW}Stopping all services...${NC}"
  pkill -f "hardhat node" 2>/dev/null || true
  pkill -f "price-sync.mjs" 2>/dev/null || true
  pkill -f "guardian.mjs" 2>/dev/null || true
  pkill -f "vite" 2>/dev/null || true
  sleep 1
  echo -e "${GREEN}All services stopped.${NC}"
  exit 0
}
trap cleanup SIGINT SIGTERM

# Check if port is in use
port_in_use() {
  local port=$1
  nc -z 127.0.0.1 "$port" 2>/dev/null
}

# Wait for port to be available
wait_for_port() {
  local port=$1
  local max_wait=${2:-30}
  local count=0
  echo -n "   Waiting for port $port"
  while ! port_in_use "$port"; do
    sleep 1
    echo -n "."
    count=$((count + 1))
    if [ $count -ge $max_wait ]; then
      echo -e " ${RED}timeout${NC}"
      return 1
    fi
  done
  echo -e " ${GREEN}ready${NC}"
  return 0
}

# Kill existing processes on port
kill_port() {
  local port=$1
  if port_in_use "$port"; then
    echo -e "   ${YELLOW}Port $port in use, killing existing process...${NC}"
    fuser -k "$port/tcp" 2>/dev/null || true
    sleep 2
  fi
}

# Print section header
print_header() {
  echo ""
  echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

# Print step
print_step() {
  echo -e "\n${CYAN}▶ $1${NC}"
}

# Main script
clear
echo -e "${GREEN}"
echo "  ____  ____  ____    _                    _ "
echo " | __ )|  _ \/ ___|  | |    ___   ___ __ _| |"
echo " |  _ \| |_) \___ \  | |   / _ \ / __/ _\` | |"
echo " | |_) |  _ < ___) | | |__| (_) | (_| (_| | |"
echo " |____/|_| \_\____/  |_____\___/ \___\__,_|_|"
echo -e "${NC}"
echo -e "  Local Development Environment"
echo ""
echo -e "  Contracts: ${CYAN}$CONTRACTS_DIR${NC}"
echo -e "  Interface: ${CYAN}$INTERFACE_DIR${NC}"
echo -e "  Logs:      ${CYAN}$LOG_DIR${NC}"
echo -e "  WSL IP:    ${CYAN}$WSL_IP${NC}"
echo ""

# ============================================================================
# Step 1: Start Hardhat Node
# ============================================================================
print_header "Step 1/6: Start Hardhat Node"

kill_port $HARDHAT_PORT
pkill -f "hardhat node" 2>/dev/null || true
sleep 1

cd "$CONTRACTS_DIR"
print_step "Starting Hardhat node on ${HARDHAT_HOST}:${HARDHAT_PORT}..."

npx hardhat node --hostname "$HARDHAT_HOST" > "$LOG_DIR/hardhat-node.log" 2>&1 &
HARDHAT_PID=$!

if wait_for_port $HARDHAT_PORT 30; then
  echo -e "   ${GREEN}✓ Hardhat node started (PID: $HARDHAT_PID)${NC}"
  echo -e "   ${GREEN}✓ RPC: http://${WSL_IP}:${HARDHAT_PORT}${NC}"
else
  echo -e "   ${RED}✗ Failed to start Hardhat node${NC}"
  echo "   Last 20 lines of log:"
  tail -20 "$LOG_DIR/hardhat-node.log"
  exit 1
fi

# ============================================================================
# Step 2: Deploy Contracts
# ============================================================================
print_header "Step 2/6: Deploy Contracts (Ignition)"

print_step "Cleaning previous deployment..."
rm -rf "$CONTRACTS_DIR/ignition/deployments/chain-31337"

print_step "Deploying contracts..."
if npx hardhat ignition deploy ignition/modules/FullSystem.ts --network localhost > "$LOG_DIR/deploy.log" 2>&1; then
  echo -e "   ${GREEN}✓ Contracts deployed successfully${NC}"
  # Show deployed addresses
  echo "   Key addresses:"
  grep -E "(FarmingPool|PriceOracle|Treasury|BRS|BTD|BTB)" "$LOG_DIR/deploy.log" | tail -10 | while read line; do
    echo -e "   ${CYAN}$line${NC}"
  done
else
  echo -e "   ${RED}✗ Deployment failed${NC}"
  echo "   Last 30 lines of log:"
  tail -30 "$LOG_DIR/deploy.log"
  cleanup
fi

# ============================================================================
# Step 3: Initialize System
# ============================================================================
print_header "Step 3/6: Initialize System"

print_step "Running init-full-system.mjs..."
if npx hardhat run scripts/main/init-full-system.mjs --network localhost > "$LOG_DIR/init.log" 2>&1; then
  echo -e "   ${GREEN}✓ System initialized${NC}"
  # Show init summary
  grep -E "^(=>|✓|✅)" "$LOG_DIR/init.log" | while read line; do
    echo -e "   ${CYAN}$line${NC}"
  done
else
  echo -e "   ${RED}✗ Initialization failed${NC}"
  echo "   Last 30 lines of log:"
  tail -30 "$LOG_DIR/init.log"
  cleanup
fi

# ============================================================================
# Step 4: Start Price Sync Service
# ============================================================================
print_header "Step 4/7: Start Price Sync Service"

pkill -f "price-sync.mjs" 2>/dev/null || true
sleep 1

print_step "Starting price-sync.mjs (syncs DEX prices to oracles)..."
node scripts/main/price-sync.mjs > "$LOG_DIR/price-sync.log" 2>&1 &
PRICESYNC_PID=$!
sleep 3

if ps -p $PRICESYNC_PID > /dev/null 2>&1; then
  echo -e "   ${GREEN}✓ Price Sync started (PID: $PRICESYNC_PID)${NC}"
  echo -e "   ${GREEN}✓ Oracle prices will stay synced with DEX${NC}"
else
  echo -e "   ${YELLOW}⚠ Price Sync may not be running, check log${NC}"
  tail -10 "$LOG_DIR/price-sync.log"
fi

# ============================================================================
# Step 5: Update Frontend Config
# ============================================================================
print_header "Step 5/7: Update Frontend Config"

print_step "Updating interface/src/config/contracts.ts..."
if node scripts/main/update-interface-config.mjs > "$LOG_DIR/update-config.log" 2>&1; then
  echo -e "   ${GREEN}✓ Frontend config updated${NC}"
else
  echo -e "   ${RED}✗ Config update failed${NC}"
  tail -10 "$LOG_DIR/update-config.log"
  cleanup
fi

# ============================================================================
# Step 6: Start Guardian (Auto-mining)
# ============================================================================
print_header "Step 6/7: Start Guardian (Auto-mining)"

pkill -f "guardian.mjs" 2>/dev/null || true
sleep 1

print_step "Starting guardian.mjs (real-time mode)..."
node scripts/main/guardian.mjs --realtime > "$LOG_DIR/guardian.log" 2>&1 &
GUARDIAN_PID=$!
sleep 3

if ps -p $GUARDIAN_PID > /dev/null 2>&1; then
  echo -e "   ${GREEN}✓ Guardian started (PID: $GUARDIAN_PID)${NC}"
  echo -e "   ${GREEN}✓ Auto-mining enabled with real-time sync${NC}"
else
  echo -e "   ${YELLOW}⚠ Guardian may not be running, check log${NC}"
  tail -10 "$LOG_DIR/guardian.log"
fi

# ============================================================================
# Step 7: Start Frontend (Optional)
# ============================================================================
if [ "$SKIP_FRONTEND" = false ]; then
  print_header "Step 7/7: Start Frontend"

  if [ ! -d "$INTERFACE_DIR" ]; then
    echo -e "   ${YELLOW}⚠ Interface directory not found: $INTERFACE_DIR${NC}"
    echo -e "   ${YELLOW}  Skipping frontend startup${NC}"
  else
    kill_port $FRONTEND_PORT
    pkill -f "vite" 2>/dev/null || true
    sleep 1

    cd "$INTERFACE_DIR"
    print_step "Starting Vite dev server on port ${FRONTEND_PORT}..."

    npm run dev -- --host 0.0.0.0 --port $FRONTEND_PORT > "$LOG_DIR/frontend.log" 2>&1 &
    FRONTEND_PID=$!

    if wait_for_port $FRONTEND_PORT 30; then
      echo -e "   ${GREEN}✓ Frontend started (PID: $FRONTEND_PID)${NC}"
      echo -e "   ${GREEN}✓ URL: http://${WSL_IP}:${FRONTEND_PORT}${NC}"
    else
      echo -e "   ${YELLOW}⚠ Frontend may not be ready, check log${NC}"
      tail -10 "$LOG_DIR/frontend.log"
    fi
  fi
else
  print_header "Step 7/7: Frontend (Skipped)"
  echo -e "   ${YELLOW}Frontend startup skipped (--no-frontend)${NC}"
fi

# ============================================================================
# Summary
# ============================================================================
print_header "Environment Ready"

echo ""
echo -e "  ${GREEN}Services:${NC}"
echo -e "    Hardhat Node:  PID ${HARDHAT_PID:-N/A}  →  http://${WSL_IP}:${HARDHAT_PORT}"
echo -e "    Price Sync:    PID ${PRICESYNC_PID:-N/A}  →  DEX-Oracle sync"
echo -e "    Guardian:      PID ${GUARDIAN_PID:-N/A}  →  60x time acceleration"
if [ "$SKIP_FRONTEND" = false ] && [ -n "$FRONTEND_PID" ]; then
  echo -e "    Frontend:      PID ${FRONTEND_PID:-N/A}  →  http://${WSL_IP}:${FRONTEND_PORT}"
fi
echo ""
echo -e "  ${GREEN}Logs:${NC}"
echo -e "    Hardhat:    $LOG_DIR/hardhat-node.log"
echo -e "    Deploy:     $LOG_DIR/deploy.log"
echo -e "    Init:       $LOG_DIR/init.log"
echo -e "    Price Sync: $LOG_DIR/price-sync.log"
echo -e "    Guardian:   $LOG_DIR/guardian.log"
if [ "$SKIP_FRONTEND" = false ]; then
  echo -e "    Frontend:   $LOG_DIR/frontend.log"
fi
echo ""
echo -e "  ${GREEN}Access from Windows:${NC}"
echo -e "    Frontend:  ${CYAN}http://${WSL_IP}:${FRONTEND_PORT}${NC}"
echo -e "    Explorer:  ${CYAN}http://${WSL_IP}:${FRONTEND_PORT}/explorer${NC}"
echo -e "    Farm:      ${CYAN}http://${WSL_IP}:${FRONTEND_PORT}/farm${NC}"
echo ""
echo -e "  ${YELLOW}Press Ctrl+C to stop all services${NC}"
echo ""

# Keep script running
while true; do
  sleep 10
  # Check if critical processes are still running
  if ! ps -p $HARDHAT_PID > /dev/null 2>&1; then
    echo -e "${RED}Hardhat node stopped unexpectedly!${NC}"
    cleanup
  fi
done
