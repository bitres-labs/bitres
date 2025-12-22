#!/bin/bash

# Export ABIs from brs to brs-interface

BRS_ROOT="/home/biostar/work/brs"
INTERFACE_ROOT="/home/biostar/work/brs-interface"

cd $BRS_ROOT

echo "📦 Exporting ABIs to interface..."
echo ""

# Core tokens
echo "Exporting BRS..."
cat "artifacts/contracts/BRS.sol/BRS.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/BRS.json" && echo "✅ BRS.json"

echo "Exporting BTB..."
cat "artifacts/contracts/BTB.sol/BTB.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/BTB.json" && echo "✅ BTB.json"

echo "Exporting stBTD..."
cat "artifacts/contracts/stBTD.sol/stBTD.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/stBTD.json" && echo "✅ stBTD.json"

echo "Exporting stBTB..."
cat "artifacts/contracts/stBTB.sol/stBTB.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/stBTB.json" && echo "✅ stBTB.json"

# Core contracts
echo "Exporting Minter..."
cat "artifacts/contracts/Minter.sol/Minter.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/Minter.json" && echo "✅ Minter.json"

echo "Exporting Treasury..."
cat "artifacts/contracts/Treasury.sol/Treasury.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/Treasury.json" && echo "✅ Treasury.json"

echo "Exporting Config..."
cat "artifacts/contracts/Config.sol/Config.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/Config.json" && echo "✅ Config.json"

echo "Exporting InterestPool..."
cat "artifacts/contracts/InterestPool.sol/InterestPool.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/InterestPool.json" && echo "✅ InterestPool.json"

echo "Exporting FarmingPool..."
cat "artifacts/contracts/FarmingPool.sol/FarmingPool.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/FarmingPool.json" && echo "✅ FarmingPool.json"

echo "Exporting StakingRouter..."
cat "artifacts/contracts/StakingRouter.sol/StakingRouter.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/StakingRouter.json" && echo "✅ StakingRouter.json"

echo "Exporting PriceOracle..."
cat "artifacts/contracts/PriceOracle.sol/PriceOracle.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/PriceOracle.json" && echo "✅ PriceOracle.json"

# Mock tokens
echo "Exporting MockUniswapV2Pair..."
cat "artifacts/contracts/local/MockUniswapV2Pair.sol/MockUniswapV2Pair.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/UniswapV2Pair.json" && echo "✅ UniswapV2Pair.json"

echo "Exporting MockWBTC..."
cat "artifacts/contracts/local/MockWBTC.sol/MockWBTC.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/WBTC.json" && echo "✅ WBTC.json"

echo "Exporting MockUSDC..."
cat "artifacts/contracts/local/MockUSDC.sol/MockUSDC.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/USDC.json" && echo "✅ USDC.json"

echo "Exporting MockUSDT..."
cat "artifacts/contracts/local/MockUSDT.sol/MockUSDT.json" | node -e "console.log(JSON.stringify(JSON.parse(require('fs').readFileSync(0, 'utf-8')).abi, null, 2))" > "$INTERFACE_ROOT/src/abis/USDT.json" && echo "✅ USDT.json"

# Create index.ts
cat > "$INTERFACE_ROOT/src/abis/index.ts" << 'EOF'
// Auto-generated ABI exports
// Generated at: $(date -Iseconds)

import BRS_ABI from './BRS.json'
import BTD_ABI from './BTD.json'
import BTB_ABI from './BTB.json'
import stBTD_ABI from './stBTD.json'
import stBTB_ABI from './stBTB.json'
import Minter_ABI from './Minter.json'
import Treasury_ABI from './Treasury.json'
import Config_ABI from './Config.json'
import InterestPool_ABI from './InterestPool.json'
import FarmingPool_ABI from './FarmingPool.json'
import StakingRouter_ABI from './StakingRouter.json'
import PriceOracle_ABI from './PriceOracle.json'
import UniswapV2Pair_ABI from './UniswapV2Pair.json'
import WBTC_ABI from './WBTC.json'
import USDC_ABI from './USDC.json'
import USDT_ABI from './USDT.json'

export {
  BRS_ABI,
  BTD_ABI,
  BTB_ABI,
  stBTD_ABI,
  stBTB_ABI,
  Minter_ABI,
  Treasury_ABI,
  Config_ABI,
  InterestPool_ABI,
  FarmingPool_ABI,
  StakingRouter_ABI,
  PriceOracle_ABI,
  UniswapV2Pair_ABI,
  WBTC_ABI,
  USDC_ABI,
  USDT_ABI,
}

// ERC20 standard ABI (use BTD for ERC20 operations)
export const ERC20_ABI = BTD_ABI
EOF

echo ""
echo "✅ Created index.ts"
echo ""
echo "📊 Export complete! All ABIs exported to brs-interface/src/abis/"
