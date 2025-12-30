/**
 * WBTC Price Sync Daemon for Sepolia
 *
 * Monitors and syncs Uniswap WBTC/USDC pool price with Chainlink BTC/USD oracle.
 * Runs as a background daemon, checking prices periodically.
 *
 * Features:
 * - Continuous monitoring with configurable interval
 * - Auto-rebalancing when deviation exceeds threshold
 * - TWAP observation after each sync
 * - Graceful shutdown on SIGINT/SIGTERM
 *
 * Run modes:
 *   Daemon (default):  npx hardhat run scripts/sepolia/price-sync.mjs --network sepolia
 *   Single run:        SINGLE_RUN=1 npx hardhat run scripts/sepolia/price-sync.mjs --network sepolia
 *
 * Environment variables:
 *   SYNC_INTERVAL      - Check interval in seconds (default: 300 = 5 minutes)
 *   DEVIATION_THRESHOLD - Price deviation % to trigger sync (default: 1.0)
 *   SINGLE_RUN         - Run once and exit (default: false)
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

// Official Uniswap V2 on Sepolia
const UNISWAP_V2 = {
  FACTORY: "0xF62c03E08ada871A0bEb309762E260a7a6a880E6",
  ROUTER: "0xeE567Fe1712Faf6149d80dA1E6934E354124CfE3",
};

// Configuration (can be overridden by environment variables)
const CONFIG = {
  SYNC_INTERVAL: parseInt(process.env.SYNC_INTERVAL || "300", 10), // 5 minutes
  DEVIATION_THRESHOLD: parseFloat(process.env.DEVIATION_THRESHOLD || "1.0"), // 1%
  SINGLE_RUN: process.env.SINGLE_RUN === "1" || process.env.SINGLE_RUN === "true",
};

const ROUTER_ABI = [
  {
    inputs: [
      { name: "tokenA", type: "address" },
      { name: "tokenB", type: "address" },
      { name: "amountADesired", type: "uint256" },
      { name: "amountBDesired", type: "uint256" },
      { name: "amountAMin", type: "uint256" },
      { name: "amountBMin", type: "uint256" },
      { name: "to", type: "address" },
      { name: "deadline", type: "uint256" },
    ],
    name: "addLiquidity",
    outputs: [
      { name: "amountA", type: "uint256" },
      { name: "amountB", type: "uint256" },
      { name: "liquidity", type: "uint256" },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [
      { name: "tokenA", type: "address" },
      { name: "tokenB", type: "address" },
      { name: "liquidity", type: "uint256" },
      { name: "amountAMin", type: "uint256" },
      { name: "amountBMin", type: "uint256" },
      { name: "to", type: "address" },
      { name: "deadline", type: "uint256" },
    ],
    name: "removeLiquidity",
    outputs: [
      { name: "amountA", type: "uint256" },
      { name: "amountB", type: "uint256" },
    ],
    stateMutability: "nonpayable",
    type: "function",
  },
];

const PAIR_ABI = [
  {
    inputs: [],
    name: "getReserves",
    outputs: [
      { name: "reserve0", type: "uint112" },
      { name: "reserve1", type: "uint112" },
      { name: "blockTimestampLast", type: "uint32" },
    ],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
  {
    inputs: [],
    name: "token0",
    outputs: [{ name: "", type: "address" }],
    stateMutability: "view",
    type: "function",
  },
];

const ERC20_ABI = [
  {
    inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }],
    name: "approve",
    outputs: [{ name: "", type: "bool" }],
    stateMutability: "nonpayable",
    type: "function",
  },
  {
    inputs: [{ name: "account", type: "address" }],
    name: "balanceOf",
    outputs: [{ name: "", type: "uint256" }],
    stateMutability: "view",
    type: "function",
  },
];

const CHAINLINK_ABI = [
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

const CONFIG_CORE_ABI = [
  { inputs: [], name: "POOL_WBTC_USDC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "WBTC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "USDC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
];

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

function timestamp() {
  return new Date().toISOString().replace("T", " ").slice(0, 19);
}

function log(msg) {
  console.log(`[${timestamp()}] ${msg}`);
}

// Global state for graceful shutdown
let isRunning = true;
let currentTimeout = null;

async function checkAndSync(context) {
  const { publicClient, owner, addresses, twapOracle } = context;
  const { pairAddress, wbtcAddress, usdcAddress, isWbtcToken0 } = context.pool;

  const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

  try {
    // 1) Read Chainlink BTC/USD price
    const [, btcPrice] = await publicClient.readContract({
      address: addresses.ChainlinkBTCUSD,
      abi: CHAINLINK_ABI,
      functionName: "latestRoundData",
    });
    const btcPriceUsd = Number(btcPrice) / 1e8;

    // 2) Read current pool reserves
    const [reserve0, reserve1] = await publicClient.readContract({
      address: pairAddress,
      abi: PAIR_ABI,
      functionName: "getReserves",
    });

    const wbtcReserve = isWbtcToken0 ? reserve0 : reserve1;
    const usdcReserve = isWbtcToken0 ? reserve1 : reserve0;

    if (wbtcReserve === 0n) {
      log(`⚠ Pool has no WBTC reserves`);
      return;
    }

    const currentPoolPrice = (Number(usdcReserve) / 1e6) / (Number(wbtcReserve) / 1e8);
    const priceDiff = Math.abs(currentPoolPrice - btcPriceUsd) / btcPriceUsd * 100;

    log(`Chainlink: $${btcPriceUsd.toLocaleString()} | Pool: $${currentPoolPrice.toLocaleString()} | Deviation: ${priceDiff.toFixed(2)}%`);

    if (priceDiff < CONFIG.DEVIATION_THRESHOLD) {
      log(`✓ Price within ${CONFIG.DEVIATION_THRESHOLD}% tolerance`);
      return;
    }

    // 3) Rebalance needed
    log(`⚡ Rebalancing (deviation ${priceDiff.toFixed(2)}% > ${CONFIG.DEVIATION_THRESHOLD}%)...`);

    const lpBalance = await publicClient.readContract({
      address: pairAddress,
      abi: PAIR_ABI,
      functionName: "balanceOf",
      args: [owner.account.address],
    });

    if (lpBalance === 0n) {
      log(`⚠ No LP tokens to rebalance`);
      return;
    }

    // Approve LP tokens
    const approveLpTx = await owner.writeContract({
      address: pairAddress,
      abi: ERC20_ABI,
      functionName: "approve",
      args: [UNISWAP_V2.ROUTER, lpBalance],
      account: owner.account,
    });
    await publicClient.waitForTransactionReceipt({ hash: approveLpTx });

    // Remove liquidity
    const removeTx = await owner.writeContract({
      address: UNISWAP_V2.ROUTER,
      abi: ROUTER_ABI,
      functionName: "removeLiquidity",
      args: [wbtcAddress, usdcAddress, lpBalance, 0n, 0n, owner.account.address, deadline],
      account: owner.account,
    });
    await publicClient.waitForTransactionReceipt({ hash: removeTx });

    // Get token balances
    const wbtcBal = await publicClient.readContract({
      address: wbtcAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [owner.account.address],
    });
    const usdcBal = await publicClient.readContract({
      address: usdcAddress,
      abi: ERC20_ABI,
      functionName: "balanceOf",
      args: [owner.account.address],
    });

    // Calculate correct amounts
    const wbtcToUse = wbtcBal;
    const usdcNeeded = BigInt(Math.floor((Number(wbtcToUse) / 1e8) * btcPriceUsd * 1e6));

    let finalWbtc = wbtcToUse;
    let finalUsdc = usdcNeeded <= usdcBal ? usdcNeeded : usdcBal;

    if (usdcNeeded > usdcBal) {
      finalUsdc = usdcBal;
      finalWbtc = BigInt(Math.floor((Number(usdcBal) / 1e6 / btcPriceUsd) * 1e8));
      if (finalWbtc > wbtcBal) finalWbtc = wbtcBal;
    }

    if (finalWbtc > 0n && finalUsdc > 0n) {
      // Approve tokens
      const approveTxA = await owner.writeContract({
        address: wbtcAddress,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [UNISWAP_V2.ROUTER, finalWbtc],
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: approveTxA });

      const approveTxB = await owner.writeContract({
        address: usdcAddress,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [UNISWAP_V2.ROUTER, finalUsdc],
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: approveTxB });

      // Add liquidity
      const addLiqTx = await owner.writeContract({
        address: UNISWAP_V2.ROUTER,
        abi: ROUTER_ABI,
        functionName: "addLiquidity",
        args: [wbtcAddress, usdcAddress, finalWbtc, finalUsdc, 0n, 0n, owner.account.address, deadline],
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: addLiqTx });

      // Verify
      const [newR0, newR1] = await publicClient.readContract({
        address: pairAddress,
        abi: PAIR_ABI,
        functionName: "getReserves",
      });
      const newWbtcReserve = isWbtcToken0 ? newR0 : newR1;
      const newUsdcReserve = isWbtcToken0 ? newR1 : newR0;
      const newPoolPrice = (Number(newUsdcReserve) / 1e6) / (Number(newWbtcReserve) / 1e8);
      const newDeviation = Math.abs(newPoolPrice - btcPriceUsd) / btcPriceUsd * 100;

      log(`✓ Rebalanced: $${newPoolPrice.toLocaleString()} (deviation: ${newDeviation.toFixed(2)}%)`);
    }

    // 4) Take TWAP observation (only if >= 30 min since last update)
    try {
      const updateTx = await twapOracle.write.updateIfNeeded([pairAddress], { account: owner.account });
      await publicClient.waitForTransactionReceipt({ hash: updateTx });
      log(`✓ TWAP observation recorded`);
    } catch (err) {
      log(`⚠ TWAP update failed: ${err.message?.slice(0, 60) || err}`);
    }

  } catch (err) {
    log(`❌ Error: ${err.message || err}`);
  }
}

function sleep(ms) {
  return new Promise((resolve) => {
    currentTimeout = setTimeout(resolve, ms);
  });
}

async function main() {
  console.log("=".repeat(60));
  console.log("  WBTC Price Sync Daemon - Sepolia");
  console.log("=".repeat(60));
  console.log(`  Mode: ${CONFIG.SINGLE_RUN ? "Single run" : "Daemon"}`);
  console.log(`  Check interval: ${CONFIG.SYNC_INTERVAL} seconds`);
  console.log(`  Deviation threshold: ${CONFIG.DEVIATION_THRESHOLD}%`);
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

  log(`Syncing as: ${owner.account.address}`);

  const get = (key, abiName = key) => viem.getContractAt(abiName, addresses[key]);
  const twapOracle = await get("TWAPOracle", "contracts/UniswapV2TWAPOracle.sol:UniswapV2TWAPOracle");

  // Read pool addresses from ConfigCore (the actual addresses used by PriceOracle)
  log("Reading pool addresses from ConfigCore...");
  const pairAddress = await publicClient.readContract({
    address: addresses.ConfigCore,
    abi: CONFIG_CORE_ABI,
    functionName: "POOL_WBTC_USDC",
  });
  const wbtcAddress = await publicClient.readContract({
    address: addresses.ConfigCore,
    abi: CONFIG_CORE_ABI,
    functionName: "WBTC",
  });
  const usdcAddress = await publicClient.readContract({
    address: addresses.ConfigCore,
    abi: CONFIG_CORE_ABI,
    functionName: "USDC",
  });
  log(`Pool: ${pairAddress}`);

  // Determine token order
  const token0 = await publicClient.readContract({
    address: pairAddress,
    abi: PAIR_ABI,
    functionName: "token0",
  });
  const isWbtcToken0 = token0.toLowerCase() === wbtcAddress.toLowerCase();

  const context = {
    publicClient,
    owner,
    addresses,
    twapOracle,
    pool: {
      pairAddress,
      wbtcAddress,
      usdcAddress,
      isWbtcToken0,
    },
  };

  // Graceful shutdown
  const shutdown = () => {
    log("Shutting down...");
    isRunning = false;
    if (currentTimeout) {
      clearTimeout(currentTimeout);
    }
    process.exit(0);
  };
  process.on("SIGINT", shutdown);
  process.on("SIGTERM", shutdown);

  // Main loop
  if (CONFIG.SINGLE_RUN) {
    await checkAndSync(context);
    log("Single run complete.");
  } else {
    log("Starting daemon loop...");
    while (isRunning) {
      await checkAndSync(context);
      if (isRunning) {
        log(`Next check in ${CONFIG.SYNC_INTERVAL} seconds...`);
        await sleep(CONFIG.SYNC_INTERVAL * 1000);
      }
    }
  }
}

main().catch((err) => {
  console.error(`[${timestamp()}] Fatal error:`, err);
  process.exit(1);
});
