import fs from "fs";
import path from "path";
import hre from "hardhat";
import { createPublicClient, http } from "viem";
import { sepolia } from "viem/chains";

const ADDR_FILE = path.join(process.cwd(), "ignition/deployments/chain-11155111/deployed_addresses.json");

async function main() {
  const raw = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  const addresses = {};
  for (const [k, v] of Object.entries(raw)) {
    addresses[k.replace("FullSystemSepolia#", "")] = v;
  }

  const rpcUrl = hre.network.config?.url || process.env.SEPOLIA_RPC_URL;
  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(rpcUrl, { timeout: 60000 }),
  });

  const loadAbi = (relPath) =>
    JSON.parse(fs.readFileSync(path.join(process.cwd(), "artifacts", relPath), "utf8")).abi;

  const pairAbi = loadAbi("contracts/local/UniswapV2Pair.sol/UniswapV2Pair.json");
  const twapOracleAbi = loadAbi("contracts/UniswapV2TWAPOracle.sol/UniswapV2TWAPOracle.json");

  console.log("=== Pair Token Order ===");
  const token0 = await publicClient.readContract({
    address: addresses.PairWBTCUSDC,
    abi: pairAbi,
    functionName: "token0",
  });
  const token1 = await publicClient.readContract({
    address: addresses.PairWBTCUSDC,
    abi: pairAbi,
    functionName: "token1",
  });
  console.log("token0:", token0);
  console.log("token1:", token1);
  console.log("WBTC:  ", addresses.WBTC);
  console.log("USDC:  ", addresses.USDC);
  console.log("token0 is WBTC:", token0.toLowerCase() === addresses.WBTC.toLowerCase());
  console.log("token0 is USDC:", token0.toLowerCase() === addresses.USDC.toLowerCase());

  console.log("\n=== Pair Reserves ===");
  const reserves = await publicClient.readContract({
    address: addresses.PairWBTCUSDC,
    abi: pairAbi,
    functionName: "getReserves",
  });
  console.log("reserve0:", reserves[0].toString());
  console.log("reserve1:", reserves[1].toString());

  // Calculate spot price
  const r0 = Number(reserves[0]);
  const r1 = Number(reserves[1]);
  // If token0 is WBTC(8 decimals), token1 is USDC(6 decimals)
  // Price of WBTC in USDC = reserve1/reserve0 * 10^(8-6) = reserve1/reserve0 * 100
  const isWbtcToken0 = token0.toLowerCase() === addresses.WBTC.toLowerCase();
  if (isWbtcToken0) {
    const spotPrice = (r1 / r0) * 100;  // USDC per WBTC
    console.log("Spot price (USDC/WBTC):", spotPrice);
  } else {
    const spotPrice = (r0 / r1) * 100;  // USDC per WBTC
    console.log("Spot price (USDC/WBTC):", spotPrice);
  }

  console.log("\n=== TWAP getTWAPPrice ===");
  try {
    // getTWAPPrice(pair, token0Decimals, token1Decimals)
    const twapPrice = await publicClient.readContract({
      address: addresses.TWAPOracle,
      abi: twapOracleAbi,
      functionName: "getTWAPPrice",
      args: [addresses.PairWBTCUSDC, 8, 6],  // WBTC=8, USDC=6
    });
    console.log("getTWAPPrice(8,6):", twapPrice.toString());
    console.log("as decimal:", Number(twapPrice) / 1e18);
  } catch (e) {
    console.log("Error:", e.shortMessage || e.message?.slice(0, 300));
  }

  console.log("\n=== Price Cumulative Last ===");
  const price0Cum = await publicClient.readContract({
    address: addresses.PairWBTCUSDC,
    abi: pairAbi,
    functionName: "price0CumulativeLast",
  });
  const price1Cum = await publicClient.readContract({
    address: addresses.PairWBTCUSDC,
    abi: pairAbi,
    functionName: "price1CumulativeLast",
  });
  console.log("price0CumulativeLast:", price0Cum.toString());
  console.log("price1CumulativeLast:", price1Cum.toString());

  console.log("\n=== TWAP Observation Details ===");
  const obs = await publicClient.readContract({
    address: addresses.TWAPOracle,
    abi: twapOracleAbi,
    functionName: "pairObservations",
    args: [addresses.PairWBTCUSDC, 0],
  });
  console.log("Observation 0:", obs);
  const obs1 = await publicClient.readContract({
    address: addresses.TWAPOracle,
    abi: twapOracleAbi,
    functionName: "pairObservations",
    args: [addresses.PairWBTCUSDC, 1],
  });
  console.log("Observation 1:", obs1);
}

main().catch(console.error);
