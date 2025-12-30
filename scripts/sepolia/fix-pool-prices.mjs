/**
 * Fix Pool Prices for Sepolia
 *
 * This script adjusts pool reserves to match market prices.
 * It adds liquidity at the correct ratio to bring pool price close to oracle price.
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";
import { parseUnits } from "viem";

const ADDR_FILE = path.join(process.cwd(), "ignition/deployments/chain-11155111/deployed_addresses.json");

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
    type: "function"
  }
];

const PAIR_ABI = [
  { inputs: [], name: "getReserves", outputs: [{ name: "reserve0", type: "uint112" }, { name: "reserve1", type: "uint112" }, { name: "blockTimestampLast", type: "uint32" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "token0", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "token1", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
];

const ERC20_ABI = [
  { inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], name: "approve", outputs: [{ type: "bool" }], stateMutability: "nonpayable", type: "function" },
  { inputs: [{ name: "account", type: "address" }], name: "balanceOf", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  { inputs: [{ name: "to", type: "address" }, { name: "amount", type: "uint256" }], name: "mint", outputs: [], stateMutability: "nonpayable", type: "function" },
  { inputs: [], name: "decimals", outputs: [{ type: "uint8" }], stateMutability: "view", type: "function" },
];

const ROUTER_ABI = [
  { inputs: [{ name: "tokenA", type: "address" }, { name: "tokenB", type: "address" }, { name: "amountADesired", type: "uint256" }, { name: "amountBDesired", type: "uint256" }, { name: "amountAMin", type: "uint256" }, { name: "amountBMin", type: "uint256" }, { name: "to", type: "address" }, { name: "deadline", type: "uint256" }], name: "addLiquidity", outputs: [{ name: "amountA", type: "uint256" }, { name: "amountB", type: "uint256" }, { name: "liquidity", type: "uint256" }], stateMutability: "nonpayable", type: "function" },
];

const CONFIG_CORE_ABI = [
  { inputs: [], name: "POOL_WBTC_USDC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "WBTC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "USDC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
];

async function main() {
  console.log("\n============================================================");
  console.log("  Fix Pool Prices - Match Oracle Price");
  console.log("============================================================\n");

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

  // Read pool address from ConfigCore
  const poolWbtcUsdc = await publicClient.readContract({
    address: addr.ConfigCore,
    abi: CONFIG_CORE_ABI,
    functionName: "POOL_WBTC_USDC",
  });
  const wbtc = await publicClient.readContract({
    address: addr.ConfigCore,
    abi: CONFIG_CORE_ABI,
    functionName: "WBTC",
  });
  const usdc = await publicClient.readContract({
    address: addr.ConfigCore,
    abi: CONFIG_CORE_ABI,
    functionName: "USDC",
  });

  console.log(`=> WBTC/USDC Pool: ${poolWbtcUsdc}`);
  console.log(`=> WBTC: ${wbtc}`);
  console.log(`=> USDC: ${usdc}\n`);

  // Get current reserves
  const [reserve0, reserve1] = await publicClient.readContract({
    address: poolWbtcUsdc,
    abi: PAIR_ABI,
    functionName: "getReserves",
  });

  const token0 = await publicClient.readContract({
    address: poolWbtcUsdc,
    abi: PAIR_ABI,
    functionName: "token0",
  });

  const isWbtcToken0 = token0.toLowerCase() === wbtc.toLowerCase();
  const wbtcReserve = isWbtcToken0 ? reserve0 : reserve1;
  const usdcReserve = isWbtcToken0 ? reserve1 : reserve0;

  console.log(`Current reserves:`);
  console.log(`  WBTC: ${Number(wbtcReserve) / 1e8} WBTC (${wbtcReserve} satoshis)`);
  console.log(`  USDC: ${Number(usdcReserve) / 1e6} USDC`);

  const currentPrice = (Number(usdcReserve) / 1e6) / (Number(wbtcReserve) / 1e8);
  console.log(`  Current pool price: $${currentPrice.toFixed(2)}/BTC\n`);

  // Get Chainlink BTC price
  const chainlinkAddr = addr.ChainlinkBTCUSD;
  const [, answer] = await publicClient.readContract({
    address: chainlinkAddr,
    abi: CHAINLINK_ABI,
    functionName: "latestRoundData",
  });
  const targetPrice = Number(answer) / 1e8;
  console.log(`Target price (Chainlink): $${targetPrice.toFixed(2)}/BTC\n`);

  // Calculate how much liquidity to add
  // We need to add liquidity at the target ratio to move the price
  // Adding WBTC and USDC in the ratio that matches target price

  // For simplicity, add liquidity that doubles the pool size at target price
  const wbtcToAdd = 10000n; // 0.0001 WBTC
  const usdcToAdd = BigInt(Math.floor(Number(wbtcToAdd) * targetPrice / 100)); // USDC amount at target price

  console.log(`Adding liquidity at target price:`);
  console.log(`  WBTC: ${Number(wbtcToAdd) / 1e8} WBTC`);
  console.log(`  USDC: ${Number(usdcToAdd) / 1e6} USDC\n`);

  // Mint tokens
  console.log("=> Minting tokens...");
  const wbtcMintTx = await walletClient.writeContract({
    address: wbtc,
    abi: ERC20_ABI,
    functionName: "mint",
    args: [walletClient.account.address, wbtcToAdd * 10n], // Mint extra
  });
  await publicClient.waitForTransactionReceipt({ hash: wbtcMintTx });

  const usdcMintTx = await walletClient.writeContract({
    address: usdc,
    abi: ERC20_ABI,
    functionName: "mint",
    args: [walletClient.account.address, usdcToAdd * 10n], // Mint extra
  });
  await publicClient.waitForTransactionReceipt({ hash: usdcMintTx });
  console.log("   ✓ Tokens minted\n");

  // Approve router
  console.log("=> Approving router...");
  const router = addr.UniswapV2Router;

  await walletClient.writeContract({
    address: wbtc,
    abi: ERC20_ABI,
    functionName: "approve",
    args: [router, wbtcToAdd * 10n],
  });
  await walletClient.writeContract({
    address: usdc,
    abi: ERC20_ABI,
    functionName: "approve",
    args: [router, usdcToAdd * 10n],
  });
  console.log("   ✓ Approved\n");

  // Add liquidity multiple times to shift price
  console.log("=> Adding liquidity to shift price...");
  const deadline = BigInt(Math.floor(Date.now() / 1000) + 3600);

  for (let i = 0; i < 5; i++) {
    try {
      const addLiqTx = await walletClient.writeContract({
        address: router,
        abi: ROUTER_ABI,
        functionName: "addLiquidity",
        args: [wbtc, usdc, wbtcToAdd, usdcToAdd, 0n, 0n, walletClient.account.address, deadline],
      });
      await publicClient.waitForTransactionReceipt({ hash: addLiqTx });
      console.log(`   ✓ Added liquidity batch ${i + 1}/5`);
    } catch (err) {
      console.log(`   ⚠ Batch ${i + 1} failed: ${err.message?.slice(0, 50)}`);
    }
  }

  // Check new reserves
  const [newReserve0, newReserve1] = await publicClient.readContract({
    address: poolWbtcUsdc,
    abi: PAIR_ABI,
    functionName: "getReserves",
  });

  const newWbtcReserve = isWbtcToken0 ? newReserve0 : newReserve1;
  const newUsdcReserve = isWbtcToken0 ? newReserve1 : newReserve0;

  console.log(`\nNew reserves:`);
  console.log(`  WBTC: ${Number(newWbtcReserve) / 1e8} WBTC`);
  console.log(`  USDC: ${Number(newUsdcReserve) / 1e6} USDC`);

  const newPrice = (Number(newUsdcReserve) / 1e6) / (Number(newWbtcReserve) / 1e8);
  console.log(`  New pool price: $${newPrice.toFixed(2)}/BTC`);
  console.log(`  Target price: $${targetPrice.toFixed(2)}/BTC`);

  const deviation = Math.abs(newPrice - targetPrice) / targetPrice * 100;
  console.log(`  Deviation: ${deviation.toFixed(2)}%\n`);

  if (deviation <= 1) {
    console.log("============================================================");
    console.log("  ✅ Pool price is now within 1% of target!");
    console.log("============================================================\n");
  } else {
    console.log("============================================================");
    console.log("  ⚠ Pool price still deviates more than 1%");
    console.log("  Run this script again or adjust liquidity manually");
    console.log("============================================================\n");
  }
}

main().catch((error) => {
  console.error(error);
  process.exit(1);
});
