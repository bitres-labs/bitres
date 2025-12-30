/**
 * TWAP Warmup Script for Sepolia
 *
 * Run this script 30+ minutes after deployment to complete TWAP initialization.
 * After running, all token prices will be available via PriceOracle.
 *
 * How TWAP works:
 * - First observation is recorded during init-sepolia.mjs
 * - This script records the second observation after 30 min
 * - With 2 observations >= 30 min apart, TWAP prices become available
 *
 * Usage:
 *   npx hardhat run scripts/sepolia/warmup-twap.mjs --network sepolia
 *   npm run sepolia:warmup-twap
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";

const ADDR_FILE = path.join(process.cwd(), "ignition/deployments/chain-11155111/deployed_addresses.json");

const TWAP_ABI = [
  {
    inputs: [{ name: "pair", type: "address" }],
    name: "updateIfNeeded",
    outputs: [{ type: "bool" }],
    stateMutability: "nonpayable",
    type: "function"
  },
  {
    inputs: [{ name: "pair", type: "address" }],
    name: "needsUpdate",
    outputs: [{ type: "bool" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [{ name: "pair", type: "address" }],
    name: "isTWAPReady",
    outputs: [{ type: "bool" }],
    stateMutability: "view",
    type: "function"
  },
  {
    inputs: [{ name: "pair", type: "address" }],
    name: "getObservationInfo",
    outputs: [
      { name: "olderTimestamp", type: "uint32" },
      { name: "newerTimestamp", type: "uint32" },
      { name: "timeElapsed", type: "uint32" }
    ],
    stateMutability: "view",
    type: "function"
  }
];

const PRICE_ORACLE_ABI = [
  { inputs: [], name: "getWBTCPrice", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "getBTDPrice", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "getBTBPrice", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "getBRSPrice", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
];

const CONFIG_CORE_ABI = [
  { inputs: [], name: "POOL_WBTC_USDC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "POOL_BTD_USDC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "POOL_BTB_BTD", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "POOL_BRS_BTD", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
];

async function main() {
  console.log("\n============================================================");
  console.log("  TWAP Warmup - Complete TWAP Initialization");
  console.log("============================================================\n");

  // Load addresses
  const raw = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  const addr = {};
  for (const [key, value] of Object.entries(raw)) {
    const name = key.replace("FullSystemSepolia#", "");
    addr[name] = value;
  }

  const connection = await hre.network.connect();
  const { viem } = connection;
  const [walletClient] = await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();

  console.log(`=> Deployer: ${walletClient.account.address}`);
  console.log(`=> TWAPOracle: ${addr.TWAPOracle}`);
  console.log(`=> ConfigCore: ${addr.ConfigCore}`);
  console.log(`=> PriceOracle: ${addr.PriceOracle}\n`);

  // Read pool addresses from ConfigCore (the actual addresses used by PriceOracle)
  console.log("=> Reading pool addresses from ConfigCore...\n");
  const poolWbtcUsdc = await publicClient.readContract({
    address: addr.ConfigCore,
    abi: CONFIG_CORE_ABI,
    functionName: "POOL_WBTC_USDC",
  });
  const poolBtdUsdc = await publicClient.readContract({
    address: addr.ConfigCore,
    abi: CONFIG_CORE_ABI,
    functionName: "POOL_BTD_USDC",
  });
  const poolBtbBtd = await publicClient.readContract({
    address: addr.ConfigCore,
    abi: CONFIG_CORE_ABI,
    functionName: "POOL_BTB_BTD",
  });
  const poolBrsBtd = await publicClient.readContract({
    address: addr.ConfigCore,
    abi: CONFIG_CORE_ABI,
    functionName: "POOL_BRS_BTD",
  });

  console.log(`   WBTC/USDC: ${poolWbtcUsdc}`);
  console.log(`   BTD/USDC:  ${poolBtdUsdc}`);
  console.log(`   BTB/BTD:   ${poolBtbBtd}`);
  console.log(`   BRS/BTD:   ${poolBrsBtd}\n`);

  const pairs = [
    { name: "WBTC/USDC", address: poolWbtcUsdc },
    { name: "BTD/USDC", address: poolBtdUsdc },
    { name: "BTB/BTD", address: poolBtbBtd },
    { name: "BRS/BTD", address: poolBrsBtd },
  ];

  // Check current TWAP status
  console.log("=> Checking current TWAP status...\n");

  let allReady = true;
  let anyNeedsUpdate = false;

  for (const pair of pairs) {
    const isReady = await publicClient.readContract({
      address: addr.TWAPOracle,
      abi: TWAP_ABI,
      functionName: "isTWAPReady",
      args: [pair.address],
    });

    const needsUpdate = await publicClient.readContract({
      address: addr.TWAPOracle,
      abi: TWAP_ABI,
      functionName: "needsUpdate",
      args: [pair.address],
    });

    const [olderTs, newerTs, elapsed] = await publicClient.readContract({
      address: addr.TWAPOracle,
      abi: TWAP_ABI,
      functionName: "getObservationInfo",
      args: [pair.address],
    });

    const elapsedMin = Number(elapsed) / 60;
    const status = isReady ? "✓ Ready" : needsUpdate ? "⏳ Needs update" : `⏳ Wait ${(30 - elapsedMin).toFixed(1)} min`;

    console.log(`   ${pair.name}: ${status} (elapsed: ${elapsedMin.toFixed(1)} min)`);

    if (!isReady) allReady = false;
    if (needsUpdate) anyNeedsUpdate = true;
  }

  console.log("");

  if (allReady) {
    console.log("=> All TWAP prices are already ready!\n");
  } else if (!anyNeedsUpdate) {
    console.log("=> TWAP not ready yet. Please wait until 30 minutes have passed since deployment.\n");
    console.log("   Run this script again after the wait period.\n");
    return;
  } else {
    // Update TWAP observations
    console.log("=> Updating TWAP observations...\n");

    for (const pair of pairs) {
      const needsUpdate = await publicClient.readContract({
        address: addr.TWAPOracle,
        abi: TWAP_ABI,
        functionName: "needsUpdate",
        args: [pair.address],
      });

      if (needsUpdate) {
        const hash = await walletClient.writeContract({
          address: addr.TWAPOracle,
          abi: TWAP_ABI,
          functionName: "updateIfNeeded",
          args: [pair.address],
        });
        await publicClient.waitForTransactionReceipt({ hash });
        console.log(`   ✓ ${pair.name} updated (tx: ${hash.slice(0, 10)}...)`);
      } else {
        console.log(`   - ${pair.name} already up to date`);
      }
    }

    console.log("");
  }

  // Verify prices are now available
  console.log("=> Verifying prices are available...\n");

  try {
    const wbtcPrice = await publicClient.readContract({
      address: addr.PriceOracle,
      abi: PRICE_ORACLE_ABI,
      functionName: "getWBTCPrice",
    });
    console.log(`   WBTC: $${(Number(wbtcPrice) / 1e18).toLocaleString()}`);

    const btdPrice = await publicClient.readContract({
      address: addr.PriceOracle,
      abi: PRICE_ORACLE_ABI,
      functionName: "getBTDPrice",
    });
    console.log(`   BTD:  $${(Number(btdPrice) / 1e18).toFixed(4)}`);

    const btbPrice = await publicClient.readContract({
      address: addr.PriceOracle,
      abi: PRICE_ORACLE_ABI,
      functionName: "getBTBPrice",
    });
    console.log(`   BTB:  $${(Number(btbPrice) / 1e18).toFixed(4)}`);

    const brsPrice = await publicClient.readContract({
      address: addr.PriceOracle,
      abi: PRICE_ORACLE_ABI,
      functionName: "getBRSPrice",
    });
    console.log(`   BRS:  $${(Number(brsPrice) / 1e18).toFixed(4)}`);

    console.log("\n============================================================");
    console.log("  ✅ TWAP warmup complete! All prices are now available.");
    console.log("============================================================\n");
    console.log("The system is fully operational:");
    console.log("  - Minter mint/redeem: Ready");
    console.log("  - FarmingPool: Ready");
    console.log("  - Frontend: Will show prices after refresh\n");

  } catch (error) {
    console.log(`\n   ❌ Error getting prices: ${error.message}`);
    console.log("\n   TWAP may still need more time. Try again in a few minutes.\n");
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
