/**
 * Initialize Farming Pools (Phase 2) - Sepolia
 *
 * @deprecated This script is no longer needed.
 * Farming pool staking is now included in init-sepolia.mjs.
 * FarmingPool uses token amount validation instead of USD value,
 * so TWAP is not required for staking.
 *
 * This script is kept for backwards compatibility but will simply
 * report the current staking status.
 *
 * Run:
 *   npx hardhat run scripts/sepolia/init-farm.mjs --network sepolia
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";
import { createPublicClient, http, parseEther, parseUnits } from "viem";
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
  console.log("=".repeat(60));
  console.log("  Bitres Farming Pool Initialization (Phase 2)");
  console.log("=".repeat(60));

  const addresses = loadAddresses();
  const connection = await hre.network.connect();
  const { viem } = connection;
  const wallets = await viem.getWalletClients();
  const [owner] = wallets;

  const rpcUrl = hre.network.config?.url || process.env.SEPOLIA_RPC_URL || "https://rpc.sepolia.org";
  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(rpcUrl, { timeout: 60000 }),
  });

  console.log(`=> Deployer: ${owner.account.address}`);

  // Load ABIs
  const loadAbi = (relPath) =>
    JSON.parse(fs.readFileSync(path.join(process.cwd(), "artifacts", relPath), "utf8")).abi;

  const get = (key, abiName = key) => viem.getContractAt(abiName, addresses[key]);

  // Load contracts
  const brs = await get("BRS", "contracts/BRS.sol:BRS");
  const wbtc = await get("WBTC", "contracts/local/MockWBTC.sol:MockWBTC");
  const usdc = await get("USDC", "contracts/local/MockUSDC.sol:MockUSDC");
  const usdt = await get("USDT", "contracts/local/MockUSDT.sol:MockUSDT");
  const weth = await get("WETH", "contracts/local/MockWETH.sol:MockWETH");
  const stBTD = await get("stBTD", "contracts/stBTD.sol:stBTD");
  const stBTB = await get("stBTB", "contracts/stBTB.sol:stBTB");
  const farming = await get("FarmingPool", "contracts/FarmingPool.sol:FarmingPool");
  const priceOracle = await get("PriceOracle", "contracts/PriceOracle.sol:PriceOracle");

  const pairBRSBTD = await get("PairBRSBTD", "contracts/local/UniswapV2Pair.sol:UniswapV2Pair");
  const pairBTDUSDC = await get("PairBTDUSDC", "contracts/local/UniswapV2Pair.sol:UniswapV2Pair");
  const pairBTBBTD = await get("PairBTBBTD", "contracts/local/UniswapV2Pair.sol:UniswapV2Pair");

  const pairAbi = loadAbi("contracts/local/UniswapV2Pair.sol/UniswapV2Pair.json");
  const farmingAbi = loadAbi("contracts/FarmingPool.sol/FarmingPool.json");
  const priceOracleAbi = loadAbi("contracts/PriceOracle.sol/PriceOracle.json");

  // =========================================================================
  // 1) Check current status (TWAP check removed - no longer required)
  // =========================================================================
  console.log("\n=> This script is deprecated. Farming is now initialized in init-sepolia.mjs");
  console.log("   FarmingPool uses token amount validation, TWAP not required for staking.");
  console.log("\n=> Checking current staking status...");

  // =========================================================================
  // 2) Get LP balances
  // =========================================================================
  console.log("\n=> Reading LP balances...");

  const lpBRSBTD = await publicClient.readContract({
    address: pairBRSBTD.address,
    abi: pairAbi,
    functionName: "balanceOf",
    args: [owner.account.address],
  });
  const lpBTDUSDC = await publicClient.readContract({
    address: pairBTDUSDC.address,
    abi: pairAbi,
    functionName: "balanceOf",
    args: [owner.account.address],
  });
  const lpBTBBTD = await publicClient.readContract({
    address: pairBTBBTD.address,
    abi: pairAbi,
    functionName: "balanceOf",
    args: [owner.account.address],
  });

  console.log(`   BRS/BTD LP: ${lpBRSBTD}`);
  console.log(`   BTD/USDC LP: ${lpBTDUSDC}`);
  console.log(`   BTB/BTD LP: ${lpBTBBTD}`);

  // =========================================================================
  // 3) Seed staking for pools
  // =========================================================================
  console.log("\n=> Seeding staking for farming pools...");

  // Calculate stake amounts (use 1% of LP or fixed small amounts)
  const stakePlans = [
    { id: 0, token: pairBRSBTD, amount: lpBRSBTD > 0n ? lpBRSBTD / 100n : 0n, name: "BRS/BTD LP" },
    { id: 1, token: pairBTDUSDC, amount: lpBTDUSDC > 0n ? lpBTDUSDC / 100n : 0n, name: "BTD/USDC LP" },
    { id: 2, token: pairBTBBTD, amount: lpBTBBTD > 0n ? lpBTBBTD / 100n : 0n, name: "BTB/BTD LP" },
    { id: 3, token: usdc, amount: parseUnits("1", 6), name: "USDC" },
    { id: 4, token: usdt, amount: parseUnits("1", 6), name: "USDT" },
    { id: 5, token: wbtc, amount: parseUnits("0.000005", 8), name: "WBTC" },
    { id: 6, token: weth, amount: parseEther("0.0002"), name: "WETH" },
    { id: 7, token: stBTD, amount: parseEther("0.1"), name: "stBTD" },
    { id: 8, token: stBTB, amount: parseEther("0.1"), name: "stBTB" },
    { id: 9, token: brs, amount: parseEther("0.9"), name: "BRS" },
  ];

  let successCount = 0;
  let skipCount = 0;

  for (const plan of stakePlans) {
    if (plan.amount === 0n) {
      console.log(`   ⏭ pool ${plan.id} (${plan.name}) skipped: no balance`);
      skipCount++;
      continue;
    }

    // Check if already staked
    const [stakedAmount] = await publicClient.readContract({
      address: farming.address,
      abi: farmingAbi,
      functionName: "userInfo",
      args: [plan.id, owner.account.address],
    });

    if (stakedAmount > 0n) {
      console.log(`   ⏭ pool ${plan.id} (${plan.name}) already staked: ${stakedAmount}`);
      skipCount++;
      continue;
    }

    try {
      // Approve
      const approveTx = await plan.token.write.approve([farming.address, plan.amount], {
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: approveTx });

      // Deposit
      const depositTx = await farming.write.deposit([plan.id, plan.amount], {
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: depositTx });

      console.log(`   ✓ pool ${plan.id} (${plan.name}) staked: ${plan.amount}`);
      successCount++;
    } catch (err) {
      console.log(`   ❌ pool ${plan.id} (${plan.name}) failed: ${err.message?.slice(0, 60) || err}`);
    }
  }

  // =========================================================================
  // Done
  // =========================================================================
  console.log("\n" + "=".repeat(60));
  console.log(`  ✅ Farming initialization complete!`);
  console.log(`     Staked: ${successCount}, Skipped: ${skipCount}`);
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
