/**
 * Update Interface Config
 *
 * Syncs deployed contract addresses from bitres to interface project.
 * Supports both local (chain-31337) and Sepolia (chain-11155111) deployments.
 *
 * Usage:
 *   node scripts/main/update-interface-config.mjs [options]
 *
 * Options:
 *   --network <network>   Network to sync (local, sepolia, or auto). Default: auto
 *   --push                Push changes to GitHub after update
 *   --dry-run             Show what would be changed without modifying files
 *
 * Examples:
 *   node scripts/main/update-interface-config.mjs                    # Auto-detect network
 *   node scripts/main/update-interface-config.mjs --network sepolia  # Sync Sepolia only
 *   node scripts/main/update-interface-config.mjs --push             # Sync and push to GitHub
 */

import fs from "fs";
import path from "path";
import { execSync } from "child_process";

// Configuration
const BITRES_ROOT = process.cwd();
const INTERFACE_ROOT = path.join(BITRES_ROOT, "..", "interface");
const INTERFACE_CONFIG = path.join(INTERFACE_ROOT, "src/config/contracts.json");

const NETWORKS = {
  local: {
    chainId: 31337,
    prefix: "FullSystemLocal#",
    deploymentDir: "ignition/deployments/chain-31337",
  },
  sepolia: {
    chainId: 11155111,
    prefix: "FullSystemSepolia#",
    deploymentDir: "ignition/deployments/chain-11155111",
  },
};

// Address mapping: deployed name -> config structure
const ADDRESS_MAP = {
  tokens: {
    BRS: "BRS",
    BTD: "BTD",
    BTB: "BTB",
    stBTD: "stBTD",
    stBTB: "stBTB",
    WBTC: "WBTC",
    USDC: "USDC",
    USDT: "USDT",
    WETH: "WETH",
  },
  contracts: {
    ConfigCore: "ConfigCore",
    ConfigGov: "ConfigGov",
    Treasury: "Treasury",
    Minter: "Minter",
    InterestPool: "InterestPool",
    FarmingPool: "FarmingPool",
    StakingRouter: "StakingRouter",
    PriceOracle: "PriceOracle",
    IdealUSDManager: "IdealUSDManager",
    TWAPOracle: "TWAPOracle",
  },
  pairs: {
    WBTC_USDC: "PairWBTCUSDC",
    BTD_USDC: "PairBTDUSDC",
    BTB_BTD: "PairBTBBTD",
    BRS_BTD: "PairBRSBTD",
  },
  oracles: {
    ChainlinkBTCUSD: "ChainlinkBTCUSD",
    ChainlinkWBTCBTC: "ChainlinkWBTCBTC",
    MockPyth: "MockPyth",
    MockRedstone: "MockRedstone",
  },
};

function parseArgs() {
  const args = process.argv.slice(2);
  const options = {
    network: "auto",
    push: false,
    dryRun: false,
  };

  for (let i = 0; i < args.length; i++) {
    if (args[i] === "--network" && args[i + 1]) {
      options.network = args[++i];
    } else if (args[i] === "--push") {
      options.push = true;
    } else if (args[i] === "--dry-run") {
      options.dryRun = true;
    }
  }

  return options;
}

function loadDeployedAddresses(network) {
  const config = NETWORKS[network];
  if (!config) {
    throw new Error(`Unknown network: ${network}`);
  }

  const deploymentFile = path.join(BITRES_ROOT, config.deploymentDir, "deployed_addresses.json");

  if (!fs.existsSync(deploymentFile)) {
    return null;
  }

  const raw = JSON.parse(fs.readFileSync(deploymentFile, "utf8"));
  const map = {};

  for (const [key, value] of Object.entries(raw)) {
    const cleanKey = key.replace(config.prefix, "");
    map[cleanKey] = value;
  }

  return map;
}

function detectNetwork() {
  // Check which deployments exist
  const localExists = fs.existsSync(
    path.join(BITRES_ROOT, NETWORKS.local.deploymentDir, "deployed_addresses.json")
  );
  const sepoliaExists = fs.existsSync(
    path.join(BITRES_ROOT, NETWORKS.sepolia.deploymentDir, "deployed_addresses.json")
  );

  if (sepoliaExists && localExists) {
    // Both exist, prefer sepolia for production
    console.log("Both local and Sepolia deployments found. Using Sepolia.");
    return "sepolia";
  } else if (sepoliaExists) {
    return "sepolia";
  } else if (localExists) {
    return "local";
  }

  return null;
}

function buildConfig(addresses) {
  const config = {
    tokens: {},
    contracts: {},
    pairs: {},
    oracles: {},
  };

  for (const [category, mapping] of Object.entries(ADDRESS_MAP)) {
    for (const [configKey, deployedKey] of Object.entries(mapping)) {
      const address = addresses[deployedKey];
      if (address) {
        config[category][configKey] = address;
      }
    }
  }

  return config;
}

function loadCurrentConfig() {
  if (!fs.existsSync(INTERFACE_CONFIG)) {
    return null;
  }
  return JSON.parse(fs.readFileSync(INTERFACE_CONFIG, "utf8"));
}

function compareConfigs(oldConfig, newConfig) {
  const changes = [];

  for (const category of Object.keys(ADDRESS_MAP)) {
    for (const key of Object.keys(ADDRESS_MAP[category])) {
      const oldValue = oldConfig?.[category]?.[key];
      const newValue = newConfig[category]?.[key];

      if (oldValue !== newValue) {
        changes.push({
          category,
          key,
          old: oldValue || "(none)",
          new: newValue || "(none)",
        });
      }
    }
  }

  return changes;
}

function saveConfig(config) {
  const dir = path.dirname(INTERFACE_CONFIG);
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
  }
  fs.writeFileSync(INTERFACE_CONFIG, JSON.stringify(config, null, 2) + "\n");
}

function gitPush() {
  const cwd = INTERFACE_ROOT;

  try {
    // Check if there are changes
    const status = execSync("git status --porcelain src/config/contracts.json", { cwd, encoding: "utf8" });
    if (!status.trim()) {
      console.log("No changes to commit.");
      return false;
    }

    // Stage, commit, and push
    console.log("=> Staging changes...");
    execSync("git add src/config/contracts.json", { cwd, stdio: "inherit" });

    console.log("=> Committing...");
    const message = `Update contract addresses from bitres deployment

- Auto-generated by update-interface-config.mjs`;
    execSync(`git commit -m "${message}"`, { cwd, stdio: "inherit" });

    console.log("=> Pushing to GitHub...");
    execSync("git push", { cwd, stdio: "inherit" });

    return true;
  } catch (err) {
    console.error("Git operation failed:", err.message);
    return false;
  }
}

async function main() {
  console.log("=".repeat(60));
  console.log("  Update Interface Config");
  console.log("=".repeat(60));

  const options = parseArgs();

  // Check interface project exists
  if (!fs.existsSync(INTERFACE_ROOT)) {
    console.error(`\nError: Interface project not found at ${INTERFACE_ROOT}`);
    console.error("Expected directory structure:");
    console.error("  bitres-labs/");
    console.error("    bitres/      (this project)");
    console.error("    interface/   (frontend project)");
    process.exit(1);
  }

  // Determine network
  let network = options.network;
  if (network === "auto") {
    network = detectNetwork();
    if (!network) {
      console.error("\nError: No deployments found. Deploy contracts first:");
      console.error("  npm run local:deploy    (for local)");
      console.error("  npm run sepolia:deploy  (for Sepolia)");
      process.exit(1);
    }
  }

  console.log(`\n=> Network: ${network}`);
  console.log(`=> Source: ${NETWORKS[network].deploymentDir}`);
  console.log(`=> Target: ${INTERFACE_CONFIG}`);

  // Load deployed addresses
  const addresses = loadDeployedAddresses(network);
  if (!addresses) {
    console.error(`\nError: No deployment found for ${network}`);
    process.exit(1);
  }

  console.log(`=> Found ${Object.keys(addresses).length} deployed contracts`);

  // Build new config
  const newConfig = buildConfig(addresses);

  // Load current config and compare
  const currentConfig = loadCurrentConfig();
  const changes = compareConfigs(currentConfig, newConfig);

  if (changes.length === 0) {
    console.log("\n=> No changes detected. Config is up to date.");
    return;
  }

  // Show changes
  console.log(`\n=> ${changes.length} changes detected:`);
  for (const change of changes) {
    console.log(`   ${change.category}.${change.key}:`);
    console.log(`     - ${change.old}`);
    console.log(`     + ${change.new}`);
  }

  if (options.dryRun) {
    console.log("\n=> Dry run mode. No files modified.");
    return;
  }

  // Save config
  console.log("\n=> Updating config...");
  saveConfig(newConfig);
  console.log("   Config saved.");

  // Push to GitHub if requested
  if (options.push) {
    console.log("\n=> Pushing to GitHub...");
    const pushed = gitPush();
    if (pushed) {
      console.log("   Changes pushed successfully.");
      console.log("   Vercel will auto-deploy from GitHub.");
    }
  } else {
    console.log("\n=> To push changes to GitHub:");
    console.log("   npm run update:interface -- --push");
    console.log("   or manually: cd ../interface && git add . && git commit && git push");
  }

  console.log("\n" + "=".repeat(60));
  console.log("  Done!");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
