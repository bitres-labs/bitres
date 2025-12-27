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
#   - SEPOLIA_RPC_URL and PRIVATE_KEY in .env
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
    echo "Please create .env with SEPOLIA_RPC_URL and PRIVATE_KEY"
    exit 1
fi

source .env

if [ -z "$SEPOLIA_RPC_URL" ]; then
    echo "Error: SEPOLIA_RPC_URL not set in .env"
    exit 1
fi

if [ -z "$PRIVATE_KEY" ]; then
    echo "Error: PRIVATE_KEY not set in .env"
    exit 1
fi

echo "=> Step 1/5: Compile contracts..."
npx hardhat compile

echo ""
echo "=> Step 2/5: Deploy contracts via Ignition..."
npx hardhat ignition deploy ignition/modules/FullSystemSepolia.ts --network sepolia

echo ""
echo "=> Step 3/5: Initialize system (LP + vaults + farming pools)..."
echo "   This is a one-step initialization - no secondary init needed."
npx hardhat run scripts/sepolia/init-sepolia.mjs --network sepolia

echo ""
echo "=> Step 4/5: Distribute test tokens (faucet)..."
npx hardhat run scripts/sepolia/faucet.mjs --network sepolia

echo ""
echo "=> Step 5/5: Sync addresses to interface..."
if [ -d "../interface" ]; then
    node scripts/main/update-interface-config.mjs --network sepolia
    echo ""
    echo "   To push to GitHub/Vercel: npm run update:interface -- --push"
else
    echo "   Interface project not found at ../interface. Skipping sync."
fi

echo ""
echo "========================================"
echo "  Deployment Complete!"
echo "========================================"
echo ""
echo "System Status:"
echo "  ✓ FarmingPool: Ready to use immediately"
echo "  ✓ Minter mint: Ready to use immediately"
echo "  ⏳ Minter redeem: Will work after 30 minutes (TWAP warmup)"
echo ""
echo "Optional commands:"
echo "  npm run sepolia:price-sync      # Sync WBTC price with Chainlink"
echo "  npm run sepolia:health-check    # Verify system health"
echo "  npm run update:interface --push # Sync addresses to GitHub/Vercel"
echo ""
echo "View deployed addresses:"
echo "  cat ignition/deployments/chain-11155111/deployed_addresses.json"
echo ""
