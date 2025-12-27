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

  const priceOracleAbi = loadAbi("contracts/PriceOracle.sol/PriceOracle.json");

  console.log("=== Debug PriceOracle ===\n");

  // Check useTWAP
  const useTWAP = await publicClient.readContract({
    address: addresses.PriceOracle,
    abi: priceOracleAbi,
    functionName: "useTWAP",
  });
  console.log("useTWAP:", useTWAP);

  // Try spot price directly
  console.log("\n=== getPrice (spot) ===");
  try {
    const price = await publicClient.readContract({
      address: addresses.PriceOracle,
      abi: priceOracleAbi,
      functionName: "getPrice",
      args: [addresses.PairWBTCUSDC, addresses.WBTC, addresses.USDC],
    });
    console.log("getPrice(WBTC->USDC):", price.toString());
    console.log("As USD:", Number(price) / 1e18);
  } catch (e) {
    console.log("Error:", e.message?.slice(0, 300));
  }

  // Try getWBTCPrice
  console.log("\n=== getWBTCPrice ===");
  try {
    const price = await publicClient.readContract({
      address: addresses.PriceOracle,
      abi: priceOracleAbi,
      functionName: "getWBTCPrice",
    });
    console.log("getWBTCPrice:", price.toString());
  } catch (e) {
    console.log("Error:", e.message?.slice(0, 400));
  }

  // Check chainlink price
  console.log("\n=== Chainlink prices ===");
  const chainlinkAbi = [{
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
  }];

  const [, btcPrice] = await publicClient.readContract({
    address: addresses.ChainlinkBTCUSD,
    abi: chainlinkAbi,
    functionName: "latestRoundData",
  });
  console.log("Chainlink BTC/USD:", Number(btcPrice) / 1e8);
}

main().catch(console.error);
