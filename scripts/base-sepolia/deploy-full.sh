#!/bin/bash
# Base Sepolia Full Deployment Script
#
# One-click deployment for Bitres system on Base Sepolia testnet.
# Runs: deploy contracts -> initialize system (including farming) -> distribute tokens
#
# After deployment:
#   - FarmingPool: Ready immediately
#   - Minter mint: Ready immediately
#   - Minter redeem: Ready after 30 minutes (needs TWAP prices)
#
# Prerequisites:
#   - BASE_SEPOLIA_RPC_URL and BASE_SEPOLIA_PRIVATE_KEY in .env
#   - Sufficient Base Sepolia ETH in deployer account (~0.5 ETH recommended)
#
# Usage:
#   ./scripts/base-sepolia/deploy-full.sh
#   npm run base-sepolia:deploy-full

set -e

echo "========================================"
echo "  Bitres Base Sepolia Full Deployment"
echo "========================================"
echo ""

# Check environment
if [ ! -f .env ]; then
    echo "Error: .env file not found"
    echo "Please create .env with BASE_SEPOLIA_RPC_URL and BASE_SEPOLIA_PRIVATE_KEY"
    exit 1
fi

source .env

if [ -z "$BASE_SEPOLIA_RPC_URL" ]; then
    echo "Error: BASE_SEPOLIA_RPC_URL not set in .env"
    exit 1
fi

if [ -z "$BASE_SEPOLIA_PRIVATE_KEY" ]; then
    echo "Error: BASE_SEPOLIA_PRIVATE_KEY not set in .env"
    exit 1
fi

echo "=> Step 1/6: Compile contracts..."
npx hardhat compile

echo ""
echo "=> Step 2/6: Deploy contracts via Ignition..."
npx hardhat ignition deploy ignition/modules/FullSystemBaseSepolia.ts --network baseSepolia

echo ""
echo "=> Step 3/6: Initialize system (LP + vaults + farming pools)..."
echo "   This is a one-step initialization - no secondary init needed."
npx hardhat run scripts/base-sepolia/init-base-sepolia.mjs --network baseSepolia

echo ""
echo "=> Step 4/6: Distribute test tokens (faucet)..."
npx hardhat run scripts/base-sepolia/faucet.mjs --network baseSepolia

echo ""
echo "=> Step 5/6: Sync addresses to interface..."
if [ -d "../interface" ]; then
    node scripts/main/update-interface-config.mjs --network baseSepolia
    echo ""
    echo "   To push to GitHub/Vercel: npm run update:interface -- --push"
else
    echo "   Interface project not found at ../interface. Skipping sync."
fi

echo ""
echo "=> Step 6/6: Run deployment health check..."
npx hardhat run scripts/base-sepolia/health-check.mjs --network baseSepolia

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
echo "Other commands:"
echo "  npm run base-sepolia:health-check    # Verify system health"
echo "  npm run base-sepolia:e2e             # Run Base Sepolia E2E tests"
echo "  npm run update:interface --push # Sync addresses to GitHub/Vercel"
echo ""
echo "View deployed addresses:"
echo "  cat ignition/deployments/chain-84532/deployed_addresses.json"
echo ""
