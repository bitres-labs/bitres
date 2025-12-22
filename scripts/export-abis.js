const fs = require('fs');
const path = require('path');

// Contracts to export
const contracts = [
  // Core contracts
  { name: 'Minter', path: 'contracts/Minter.sol/Minter.json' },
  { name: 'InterestPool', path: 'contracts/InterestPool.sol/InterestPool.json' },
  { name: 'FarmingPool', path: 'contracts/FarmingPool.sol/FarmingPool.json' },
  { name: 'StakingRouter', path: 'contracts/StakingRouter.sol/StakingRouter.json' },
  { name: 'PriceOracle', path: 'contracts/PriceOracle.sol/PriceOracle.json' },
  { name: 'Config', path: 'contracts/Config.sol/Config.json' },
  { name: 'Treasury', path: 'contracts/Treasury.sol/Treasury.json' },

  // Token contracts
  { name: 'BTD', path: 'contracts/BTD.sol/BTD.json' },
  { name: 'BTB', path: 'contracts/BTB.sol/BTB.json' },
  { name: 'BRS', path: 'contracts/BRS.sol/BRS.json' },
  { name: 'stBTD', path: 'contracts/stBTD.sol/stBTD.json' },
  { name: 'stBTB', path: 'contracts/stBTB.sol/stBTB.json' },

  // Mock contracts
  { name: 'MockERC20', path: 'contracts/local/MockERC20.sol/MockERC20.json' },
  { name: 'MockUniswapV2Pair', path: 'contracts/local/MockUniswapV2Pair.sol/MockUniswapV2Pair.json' },
  { name: 'MockAggregatorV3', path: 'contracts/local/MockAggregatorV3.sol/MockAggregatorV3.json' },
];

const artifactsDir = path.join(__dirname, '../artifacts');
const outputDir = path.join(__dirname, '../../brs-interface/src/abis');

// Create output directory if it doesn't exist
if (!fs.existsSync(outputDir)) {
  fs.mkdirSync(outputDir, { recursive: true });
}

console.log('Exporting ABIs...\n');

contracts.forEach(({ name, path: contractPath }) => {
  const fullPath = path.join(artifactsDir, contractPath);

  if (!fs.existsSync(fullPath)) {
    console.log(`❌ ${name}: File not found at ${contractPath}`);
    return;
  }

  try {
    const artifact = JSON.parse(fs.readFileSync(fullPath, 'utf8'));
    const abi = artifact.abi;

    // Write ABI to output file
    const outputFile = path.join(outputDir, `${name}.json`);
    fs.writeFileSync(outputFile, JSON.stringify(abi, null, 2));

    console.log(`✅ ${name}: Exported (${abi.length} functions/events)`);
  } catch (error) {
    console.log(`❌ ${name}: Error - ${error.message}`);
  }
});

console.log(`\n✨ ABIs exported to: ${outputDir}`);
