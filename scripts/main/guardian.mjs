/**
 * BRS Guardian - Local Network Monitor & Time Manager
 *
 * Features:
 * - Enables interval mining for automatic block production
 * - Supports real-time mode (block time = system time) or accelerated mode
 * - Displays real-time mining stats and BRS distribution
 *
 * Run: node scripts/main/guardian.mjs
 *
 * Options:
 *   --realtime            Sync block time to real system time (for permit/signature testing)
 *   --speed <multiplier>  Time acceleration (default: 60 = 1 min real = 1 hour chain)
 *
 * Examples:
 *   node scripts/main/guardian.mjs --realtime     # Use real time (recommended for frontend testing)
 *   node scripts/main/guardian.mjs --speed 60     # 60x acceleration (1 min = 1 hour chain time)
 */

import fs from "fs";
import path from "path";
import { createPublicClient, createWalletClient, http, formatUnits } from "viem";
import { hardhat } from "viem/chains";

const RPC_URL = process.env.RPC_URL || "http://localhost:8545";
const ADDR_FILE = path.join(process.cwd(), "ignition/deployments/chain-31337/deployed_addresses.json");

// Parse arguments
const args = process.argv.slice(2);
let timeSpeed = 60; // 60x speed: 1 real second = 60 chain seconds
let useRealTime = false; // Use real system time instead of acceleration
for (let i = 0; i < args.length; i++) {
  if (args[i] === "--speed" && args[i + 1]) {
    timeSpeed = parseInt(args[i + 1]);
  }
  if (args[i] === "--realtime") {
    useRealTime = true;
  }
}

const REFRESH_INTERVAL_MS = 2000;
const MINING_INTERVAL_MS = 2000;

const colors = {
  reset: "\x1b[0m",
  bright: "\x1b[1m",
  cyan: "\x1b[36m",
  yellow: "\x1b[33m",
  green: "\x1b[32m",
  magenta: "\x1b[35m",
  red: "\x1b[31m",
};

function loadAddresses() {
  if (!fs.existsSync(ADDR_FILE)) {
    throw new Error("deployed_addresses.json not found. Run Ignition deployment first.");
  }
  const raw = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  const map = {};
  for (const [k, v] of Object.entries(raw)) {
    map[k.replace("FullSystemLocal#", "")] = v;
  }
  return map;
}

async function rpcCall(method, params = []) {
  const response = await fetch(RPC_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ jsonrpc: "2.0", method, params, id: Date.now() }),
  });
  const data = await response.json();
  return data.result;
}

async function enableAutoMining() {
  console.log("\n⛏️  Enabling interval mining...");
  try {
    await rpcCall("evm_setAutomine", [true]);
  } catch {}
  // Only enable interval mining in accelerated mode
  // In realtime mode, we control mining ourselves to prevent double-mining
  if (!useRealTime) {
    await rpcCall("evm_setIntervalMining", [MINING_INTERVAL_MS]);
    console.log(`   ✓ Blocks mined every ${MINING_INTERVAL_MS}ms`);
  } else {
    // Disable interval mining in realtime mode to prevent timestamp drift
    await rpcCall("evm_setIntervalMining", [0]);
    console.log(`   ✓ Manual mining enabled (realtime mode)`);
  }
}

async function advanceTime(seconds) {
  await rpcCall("evm_increaseTime", [seconds]);
  await rpcCall("evm_mine", []);
}

// Sync block time to real system time
// In realtime mode, we control mining to keep block time = real time
async function syncToRealTime() {
  const realTime = Math.floor(Date.now() / 1000);
  await rpcCall("evm_setNextBlockTimestamp", [realTime]);
  await rpcCall("evm_mine", []);
}

const formatNum = (value, decimals = 18) => {
  const num = Number(formatUnits(BigInt(value || 0), decimals));
  return num.toLocaleString("en-US", { maximumFractionDigits: 2 });
};

const formatCompact = (value, decimals = 18) => {
  const num = Number(formatUnits(BigInt(value || 0), decimals));
  if (num >= 1e9) return (num / 1e9).toFixed(2) + "B";
  if (num >= 1e6) return (num / 1e6).toFixed(2) + "M";
  if (num >= 1e3) return (num / 1e3).toFixed(2) + "K";
  return num.toFixed(2);
};

async function main() {
  const addr = loadAddresses();
  const client = createPublicClient({
    chain: { ...hardhat, id: 31337 },
    transport: http(RPC_URL),
  });

  // ABIs
  const erc20Abi = [
    { inputs: [], name: "totalSupply", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [{ name: "account", type: "address" }], name: "balanceOf", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  ];
  const farmingAbi = [
    { inputs: [], name: "startTime", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "minted", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "totalAllocPoint", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "poolLength", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "currentRewardPerSecond", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  ];
  const priceOracleAbi = [
    { inputs: [], name: "getWBTCPrice", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "getBTDPrice", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "getBRSPrice", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  ];

  await enableAutoMining();

  // Sync to real time first if using realtime mode
  if (useRealTime) {
    console.log(`\n⏰ Real-Time Mode: Block time synced to system time`);
    await syncToRealTime();
    console.log(`   ✓ Block time synchronized to ${new Date().toLocaleString()}`);
  } else {
    console.log(`\n⏰ Time Acceleration: ${timeSpeed}x (1 real second = ${timeSpeed} chain seconds)`);
  }
  console.log(`${colors.magenta}Press Ctrl+C to exit${colors.reset}\n`);

  let startRealTime = Date.now();
  let totalAdvanced = 0;

  // Time management loop
  setInterval(async () => {
    try {
      if (useRealTime) {
        // Keep block time in sync with real time
        await syncToRealTime();
      } else {
        // Accelerate time
        await advanceTime(timeSpeed);
        totalAdvanced += timeSpeed;
      }
    } catch {}
  }, 1000);

  // Display loop
  setInterval(async () => {
    try {
      const block = await client.getBlock({ blockTag: "latest" });
      const blockTime = Number(block.timestamp);

      const [totalSupply, farmingBalance, treasuryBalance, minted, rewardPerSec, wbtcPrice, btdPrice, brsPrice] =
        await Promise.all([
          client.readContract({ address: addr.BRS, abi: erc20Abi, functionName: "totalSupply" }),
          client.readContract({ address: addr.BRS, abi: erc20Abi, functionName: "balanceOf", args: [addr.FarmingPool] }),
          client.readContract({ address: addr.BRS, abi: erc20Abi, functionName: "balanceOf", args: [addr.Treasury] }),
          client.readContract({ address: addr.FarmingPool, abi: farmingAbi, functionName: "minted" }),
          client.readContract({ address: addr.FarmingPool, abi: farmingAbi, functionName: "currentRewardPerSecond" }),
          client.readContract({ address: addr.PriceOracle, abi: priceOracleAbi, functionName: "getWBTCPrice" }).catch(() => 0n),
          client.readContract({ address: addr.PriceOracle, abi: priceOracleAbi, functionName: "getBTDPrice" }).catch(() => 0n),
          client.readContract({ address: addr.PriceOracle, abi: priceOracleAbi, functionName: "getBRSPrice" }).catch(() => 0n),
        ]);

      const distributed = totalSupply - farmingBalance;
      const distributedPct = (Number(distributed) / Number(totalSupply) * 100).toFixed(4);

      const chainHours = Math.floor(totalAdvanced / 3600);
      const chainMins = Math.floor((totalAdvanced % 3600) / 60);

      console.clear();
      console.log(`${colors.bright}═══════════════════════════════════════════════════════════════════════${colors.reset}`);
      console.log(`${colors.bright}  BRS Guardian - Local Network Monitor${colors.reset}`);
      console.log(`${colors.bright}═══════════════════════════════════════════════════════════════════════${colors.reset}`);
      console.log();
      console.log(`  Block #${block.number}  |  ${new Date(blockTime * 1000).toLocaleString()}`);
      const timeMode = useRealTime
        ? `${colors.green}Real-Time${colors.reset}`
        : `${colors.cyan}${timeSpeed}x${colors.reset}`;
      console.log(`  Mode: ${timeMode}  |  Chain elapsed: ${colors.cyan}${chainHours}h ${chainMins}m${colors.reset}`);
      console.log();
      console.log(`${colors.bright}  BRS Token${colors.reset}`);
      console.log(`  ─────────────────────────────────────────────────────────────────────`);
      console.log(`  Total Supply:     ${colors.cyan}${formatCompact(totalSupply)}${colors.reset}`);
      console.log(`  In FarmingPool:   ${colors.green}${formatCompact(farmingBalance)}${colors.reset}`);
      console.log(`  Distributed:      ${colors.yellow}${formatCompact(distributed)}${colors.reset} (${distributedPct}%)`);
      console.log(`  Mining Rate:      ${colors.magenta}${formatNum(rewardPerSec)} BRS/sec${colors.reset}`);
      console.log();
      console.log(`${colors.bright}  Prices${colors.reset}`);
      console.log(`  ─────────────────────────────────────────────────────────────────────`);
      console.log(`  WBTC: ${colors.yellow}$${formatNum(wbtcPrice)}${colors.reset}  |  BTD: ${colors.green}$${formatNum(btdPrice)}${colors.reset}  |  BRS: ${colors.cyan}$${formatNum(brsPrice)}${colors.reset}`);
      console.log();
      console.log(`${colors.bright}═══════════════════════════════════════════════════════════════════════${colors.reset}`);
      console.log(`  ${colors.magenta}Ctrl+C to exit${colors.reset}`);
    } catch (err) {
      console.error("Refresh error:", err.message);
    }
  }, REFRESH_INTERVAL_MS);

  await new Promise(() => {});
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
