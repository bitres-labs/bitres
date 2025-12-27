/**
 * WBTC Price Sync Script for Sepolia
 *
 * Syncs Uniswap WBTC/USDC pool price with Chainlink BTC/USD oracle.
 * This script:
 * 1. Reads real BTC price from Chainlink
 * 2. Calculates target USDC reserve to match Chainlink price
 * 3. Adjusts pool reserves (transfers tokens and uses setReserves)
 * 4. Takes a TWAP observation for the oracle
 *
 * Run:
 *   npx hardhat run scripts/sepolia/price-sync.mjs --network sepolia
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";
import { createPublicClient, http, parseUnits } from "viem";
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
  console.log("  WBTC Price Sync - Sepolia");
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

  console.log(`=> Syncing as: ${owner.account.address}`);

  // Load ABIs
  const loadAbi = (relPath) =>
    JSON.parse(fs.readFileSync(path.join(process.cwd(), "artifacts", relPath), "utf8")).abi;

  const pairAbi = loadAbi("contracts/local/UniswapV2Pair.sol/UniswapV2Pair.json");
  const erc20Abi = loadAbi("contracts/local/MockWBTC.sol/MockWBTC.json");

  // Load contracts
  const get = (key, abiName = key) => viem.getContractAt(abiName, addresses[key]);
  const pairWBTCUSDC = await get("PairWBTCUSDC", "contracts/local/UniswapV2Pair.sol:UniswapV2Pair");
  const twapOracle = await get("TWAPOracle", "contracts/UniswapV2TWAPOracle.sol:UniswapV2TWAPOracle");
  const wbtc = await get("WBTC", "contracts/local/MockWBTC.sol:MockWBTC");
  const usdc = await get("USDC", "contracts/local/MockUSDC.sol:MockUSDC");

  // =========================================================================
  // 1) Read Chainlink BTC/USD price
  // =========================================================================
  console.log("\n=> Reading Chainlink BTC/USD price...");
  const chainlinkAbi = [
    {
      inputs: [],
      name: "latestRoundData",
      outputs: [
        { name: "roundId", type: "uint80" },
        { name: "answer", type: "int256" },
        { name: "startedAt", type: "uint256" },
        { name: "updatedAt", type: "uint256" },
        { name: "answeredInRound", type: "uint80" },
      ],
      stateMutability: "view",
      type: "function",
    },
  ];

  const [, btcPrice] = await publicClient.readContract({
    address: addresses.ChainlinkBTCUSD,
    abi: chainlinkAbi,
    functionName: "latestRoundData",
  });
  const btcPriceUsd = Number(btcPrice) / 1e8;
  console.log(`   Chainlink BTC/USD: $${btcPriceUsd.toLocaleString()}`);

  // =========================================================================
  // 2) Read current pool reserves
  // =========================================================================
  console.log("\n=> Reading current WBTC/USDC pool reserves...");
  const [reserve0, reserve1] = await publicClient.readContract({
    address: pairWBTCUSDC.address,
    abi: pairAbi,
    functionName: "getReserves",
  });

  const token0 = await publicClient.readContract({
    address: pairWBTCUSDC.address,
    abi: pairAbi,
    functionName: "token0",
  });

  // Determine which reserve is WBTC and which is USDC
  const isWbtcToken0 = token0.toLowerCase() === addresses.WBTC.toLowerCase();
  const wbtcReserve = isWbtcToken0 ? reserve0 : reserve1;
  const usdcReserve = isWbtcToken0 ? reserve1 : reserve0;

  // Current pool price (USDC per WBTC)
  // WBTC has 8 decimals, USDC has 6 decimals
  const currentPoolPrice = (Number(usdcReserve) / 1e6) / (Number(wbtcReserve) / 1e8);
  console.log(`   WBTC reserve: ${Number(wbtcReserve) / 1e8} WBTC`);
  console.log(`   USDC reserve: ${Number(usdcReserve) / 1e6} USDC`);
  console.log(`   Current pool price: $${currentPoolPrice.toLocaleString()}`);

  // =========================================================================
  // 3) Calculate target reserves
  // =========================================================================
  console.log("\n=> Calculating target reserves...");

  // Keep WBTC reserve the same, adjust USDC to match Chainlink price
  const targetUsdcReserve = BigInt(Math.floor((Number(wbtcReserve) / 1e8) * btcPriceUsd * 1e6));

  console.log(`   Target USDC reserve: ${Number(targetUsdcReserve) / 1e6} USDC`);

  const priceDiff = Math.abs(currentPoolPrice - btcPriceUsd) / btcPriceUsd * 100;
  console.log(`   Price difference: ${priceDiff.toFixed(2)}%`);

  if (priceDiff < 0.5) {
    console.log("   ⏭ Price within 0.5% tolerance, skipping adjustment");
  } else {
    // =========================================================================
    // 4) Adjust reserves
    // =========================================================================
    console.log("\n=> Adjusting pool reserves...");

    // Get current token balances in the pair
    const pairWbtcBalance = await publicClient.readContract({
      address: addresses.WBTC,
      abi: erc20Abi,
      functionName: "balanceOf",
      args: [pairWBTCUSDC.address],
    });
    const pairUsdcBalance = await publicClient.readContract({
      address: addresses.USDC,
      abi: erc20Abi,
      functionName: "balanceOf",
      args: [pairWBTCUSDC.address],
    });

    // Calculate how much USDC to add/remove
    const usdcDiff = targetUsdcReserve - usdcReserve;

    if (usdcDiff > 0n) {
      // Need to add USDC
      console.log(`   Adding ${Number(usdcDiff) / 1e6} USDC to pool...`);
      const transferTx = await owner.writeContract({
        address: addresses.USDC,
        abi: erc20Abi,
        functionName: "transfer",
        args: [pairWBTCUSDC.address, usdcDiff],
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: transferTx });
    } else if (usdcDiff < 0n) {
      // Need to reduce USDC - we'll skim the excess
      console.log(`   Removing ${Number(-usdcDiff) / 1e6} USDC from pool via skim...`);
    }

    // Set reserves to match target
    const newReserve0 = isWbtcToken0 ? wbtcReserve : targetUsdcReserve;
    const newReserve1 = isWbtcToken0 ? targetUsdcReserve : wbtcReserve;

    const setReservesTx = await pairWBTCUSDC.write.setReserves(
      [newReserve0, newReserve1],
      { account: owner.account }
    );
    await publicClient.waitForTransactionReceipt({ hash: setReservesTx });
    console.log("   ✓ Reserves updated");

    // Verify new price
    const [newR0, newR1] = await publicClient.readContract({
      address: pairWBTCUSDC.address,
      abi: pairAbi,
      functionName: "getReserves",
    });
    const newWbtcReserve = isWbtcToken0 ? newR0 : newR1;
    const newUsdcReserve = isWbtcToken0 ? newR1 : newR0;
    const newPoolPrice = (Number(newUsdcReserve) / 1e6) / (Number(newWbtcReserve) / 1e8);
    console.log(`   New pool price: $${newPoolPrice.toLocaleString()}`);
  }

  // =========================================================================
  // 5) Take TWAP observation
  // =========================================================================
  console.log("\n=> Taking TWAP observation...");
  try {
    const updateTx = await twapOracle.write.update([pairWBTCUSDC.address], { account: owner.account });
    await publicClient.waitForTransactionReceipt({ hash: updateTx });
    console.log("   ✓ TWAP observation recorded");
  } catch (err) {
    console.log(`   ⚠ TWAP update: ${err.message?.slice(0, 80) || err}`);
  }

  // =========================================================================
  // Done
  // =========================================================================
  console.log("\n" + "=".repeat(60));
  console.log("  ✅ Price sync complete!");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
