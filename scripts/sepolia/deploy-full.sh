#!/bin/bash
# Sepolia Full Deployment Script
#
# One-click deployment for Bitres system on Sepolia testnet.
# Runs: deploy contracts -> initialize system (including farming) -> distribute tokens
#
# After deployment:
#   - FarmingPool: Ready immediately
#   - Minter mint: Ready immediately
#   - Minter redeem: Ready after 30 minutes (needs TWAP prices)
#
# Prerequisites:
#   - SEPOLIA_RPC_URL and SEPOLIA_PRIVATE_KEY in .env
#   - Sufficient Sepolia ETH in deployer account (~0.5 ETH recommended)
#
# Usage:
#   ./scripts/sepolia/deploy-full.sh
#   npm run sepolia:deploy-full

set -e

echo "========================================"
echo "  Bitres Sepolia Full Deployment"
echo "========================================"
echo ""

# Check environment
if [ ! -f .env ]; then
    echo "Error: .env file not found"
    echo "Please create .env with SEPOLIA_RPC_URL and SEPOLIA_PRIVATE_KEY"
    exit 1
fi

source .env

if [ -z "$SEPOLIA_RPC_URL" ]; then
    echo "Error: SEPOLIA_RPC_URL not set in .env"
    exit 1
fi

if [ -z "$SEPOLIA_PRIVATE_KEY" ]; then
    echo "Error: SEPOLIA_PRIVATE_KEY not set in .env"
    exit 1
fi

echo "=> Step 1/6: Compile contracts..."
npx hardhat compile

echo ""
echo "=> Step 2/6: Deploy contracts via Ignition..."
npx hardhat ignition deploy ignition/modules/FullSystemSepolia.ts --network sepolia

echo ""
echo "=> Step 3/6: Initialize system (LP + vaults + farming pools)..."
echo "   This is a one-step initialization - no secondary init needed."
npx hardhat run scripts/sepolia/init-sepolia.mjs --network sepolia

echo ""
echo "=> Step 4/6: Distribute test tokens (faucet)..."
npx hardhat run scripts/sepolia/faucet.mjs --network sepolia

echo ""
echo "=> Step 5/6: Sync addresses to interface..."
if [ -d "../interface" ]; then
    node scripts/main/update-interface-config.mjs --network sepolia
    echo ""
    echo "   To push to GitHub/Vercel: npm run update:interface -- --push"
else
    echo "   Interface project not found at ../interface. Skipping sync."
fi

echo ""
echo "=> Step 6/6: Starting price sync daemon..."
LOG_FILE="/tmp/price-sync-daemon.log"
PID_FILE="/tmp/price-sync-daemon.pid"

# Kill existing daemon if running
if [ -f "$PID_FILE" ]; then
    OLD_PID=$(cat "$PID_FILE")
    if kill -0 "$OLD_PID" 2>/dev/null; then
        echo "   Stopping existing daemon (PID: $OLD_PID)..."
        kill "$OLD_PID" 2>/dev/null || true
        sleep 2
    fi
    rm -f "$PID_FILE"
fi

# Start daemon in background
nohup npx hardhat run scripts/sepolia/price-sync.mjs --network sepolia > "$LOG_FILE" 2>&1 &
DAEMON_PID=$!
echo "$DAEMON_PID" > "$PID_FILE"
echo "   ✓ Price sync daemon started (PID: $DAEMON_PID)"
echo "   Log file: $LOG_FILE"

echo ""
echo "========================================"
echo "  Deployment Complete!"
echo "========================================"
echo ""
echo "System Status:"
echo "  ✓ FarmingPool: Ready to use immediately"
echo "  ✓ Minter mint: Ready to use immediately"
echo "  ✓ Price sync daemon: Running (PID: $DAEMON_PID)"
echo "  ⏳ Minter redeem: Will work after 30 minutes (TWAP warmup)"
echo ""
echo "Daemon commands:"
echo "  tail -f $LOG_FILE              # View daemon logs"
echo "  kill \$(cat $PID_FILE)          # Stop daemon"
echo ""
echo "Other commands:"
echo "  npm run sepolia:health-check    # Verify system health"
echo "  npm run update:interface --push # Sync addresses to GitHub/Vercel"
echo ""
echo "View deployed addresses:"
echo "  cat ignition/deployments/chain-11155111/deployed_addresses.json"
echo ""
