#!/bin/bash
# BRS local dev one-click restart
# Stop services -> start Hardhat -> deploy -> sync frontend -> start frontend

set -e

echo "🔄 Restarting BRS local dev environment..."
echo ""

# 1. Stop existing services
echo "📛 Stopping existing services..."
pkill -f "hardhat node" || true
pkill -f "vite" || true
sleep 2
echo "✅ Services stopped"
echo ""

# 2. Start Hardhat node
echo "🚀 Starting Hardhat node..."
cd /home/biostar/work/brs
npx hardhat node --hostname 0.0.0.0 > /tmp/hardhat-node.log 2>&1 &
sleep 5

if lsof -i :8545 > /dev/null 2>&1; then
    echo "✅ Hardhat node started (port 8545)"
else
    echo "❌ Hardhat node failed to start"
    exit 1
fi
echo ""

# 3. Deploy BRS system (auto-sync frontend config)
echo "📦 Deploying BRS system..."
npx hardhat run scripts/main/deploy-full-system-local.js --network localhost
echo ""

# 4. Start frontend dev server
echo "🌐 Starting frontend dev server..."
cd /home/biostar/work/brs-interface
npm run dev > /tmp/vite-dev.log 2>&1 &
sleep 5

if lsof -i :3000 > /dev/null 2>&1; then
    echo "✅ Frontend server started (port 3000)"
else
    echo "❌ Frontend server failed to start"
    exit 1
fi
echo ""

# 5. Show status
echo "════════════════════════════════════════════════════════════"
echo "✨ BRS local dev environment is ready!"
echo "════════════════════════════════════════════════════════════"
echo ""
echo "📊 Services:"
echo "   🔹 Hardhat:  http://localhost:8545"
echo "   🔹 Frontend: http://localhost:3000"
echo "   🔹 LAN:      http://192.168.2.151:3000"
echo ""
echo "📝 Logs:"
echo "   Hardhat:  /tmp/hardhat-node.log"
echo "   Frontend: /tmp/vite-dev.log"
echo ""
echo "🔧 Useful commands:"
echo "   Tail logs:        tail -f /tmp/hardhat-node.log"
echo "   Sync addresses:   node scripts/sync-contracts-to-interface.js"
echo "   Stop all:         pkill -f 'hardhat node'; pkill -f 'vite'"
echo ""
echo "════════════════════════════════════════════════════════════"
