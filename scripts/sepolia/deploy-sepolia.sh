#!/bin/bash

# Bitres Sepolia Testnet Deployment Script
#
# This script deploys the complete Bitres system to Sepolia testnet:
# 1. Contract deployment via Ignition
# 2. System initialization (LP, pools, etc.)
#
# Prerequisites:
#   - .env file with SEPOLIA_RPC_URL and SEPOLIA_PRIVATE_KEY
#   - Sufficient Sepolia ETH in deployer account
#
# Usage: ./scripts/sepolia/deploy-sepolia.sh [--skip-init]

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Parse arguments
SKIP_INIT=false
for arg in "$@"; do
  case $arg in
    --skip-init)
      SKIP_INIT=true
      shift
      ;;
  esac
done

# Print header
print_header() {
  echo ""
  echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
  echo -e "${BLUE}  $1${NC}"
  echo -e "${BLUE}════════════════════════════════════════════════════════════════${NC}"
}

print_step() {
  echo -e "\n${CYAN}▶ $1${NC}"
}

# Main script
clear
echo -e "${GREEN}"
echo "  ____  _ _                    ____                  _ _       "
echo " | __ )(_) |_ _ __ ___  ___   / ___|  ___ _ __   ___ | (_) __ _ "
echo " |  _ \| | __| '__/ _ \/ __| | \___ \/ _ \ '_ \ / _ \| | |/ _\` |"
echo " | |_) | | |_| | |  __/\__ \  ___) |  __/ |_) | (_) | | | (_| |"
echo " |____/|_|\__|_|  \___||___/ |____/ \___| .__/ \___/|_|_|\__,_|"
echo "                                        |_|                    "
echo -e "${NC}"
echo -e "  Sepolia Testnet Deployment"
echo ""

cd "$PROJECT_DIR"

# Check .env
if [ ! -f ".env" ]; then
  echo -e "${RED}Error: .env file not found${NC}"
  echo "Please create .env with:"
  echo "  SEPOLIA_RPC_URL=https://..."
  echo "  SEPOLIA_PRIVATE_KEY=0x..."
  exit 1
fi

source .env

if [ -z "$SEPOLIA_RPC_URL" ] || [ -z "$SEPOLIA_PRIVATE_KEY" ]; then
  echo -e "${RED}Error: SEPOLIA_RPC_URL and SEPOLIA_PRIVATE_KEY must be set in .env${NC}"
  exit 1
fi

echo -e "  RPC URL: ${CYAN}${SEPOLIA_RPC_URL:0:40}...${NC}"
echo ""

# ============================================================================
# Step 1: Deploy Contracts
# ============================================================================
print_header "Step 1/2: Deploy Contracts (Ignition)"

print_step "Deploying contracts to Sepolia..."
echo -e "${YELLOW}This may take several minutes due to network confirmation times${NC}"

if npx hardhat ignition deploy ignition/modules/FullSystemSepolia.ts --network sepolia; then
  echo -e "\n${GREEN}✓ Contracts deployed successfully${NC}"
else
  echo -e "\n${RED}✗ Deployment failed${NC}"
  exit 1
fi

# ============================================================================
# Step 2: Initialize System
# ============================================================================
if [ "$SKIP_INIT" = false ]; then
  print_header "Step 2/2: Initialize System"

  print_step "Running init-sepolia.mjs..."
  if npx hardhat run scripts/sepolia/init-sepolia.mjs --network sepolia; then
    echo -e "\n${GREEN}✓ System initialized${NC}"
  else
    echo -e "\n${RED}✗ Initialization failed${NC}"
    exit 1
  fi
else
  print_header "Step 2/2: Initialize System (Skipped)"
  echo -e "${YELLOW}Skipped (--skip-init)${NC}"
fi

# ============================================================================
# Summary
# ============================================================================
print_header "Deployment Complete"

ADDR_FILE="$PROJECT_DIR/ignition/deployments/chain-11155111/deployed_addresses.json"

if [ -f "$ADDR_FILE" ]; then
  echo ""
  echo -e "  ${GREEN}Deployed addresses:${NC}"
  echo -e "  ${CYAN}$ADDR_FILE${NC}"
  echo ""
  echo -e "  Key contracts:"
  grep -E "(BTD|BTB|BRS|Minter|FarmingPool|PriceOracle)" "$ADDR_FILE" | head -10 | while read line; do
    echo -e "    ${CYAN}$line${NC}"
  done
fi

echo ""
echo -e "  ${GREEN}Next steps:${NC}"
echo -e "    1. Verify contracts on Etherscan:"
echo -e "       ${CYAN}npx hardhat verify --network sepolia <address> <constructor-args>${NC}"
echo -e "    2. Update frontend config with new addresses"
echo -e "    3. Fund test accounts with mock tokens"
echo ""
echo -e "  ${GREEN}View on Sepolia Etherscan:${NC}"
echo -e "    ${CYAN}https://sepolia.etherscan.io${NC}"
echo ""
