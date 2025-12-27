/**
 * Update TWAP Oracle Observations on Sepolia
 *
 * @deprecated TWAP is now enabled automatically in init-sepolia.mjs.
 * This script is now optional - use it to take additional TWAP observations
 * if you want to update prices after the initial 30-minute warmup period.
 *
 * Run:
 *   npx hardhat run scripts/sepolia/enable-twap.mjs --network sepolia
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";
import { createPublicClient, http } from "viem";
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
  console.log("  Enable TWAP Oracle on Sepolia");
  console.log("=".repeat(60));

  const addresses = loadAddresses();
  const connection = await hre.network.connect();
  const { viem } = connection;
  const wallets = await viem.getWalletClients();
  const [owner] = wallets;
  const rpcUrl = hre.network.config?.url || process.env.SEPOLIA_RPC_URL;

  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(rpcUrl, { timeout: 60000 }),
  });

  console.log(`\n=> Deployer: ${owner.account.address}`);

  const get = (key, abiName = key) => viem.getContractAt(abiName, addresses[key]);

  // Load contracts
  const twapOracle = await get("TWAPOracle", "contracts/UniswapV2TWAPOracle.sol:UniswapV2TWAPOracle");
  const priceOracle = await get("PriceOracle", "contracts/PriceOracle.sol:PriceOracle");
  const pairWBTCUSDC = await get("PairWBTCUSDC", "contracts/local/UniswapV2Pair.sol:UniswapV2Pair");
  const pairBTDUSDC = await get("PairBTDUSDC", "contracts/local/UniswapV2Pair.sol:UniswapV2Pair");
  const pairBTBBTD = await get("PairBTBBTD", "contracts/local/UniswapV2Pair.sol:UniswapV2Pair");
  const pairBRSBTD = await get("PairBRSBTD", "contracts/local/UniswapV2Pair.sol:UniswapV2Pair");

  const pairs = [
    { name: "WBTC/USDC", contract: pairWBTCUSDC },
    { name: "BTD/USDC", contract: pairBTDUSDC },
    { name: "BTB/BTD", contract: pairBTBBTD },
    { name: "BRS/BTD", contract: pairBRSBTD },
  ];

  // Check TWAP readiness before updating
  console.log("\n=> Checking TWAP observation status...");
  const twapOracleAbi = [
    {
      inputs: [{ name: "pair", type: "address" }],
      name: "isTWAPReady",
      outputs: [{ type: "bool" }],
      stateMutability: "view",
      type: "function",
    },
    {
      inputs: [{ name: "pair", type: "address" }],
      name: "getObservationInfo",
      outputs: [
        { name: "olderTimestamp", type: "uint32" },
        { name: "newerTimestamp", type: "uint32" },
        { name: "timeElapsed", type: "uint32" },
      ],
      stateMutability: "view",
      type: "function",
    },
  ];

  let allReady = true;
  for (const pair of pairs) {
    const [olderTs, newerTs, elapsed] = await publicClient.readContract({
      address: twapOracle.address,
      abi: twapOracleAbi,
      functionName: "getObservationInfo",
      args: [pair.contract.address],
    });

    const elapsedMins = Math.floor(Number(elapsed) / 60);
    const ready = elapsed >= 30 * 60; // 30 minutes
    console.log(`   ${pair.name}: ${elapsedMins} min elapsed ${ready ? "✓" : "(need 30 min)"}`);
    if (!ready) allReady = false;
  }

  if (!allReady) {
    console.log("\n⚠  Some pairs need more time. Please wait and run this script again.");
    process.exit(1);
  }

  // Take second TWAP observation
  console.log("\n=> Taking second TWAP observation...");
  for (const pair of pairs) {
    try {
      await twapOracle.write.update([pair.contract.address], { account: owner.account });
      console.log(`   ✓ ${pair.name} observation updated`);
    } catch (err) {
      console.log(`   ⚠ ${pair.name} update failed: ${err.message?.slice(0, 50) || err}`);
    }
  }

  // Verify TWAP is ready
  console.log("\n=> Verifying TWAP readiness...");
  for (const pair of pairs) {
    const isReady = await publicClient.readContract({
      address: twapOracle.address,
      abi: twapOracleAbi,
      functionName: "isTWAPReady",
      args: [pair.contract.address],
    });
    console.log(`   ${pair.name}: ${isReady ? "✓ Ready" : "✗ Not ready"}`);
  }

  // Enable TWAP on PriceOracle
  console.log("\n=> Enabling TWAP on PriceOracle...");
  await priceOracle.write.setUseTWAP([true], { account: owner.account });
  console.log("   ✓ TWAP enabled");

  console.log("\n" + "=".repeat(60));
  console.log("  ✅ TWAP Oracle enabled successfully!");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
