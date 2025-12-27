/**
 * Health Check Script for Sepolia Testnet
 *
 * Verifies that all contracts are deployed and configured correctly.
 * Run after deployment to ensure system is operational.
 *
 * Run:
 *   npx hardhat run scripts/sepolia/health-check.mjs --network sepolia
 *   npm run sepolia:health-check
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";
import { createPublicClient, http, formatEther, formatUnits } from "viem";
import { sepolia } from "viem/chains";

const CHAIN_ID = 11155111;
const ADDR_FILE = path.join(
  process.cwd(),
  `ignition/deployments/chain-${CHAIN_ID}/deployed_addresses.json`
);

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
  console.log("=".repeat(70));
  console.log("  Bitres Sepolia Health Check");
  console.log("=".repeat(70));

  const addresses = loadAddresses();
  const rpcUrl = hre.network.config?.url || process.env.SEPOLIA_RPC_URL;

  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(rpcUrl, { timeout: 60000 }),
  });

  let passed = 0;
  let failed = 0;

  const check = async (name, fn) => {
    try {
      const result = await fn();
      console.log(`  ✓ ${name}: ${result}`);
      passed++;
      return true;
    } catch (err) {
      console.log(`  ✗ ${name}: ${err.message?.slice(0, 60) || err}`);
      failed++;
      return false;
    }
  };

  // =========================================================================
  // 1) Core Contracts Deployed
  // =========================================================================
  console.log("\n=> Core Contracts");
  console.log("-".repeat(70));

  const coreContracts = [
    "BTD", "BTB", "BRS", "WBTC", "USDC", "USDT", "WETH",
    "stBTD", "stBTB", "Minter", "Treasury", "FarmingPool",
    "InterestPool", "PriceOracle", "ConfigCore", "ConfigGov"
  ];

  for (const name of coreContracts) {
    await check(name, async () => {
      const addr = addresses[name];
      if (!addr) throw new Error("Address not found");
      const code = await publicClient.getCode({ address: addr });
      if (!code || code === "0x") throw new Error("No code at address");
      return addr.slice(0, 10) + "...";
    });
  }

  // =========================================================================
  // 2) Uniswap Pairs
  // =========================================================================
  console.log("\n=> Uniswap Pairs");
  console.log("-".repeat(70));

  const pairAbi = [
    { inputs: [], name: "totalSupply", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "getReserves", outputs: [{ type: "uint112" }, { type: "uint112" }, { type: "uint32" }], stateMutability: "view", type: "function" },
  ];

  const pairs = [
    { name: "PairWBTCUSDC", label: "WBTC/USDC" },
    { name: "PairBTDUSDC", label: "BTD/USDC" },
    { name: "PairBTBBTD", label: "BTB/BTD" },
    { name: "PairBRSBTD", label: "BRS/BTD" },
  ];

  for (const pair of pairs) {
    await check(pair.label, async () => {
      const addr = addresses[pair.name];
      if (!addr) throw new Error("Address not found");
      const [r0, r1] = await publicClient.readContract({
        address: addr,
        abi: pairAbi,
        functionName: "getReserves",
      });
      if (r0 === 0n && r1 === 0n) throw new Error("No liquidity");
      return `Reserves: ${r0.toString().slice(0, 10)}... / ${r1.toString().slice(0, 10)}...`;
    });
  }

  // =========================================================================
  // 3) Oracles
  // =========================================================================
  console.log("\n=> Oracle Configuration");
  console.log("-".repeat(70));

  const chainlinkAbi = [
    { inputs: [], name: "latestRoundData", outputs: [
      { type: "uint80" }, { type: "int256" }, { type: "uint256" }, { type: "uint256" }, { type: "uint80" }
    ], stateMutability: "view", type: "function" },
  ];

  await check("Chainlink BTC/USD", async () => {
    const [, price] = await publicClient.readContract({
      address: addresses.ChainlinkBTCUSD,
      abi: chainlinkAbi,
      functionName: "latestRoundData",
    });
    return `$${(Number(price) / 1e8).toLocaleString()}`;
  });

  const priceOracleAbi = [
    { inputs: [], name: "useTWAP", outputs: [{ type: "bool" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "getWBTCPrice", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "getBTDPrice", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "getBTBPrice", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "getBRSPrice", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  ];

  await check("TWAP Mode", async () => {
    const useTWAP = await publicClient.readContract({
      address: addresses.PriceOracle,
      abi: priceOracleAbi,
      functionName: "useTWAP",
    });
    return useTWAP ? "Enabled" : "Disabled (run enable-twap after 30 min)";
  });

  // =========================================================================
  // 4) Token Prices (via PriceOracle)
  // =========================================================================
  console.log("\n=> Token Prices (from PriceOracle)");
  console.log("-".repeat(70));

  const priceChecks = [
    { name: "WBTC", fn: "getWBTCPrice" },
    { name: "BTD", fn: "getBTDPrice" },
    { name: "BTB", fn: "getBTBPrice" },
    { name: "BRS", fn: "getBRSPrice" },
  ];

  for (const pc of priceChecks) {
    await check(pc.name, async () => {
      const price = await publicClient.readContract({
        address: addresses.PriceOracle,
        abi: priceOracleAbi,
        functionName: pc.fn,
      });
      return `$${formatEther(price)}`;
    });
  }

  // =========================================================================
  // 5) Farming Pool Configuration
  // =========================================================================
  console.log("\n=> FarmingPool");
  console.log("-".repeat(70));

  const farmingAbi = [
    { inputs: [], name: "poolLength", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "startTime", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "currentRewardPerSecond", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  ];

  await check("Pool Count", async () => {
    const count = await publicClient.readContract({
      address: addresses.FarmingPool,
      abi: farmingAbi,
      functionName: "poolLength",
    });
    if (count === 0n) throw new Error("No pools configured");
    return `${count} pools`;
  });

  await check("Reward Rate", async () => {
    const rate = await publicClient.readContract({
      address: addresses.FarmingPool,
      abi: farmingAbi,
      functionName: "currentRewardPerSecond",
    });
    return `${formatEther(rate)} BRS/sec`;
  });

  // =========================================================================
  // 6) Vault Configuration
  // =========================================================================
  console.log("\n=> Vaults (stBTD/stBTB)");
  console.log("-".repeat(70));

  const vaultAbi = [
    { inputs: [], name: "totalSupply", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "totalAssets", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  ];

  for (const vault of ["stBTD", "stBTB"]) {
    await check(vault, async () => {
      const supply = await publicClient.readContract({
        address: addresses[vault],
        abi: vaultAbi,
        functionName: "totalSupply",
      });
      const assets = await publicClient.readContract({
        address: addresses[vault],
        abi: vaultAbi,
        functionName: "totalAssets",
      });
      if (supply === 0n) throw new Error("Vault not initialized");
      return `Supply: ${formatEther(supply)}, Assets: ${formatEther(assets)}`;
    });
  }

  // =========================================================================
  // 7) TWAP Oracle Status
  // =========================================================================
  console.log("\n=> TWAP Oracle Status");
  console.log("-".repeat(70));

  const twapAbi = [
    { inputs: [{ name: "pair", type: "address" }], name: "isTWAPReady", outputs: [{ type: "bool" }], stateMutability: "view", type: "function" },
    { inputs: [{ name: "pair", type: "address" }], name: "getObservationInfo", outputs: [
      { type: "uint32" }, { type: "uint32" }, { type: "uint32" }
    ], stateMutability: "view", type: "function" },
  ];

  for (const pair of pairs) {
    await check(`TWAP ${pair.label}`, async () => {
      const [, , elapsed] = await publicClient.readContract({
        address: addresses.TWAPOracle,
        abi: twapAbi,
        functionName: "getObservationInfo",
        args: [addresses[pair.name]],
      });
      const ready = elapsed >= 30 * 60;
      const mins = Math.floor(Number(elapsed) / 60);
      return ready ? `Ready (${mins} min)` : `${mins} min elapsed (need 30)`;
    });
  }

  // =========================================================================
  // Summary
  // =========================================================================
  console.log("\n" + "=".repeat(70));
  console.log(`  Summary: ${passed} passed, ${failed} failed`);
  console.log("=".repeat(70));

  if (failed > 0) {
    console.log("\n⚠  Some checks failed. Review the output above.");
    process.exit(1);
  } else {
    console.log("\n✅ All checks passed! System is operational.");
  }
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
