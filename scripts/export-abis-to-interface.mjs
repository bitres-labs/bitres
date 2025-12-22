import fs from 'fs';
import path from 'path';
import { fileURLToPath } from 'url';

// Source: brs/artifacts/contracts
// Target: brs-interface/src/abis

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const BRS_ROOT = path.resolve(__dirname, '..');
const INTERFACE_ROOT = path.resolve(BRS_ROOT, '../brs-interface');

const CONTRACTS = [
  { name: 'BRS', path: 'BRS.sol/Bitreserve.json' },
  { name: 'BTD', path: 'BTD.sol/Bitdollar.json' },
  { name: 'BTB', path: 'BTB.sol/Bitbond.json' },
  { name: 'stBTD', path: 'stBTD.sol/stBTD.json' },
  { name: 'stBTB', path: 'stBTB.sol/stBTB.json' },
  { name: 'Minter', path: 'Minter.sol/Minter.json' },
  { name: 'Treasury', path: 'Treasury.sol/Treasury.json' },
  { name: 'Config', path: 'Config.sol/Config.json' },
  { name: 'InterestPool', path: 'InterestPool.sol/InterestPool.json' },
  { name: 'FarmingPool', path: 'FarmingPool.sol/FarmingPool.json' },
  { name: 'StakingRouter', path: 'StakingRouter.sol/StakingRouter.json' },
  { name: 'PriceOracle', path: 'PriceOracle.sol/PriceOracle.json' },
  { name: 'WBTC', path: 'local/MockWBTC.sol/MockWBTC.json' },
  { name: 'USDC', path: 'local/MockUSDC.sol/MockUSDC.json' },
  { name: 'USDT', path: 'local/MockUSDT.sol/MockUSDT.json' },
  { name: 'WETH', path: 'local/MockWETH.sol/MockWETH.json' },
  { name: 'UniswapV2Pair', path: 'interfaces/IUniswapV2Pair.sol/IUniswapV2Pair.json' },
];

const artifactsDir = path.join(BRS_ROOT, 'artifacts/contracts');
const targetDir = path.join(INTERFACE_ROOT, 'src/abis');

console.log('📦 Exporting ABIs to interface...\n');
console.log(`Source: ${artifactsDir}`);
console.log(`Target: ${targetDir}\n`);

// Create target directory if it doesn't exist
if (!fs.existsSync(targetDir)) {
  fs.mkdirSync(targetDir, { recursive: true });
  console.log(`✅ Created directory: ${targetDir}\n`);
}

// Export each contract ABI
const exportedContracts = [];

for (const contract of CONTRACTS) {
  const sourcePath = path.join(artifactsDir, contract.path);
  const targetPath = path.join(targetDir, `${contract.name}.json`);

  try {
    // Read the full artifact
    const artifact = JSON.parse(fs.readFileSync(sourcePath, 'utf8'));

    // Extract only the ABI
    const abi = artifact.abi;

    // Write ABI to target
    fs.writeFileSync(targetPath, JSON.stringify(abi, null, 2));

    console.log(`✅ ${contract.name.padEnd(20)} → ${contract.name}.json`);

    exportedContracts.push(contract.name);
  } catch (error) {
    console.log(`❌ ${contract.name.padEnd(20)} → Error: ${error.message}`);
  }
}

// Create index.ts with exports
const indexContent = `// Auto-generated ABI exports
// Generated at: ${new Date().toISOString()}

${exportedContracts
  .map(name => `import ${name}_ABI from './${name}.json'`)
  .join('\n')}

export {
${exportedContracts.map(name => `  ${name}_ABI,`).join('\n')}
}

// ERC20 standard ABI (use BTD, BTB, BRS, or mock tokens)
export const ERC20_ABI = BTD_ABI
`;

const indexPath = path.join(targetDir, 'index.ts');
fs.writeFileSync(indexPath, indexContent);

console.log(`\n✅ Created index.ts with ${exportedContracts.length} exports\n`);
console.log('📊 Summary:');
console.log(`   Total contracts: ${CONTRACTS.length}`);
console.log(`   Exported: ${exportedContracts.length}`);
console.log(`   Failed: ${CONTRACTS.length - exportedContracts.length}`);
console.log(`\n✅ ABI export complete!`);
