/**
 * Update Interface Config for Sepolia
 *
 * Generates contracts-sepolia.ts in the interface/src/config directory
 * based on deployed addresses from Ignition.
 *
 * Usage:
 *   npx hardhat run scripts/sepolia/update-interface-config.mjs --network sepolia
 */

import fs from "fs";
import path from "path";

const CHAIN_ID = 11155111;
const ADDR_FILE = path.join(
  process.cwd(),
  `ignition/deployments/chain-${CHAIN_ID}/deployed_addresses.json`
);
const INTERFACE_DIR = path.join(process.cwd(), "..", "interface");
const OUTPUT_FILE = path.join(INTERFACE_DIR, "src", "config", "contracts-sepolia.ts");

function loadAddresses() {
  if (!fs.existsSync(ADDR_FILE)) {
    throw new Error(`deployed_addresses.json not found at ${ADDR_FILE}`);
  }
  const raw = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  const map = {};
  for (const [k, v] of Object.entries(raw)) {
    const key = k.replace("FullSystemSepolia#", "");
    map[key] = v;
  }
  return map;
}

async function main() {
  console.log("=".repeat(60));
  console.log("  Update Interface Config for Sepolia");
  console.log("=".repeat(60));

  const addresses = loadAddresses();
  console.log(`\n=> Loaded ${Object.keys(addresses).length} addresses from Ignition deployment`);

  // Check if interface directory exists
  if (!fs.existsSync(INTERFACE_DIR)) {
    console.error(`\n❌ Interface directory not found: ${INTERFACE_DIR}`);
    process.exit(1);
  }

  const timestamp = new Date().toISOString().split("T")[0];

  const content = `// Bitres Contract Addresses - Sepolia Testnet (Chain ID: ${CHAIN_ID})
// Auto-generated from Ignition deployment: FullSystemSepolia
// Last updated: ${timestamp}

export const CONTRACTS_SEPOLIA = {
  // Mock Tokens (testnet faucet tokens)
  WBTC: '${addresses.WBTC}' as \`0x\${string}\`,
  USDC: '${addresses.USDC}' as \`0x\${string}\`,
  USDT: '${addresses.USDT}' as \`0x\${string}\`,
  WETH: '${addresses.WETH}' as \`0x\${string}\`,

  // Core Tokens
  BRS: '${addresses.BRS}' as \`0x\${string}\`,
  BTD: '${addresses.BTD}' as \`0x\${string}\`,
  BTB: '${addresses.BTB}' as \`0x\${string}\`,

  // Staking Tokens (ERC4626)
  stBTD: '${addresses.stBTD}' as \`0x\${string}\`,
  stBTB: '${addresses.stBTB}' as \`0x\${string}\`,

  // Oracles
  ChainlinkBTCUSD: '${addresses.ChainlinkBTCUSD}' as \`0x\${string}\`,  // Real Chainlink feed
  ChainlinkWBTCBTC: '${addresses.ChainlinkWBTCBTC}' as \`0x\${string}\`, // Mock (1:1)
  MockPyth: '${addresses.MockPyth}' as \`0x\${string}\`,
  MockRedstone: '${addresses.MockRedstone}' as \`0x\${string}\`,
  IdealUSDManager: '${addresses.IdealUSDManager}' as \`0x\${string}\`,
  PriceOracle: '${addresses.PriceOracle}' as \`0x\${string}\`,
  TWAPOracle: '${addresses.TWAPOracle}' as \`0x\${string}\`,

  // Uniswap V2 Pairs (our own deployment)
  BTBBTDPair: '${addresses.PairBTBBTD}' as \`0x\${string}\`,
  BRSBTDPair: '${addresses.PairBRSBTD}' as \`0x\${string}\`,
  BTDUSDCPair: '${addresses.PairBTDUSDC}' as \`0x\${string}\`,
  WBTCUSDCPair: '${addresses.PairWBTCUSDC}' as \`0x\${string}\`,

  // Core Contracts
  ConfigCore: '${addresses.ConfigCore}' as \`0x\${string}\`,
  ConfigGov: '${addresses.ConfigGov}' as \`0x\${string}\`,
  Config: '${addresses.ConfigCore}' as \`0x\${string}\`,  // alias
  Treasury: '${addresses.Treasury}' as \`0x\${string}\`,
  Minter: '${addresses.Minter}' as \`0x\${string}\`,
  InterestPool: '${addresses.InterestPool}' as \`0x\${string}\`,
  FarmingPool: '${addresses.FarmingPool}' as \`0x\${string}\`,
  StakingRouter: '${addresses.StakingRouter}' as \`0x\${string}\`,
}

export const NETWORK_CONFIG_SEPOLIA = {
  chainId: ${CHAIN_ID},
  chainName: 'Sepolia Testnet',
  rpcUrl: 'https://rpc.sepolia.org',
  blockExplorer: 'https://sepolia.etherscan.io',
}

export default CONTRACTS_SEPOLIA
`;

  // Ensure config directory exists
  const configDir = path.dirname(OUTPUT_FILE);
  if (!fs.existsSync(configDir)) {
    fs.mkdirSync(configDir, { recursive: true });
  }

  fs.writeFileSync(OUTPUT_FILE, content, "utf8");
  console.log(`\n=> Generated: ${OUTPUT_FILE}`);

  console.log("\n" + "=".repeat(60));
  console.log("  ✅ Interface config updated for Sepolia!");
  console.log("=".repeat(60));
  console.log("\nTo use in frontend, update src/config/contracts.ts to import from contracts-sepolia.ts");
  console.log("based on the current network/chain ID.");
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
