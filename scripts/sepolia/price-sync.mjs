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

// Pyth price ID for WBTC (same as in init-sepolia.mjs)
const PYTH_WBTC_PRICE_ID = "0x505954485f575442430000000000000000000000000000000000000000000000";

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

const SWAP_ABI = [
  {
    inputs: [
      { name: "amountIn", type: "uint256" },
      { name: "amountOutMin", type: "uint256" },
      { name: "path", type: "address[]" },
      { name: "to", type: "address" },
      { name: "deadline", type: "uint256" },
    ],
    name: "swapExactTokensForTokens",
    outputs: [{ name: "amounts", type: "uint256[]" }],
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
  { inputs: [], name: "POOL_BTD_USDC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "POOL_BTB_BTD", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "POOL_BRS_BTD", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "WBTC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "USDC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
];

const MOCK_PYTH_ABI = [
  {
    inputs: [
      { name: "id", type: "bytes32" },
      { name: "price", type: "int64" },
      { name: "expo", type: "int32" },
    ],
    name: "setPrice",
    outputs: [],
    stateMutability: "nonpayable",
    type: "function",
  },
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
  const { publicClient, owner, addresses, twapOracle, mockPythAddress, allPools } = context;
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

    // 1.1) Sync MockPyth price with Chainlink
    if (mockPythAddress) {
      try {
        const setPriceTx = await owner.writeContract({
          address: mockPythAddress,
          abi: MOCK_PYTH_ABI,
          functionName: "setPrice",
          args: [PYTH_WBTC_PRICE_ID, btcPrice, -8],
          account: owner.account,
        });
        await publicClient.waitForTransactionReceipt({ hash: setPriceTx });
        log(`✓ MockPyth synced: $${btcPriceUsd.toLocaleString()}`);
      } catch (err) {
        log(`⚠ MockPyth sync failed: ${err.message?.slice(0, 60) || err}`);
      }
    }

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
      // Update TWAP for all pools
      await updateAllTWAP(twapOracle, allPools, owner, publicClient, log);
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

    // Use swap to correct the price
    // Pool price low = buy WBTC (sell USDC)
    // Pool price high = sell WBTC (buy USDC)

    // Calculate how much to swap using x*y=k formula
    // Target: newUsdcReserve / newWbtcReserve = btcPriceUsd * 1e6 / 1e8
    // Let's find the swap amount needed

    // Price = (usdcReserve / 1e6) / (wbtcReserve / 1e8) = usdcReserve * 100 / wbtcReserve
    // So: usdcReserve / wbtcReserve = price / 100
    const targetRatio = btcPriceUsd / 100;
    const currentRatio = Number(usdcReserve) / Number(wbtcReserve);

    if (currentPoolPrice < btcPriceUsd) {
      // Pool price too low -> buy WBTC with USDC
      // After swap: (usdcReserve + usdcIn) * (wbtcReserve - wbtcOut) = k
      // And: (usdcReserve + usdcIn) / (wbtcReserve - wbtcOut) = targetRatio

      // Solve for usdcIn:
      // Let k = usdcReserve * wbtcReserve
      // newUsdc = sqrt(k * targetRatio), newWbtc = sqrt(k / targetRatio)
      // usdcIn = newUsdc - usdcReserve

      const k = Number(usdcReserve) * Number(wbtcReserve);
      const newUsdcFloat = Math.sqrt(k * targetRatio);
      const usdcIn = BigInt(Math.ceil(newUsdcFloat - Number(usdcReserve)));

      if (usdcIn <= 0n) {
        log(`⚠ Calculated usdcIn <= 0, skipping`);
        return;
      }

      log(`   Swapping ${Number(usdcIn) / 1e6} USDC -> WBTC...`);

      // Approve USDC
      const approveTx = await owner.writeContract({
        address: usdcAddress,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [UNISWAP_V2.ROUTER, usdcIn],
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: approveTx });

      // Swap USDC -> WBTC
      const swapTx = await owner.writeContract({
        address: UNISWAP_V2.ROUTER,
        abi: SWAP_ABI,
        functionName: "swapExactTokensForTokens",
        args: [usdcIn, 0n, [usdcAddress, wbtcAddress], owner.account.address, deadline],
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: swapTx });

    } else {
      // Pool price too high -> sell WBTC for USDC
      const k = Number(usdcReserve) * Number(wbtcReserve);
      const newWbtcFloat = Math.sqrt(k / targetRatio);
      const wbtcIn = BigInt(Math.ceil(newWbtcFloat - Number(wbtcReserve)));

      if (wbtcIn <= 0n) {
        log(`⚠ Calculated wbtcIn <= 0, skipping`);
        return;
      }

      log(`   Swapping ${Number(wbtcIn) / 1e8} WBTC -> USDC...`);

      // Approve WBTC
      const approveTx = await owner.writeContract({
        address: wbtcAddress,
        abi: ERC20_ABI,
        functionName: "approve",
        args: [UNISWAP_V2.ROUTER, wbtcIn],
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: approveTx });

      // Swap WBTC -> USDC
      const swapTx = await owner.writeContract({
        address: UNISWAP_V2.ROUTER,
        abi: SWAP_ABI,
        functionName: "swapExactTokensForTokens",
        args: [wbtcIn, 0n, [wbtcAddress, usdcAddress], owner.account.address, deadline],
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: swapTx });
    }

    // Verify new price
    const [newR0, newR1] = await publicClient.readContract({
      address: pairAddress,
      abi: PAIR_ABI,
      functionName: "getReserves",
    });
    const newWbtcReserve = isWbtcToken0 ? newR0 : newR1;
    const newUsdcReserve = isWbtcToken0 ? newR1 : newR0;
    const newPoolPrice = (Number(newUsdcReserve) / 1e6) / (Number(newWbtcReserve) / 1e8);
    const newDeviation = Math.abs(newPoolPrice - btcPriceUsd) / btcPriceUsd * 100;

    log(`✓ Synced: $${newPoolPrice.toLocaleString()} (deviation: ${newDeviation.toFixed(2)}%)`);

    // 4) Update TWAP for all pools
    await updateAllTWAP(twapOracle, allPools, owner, publicClient, log);

  } catch (err) {
    log(`❌ Error: ${err.message || err}`);
  }
}

// Update TWAP observations for all pools
async function updateAllTWAP(twapOracle, allPools, owner, publicClient, log) {
  const poolNames = Object.keys(allPools);
  let updated = 0;

  for (const name of poolNames) {
    const poolAddr = allPools[name];
    try {
      const updateTx = await twapOracle.write.updateIfNeeded([poolAddr], { account: owner.account });
      await publicClient.waitForTransactionReceipt({ hash: updateTx });
      updated++;
    } catch (err) {
      // Silently skip if not needed (will throw if < 30 min since last update)
    }
  }

  if (updated > 0) {
    log(`✓ TWAP observations updated: ${updated}/${poolNames.length} pools`);
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

  // Read all pool addresses for TWAP updates
  const allPools = {
    WBTC_USDC: pairAddress,
    BTD_USDC: await publicClient.readContract({
      address: addresses.ConfigCore,
      abi: CONFIG_CORE_ABI,
      functionName: "POOL_BTD_USDC",
    }),
    BTB_BTD: await publicClient.readContract({
      address: addresses.ConfigCore,
      abi: CONFIG_CORE_ABI,
      functionName: "POOL_BTB_BTD",
    }),
    BRS_BTD: await publicClient.readContract({
      address: addresses.ConfigCore,
      abi: CONFIG_CORE_ABI,
      functionName: "POOL_BRS_BTD",
    }),
  };
  log(`Pool WBTC/USDC: ${pairAddress}`);

  // Determine token order
  const token0 = await publicClient.readContract({
    address: pairAddress,
    abi: PAIR_ABI,
    functionName: "token0",
  });
  const isWbtcToken0 = token0.toLowerCase() === wbtcAddress.toLowerCase();

  // Get MockPyth address
  const mockPythAddress = addresses.MockPyth;
  if (!mockPythAddress) {
    log("⚠ MockPyth address not found - Pyth sync disabled");
  } else {
    log(`MockPyth: ${mockPythAddress}`);
  }

  const context = {
    publicClient,
    owner,
    addresses,
    twapOracle,
    mockPythAddress,
    allPools,
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
