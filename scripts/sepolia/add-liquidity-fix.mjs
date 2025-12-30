/**
 * Add liquidity to fix pool price
 */
import fs from "fs";
import path from "path";
import hre from "hardhat";

const ADDR_FILE = path.join(process.cwd(), "ignition/deployments/chain-11155111/deployed_addresses.json");

const CONFIG_CORE_ABI = [
  { inputs: [], name: "POOL_WBTC_USDC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "WBTC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "USDC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
];

const CHAINLINK_ABI = [
  { inputs: [], name: "latestRoundData", outputs: [{ name: "roundId", type: "uint80" }, { name: "answer", type: "int256" }, { name: "startedAt", type: "uint256" }, { name: "updatedAt", type: "uint256" }, { name: "answeredInRound", type: "uint80" }], stateMutability: "view", type: "function" },
];

const ERC20_ABI = [
  { inputs: [{ name: "to", type: "address" }, { name: "amount", type: "uint256" }], name: "mint", outputs: [], stateMutability: "nonpayable", type: "function" },
  { inputs: [{ name: "spender", type: "address" }, { name: "amount", type: "uint256" }], name: "approve", outputs: [{ type: "bool" }], stateMutability: "nonpayable", type: "function" },
];

const ROUTER_ABI = [
  { inputs: [{ name: "tokenA", type: "address" }, { name: "tokenB", type: "address" }, { name: "amountADesired", type: "uint256" }, { name: "amountBDesired", type: "uint256" }, { name: "amountAMin", type: "uint256" }, { name: "amountBMin", type: "uint256" }, { name: "to", type: "address" }, { name: "deadline", type: "uint256" }], name: "addLiquidity", outputs: [{ name: "amountA", type: "uint256" }, { name: "amountB", type: "uint256" }, { name: "liquidity", type: "uint256" }], stateMutability: "nonpayable", type: "function" },
  { inputs: [{ name: "amountIn", type: "uint256" }, { name: "amountOutMin", type: "uint256" }, { name: "path", type: "address[]" }, { name: "to", type: "address" }, { name: "deadline", type: "uint256" }], name: "swapExactTokensForTokens", outputs: [{ name: "amounts", type: "uint256[]" }], stateMutability: "nonpayable", type: "function" },
];

const PAIR_ABI = [
  { inputs: [], name: "getReserves", outputs: [{ name: "reserve0", type: "uint112" }, { name: "reserve1", type: "uint112" }, { name: "blockTimestampLast", type: "uint32" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "token0", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "sync", outputs: [], stateMutability: "nonpayable", type: "function" },
];

const ERC20_TRANSFER_ABI = [
  { inputs: [{ name: "to", type: "address" }, { name: "amount", type: "uint256" }], name: "transfer", outputs: [{ type: "bool" }], stateMutability: "nonpayable", type: "function" },
];

async function main() {
  console.log("\n=== Add Liquidity to Fix Pool Price ===\n");

  const raw = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  const addr = {};
  for (const [k, v] of Object.entries(raw)) {
    addr[k.replace("FullSystemSepolia#", "")] = v;
  }

  const { viem } = await hre.network.connect();
  const [owner] = await viem.getWalletClients();
  const publicClient = await viem.getPublicClient();

  // Get addresses from ConfigCore
  const pool = await publicClient.readContract({ address: addr.ConfigCore, abi: CONFIG_CORE_ABI, functionName: "POOL_WBTC_USDC" });
  const wbtc = await publicClient.readContract({ address: addr.ConfigCore, abi: CONFIG_CORE_ABI, functionName: "WBTC" });
  const usdc = await publicClient.readContract({ address: addr.ConfigCore, abi: CONFIG_CORE_ABI, functionName: "USDC" });

  console.log("Pool: " + pool);
  console.log("WBTC: " + wbtc);
  console.log("USDC: " + usdc);

  // Get Chainlink price
  const [, answer] = await publicClient.readContract({ address: addr.ChainlinkBTCUSD, abi: CHAINLINK_ABI, functionName: "latestRoundData" });
  const btcPrice = Number(answer) / 1e8;
  console.log("\nChainlink BTC: $" + btcPrice.toLocaleString());

  // Get current reserves
  const [r0, r1] = await publicClient.readContract({ address: pool, abi: PAIR_ABI, functionName: "getReserves" });
  const token0 = await publicClient.readContract({ address: pool, abi: PAIR_ABI, functionName: "token0" });
  const isWbtcToken0 = token0.toLowerCase() === wbtc.toLowerCase();
  const wbtcRes = isWbtcToken0 ? r0 : r1;
  const usdcRes = isWbtcToken0 ? r1 : r0;
  const currentPrice = (Number(usdcRes) / 1e6) / (Number(wbtcRes) / 1e8);
  console.log("Current pool: $" + currentPrice.toLocaleString() + " (WBTC: " + wbtcRes + ", USDC: " + usdcRes + ")");

  // Calculate USDC to add to reach target price
  // By donating USDC (without taking WBTC), we increase the price
  // Target price = targetUsdcRes / wbtcRes * 100 = btcPrice
  // targetUsdcRes = btcPrice * wbtcRes / 100
  const targetUsdcRes = btcPrice * Number(wbtcRes) / 100;
  const usdcToAdd = BigInt(Math.ceil(targetUsdcRes - Number(usdcRes)));

  console.log("\nTarget USDC reserve: " + (targetUsdcRes/1e6).toFixed(6) + " USDC");
  console.log("Current USDC reserve: " + (Number(usdcRes)/1e6).toFixed(6) + " USDC");
  console.log("Donating " + (Number(usdcToAdd)/1e6).toFixed(6) + " USDC to pool...");

  if (usdcToAdd <= 0n) {
    console.log("No adjustment needed");
    return;
  }

  // Transfer USDC directly to the pool
  let tx = await owner.writeContract({
    address: usdc,
    abi: ERC20_TRANSFER_ABI,
    functionName: "transfer",
    args: [pool, usdcToAdd]
  });
  await publicClient.waitForTransactionReceipt({ hash: tx });
  console.log("Transfer done, calling sync...");

  // Sync the pool to update reserves
  tx = await owner.writeContract({
    address: pool,
    abi: PAIR_ABI,
    functionName: "sync",
  });
  await publicClient.waitForTransactionReceipt({ hash: tx });
  console.log("Sync done");

  // Check new price
  const [newR0, newR1] = await publicClient.readContract({ address: pool, abi: PAIR_ABI, functionName: "getReserves" });
  const finalWbtcRes = isWbtcToken0 ? newR0 : newR1;
  const finalUsdcRes = isWbtcToken0 ? newR1 : newR0;
  const newPrice = (Number(finalUsdcRes) / 1e6) / (Number(finalWbtcRes) / 1e8);
  const deviation = Math.abs(newPrice - btcPrice) / btcPrice * 100;

  console.log("\nNew pool: $" + newPrice.toLocaleString() + " (deviation: " + deviation.toFixed(2) + "%)");
  console.log(deviation < 1 ? "Done!" : "Run again to add more liquidity");
}

main().catch(console.error);
