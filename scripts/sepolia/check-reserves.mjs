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

  const pairs = [
    { name: "WBTC/USDC", addr: addresses.PairWBTCUSDC },
    { name: "BTD/USDC", addr: addresses.PairBTDUSDC },
    { name: "BTB/BTD", addr: addresses.PairBTBBTD },
    { name: "BRS/BTD", addr: addresses.PairBRSBTD },
  ];

  console.log("=== Pair Reserves ===\n");
  for (const pair of pairs) {
    const [r0, r1] = await publicClient.readContract({
      address: pair.addr,
      abi: pairAbi,
      functionName: "getReserves",
    });
    const ts = await publicClient.readContract({
      address: pair.addr,
      abi: pairAbi,
      functionName: "totalSupply",
    });
    console.log(pair.name);
    console.log("  reserve0:", r0.toString());
    console.log("  reserve1:", r1.toString());
    console.log("  totalSupply (LP):", ts.toString());
    console.log();
  }
}

main().catch(console.error);
