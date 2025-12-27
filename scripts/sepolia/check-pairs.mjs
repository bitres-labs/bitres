/**
 * Check LP pair status on Sepolia
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";
import { createPublicClient, http, formatUnits } from "viem";
import { sepolia } from "viem/chains";

const CHAIN_ID = 11155111;
const ADDR_FILE = path.join(
  process.cwd(),
  `ignition/deployments/chain-${CHAIN_ID}/deployed_addresses.json`
);

function loadAddresses() {
  const raw = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  const map = {};
  for (const [k, v] of Object.entries(raw)) {
    map[k.replace("FullSystemSepolia#", "")] = v;
  }
  return map;
}

async function main() {
  const addresses = loadAddresses();
  const rpcUrl = hre.network.config?.url || process.env.SEPOLIA_RPC_URL;

  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(rpcUrl, { timeout: 60000 }),
  });

  const pairAbi = [
    { inputs: [], name: "totalSupply", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "getReserves", outputs: [{ name: "reserve0", type: "uint112" }, { name: "reserve1", type: "uint112" }, { name: "blockTimestampLast", type: "uint32" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "token0", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
    { inputs: [], name: "token1", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  ];

  const erc20Abi = [
    { inputs: [{ name: "account", type: "address" }], name: "balanceOf", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
  ];

  const pairs = [
    { name: "WBTC/USDC", address: addresses.PairWBTCUSDC },
    { name: "BTD/USDC", address: addresses.PairBTDUSDC },
    { name: "BTB/BTD", address: addresses.PairBTBBTD },
    { name: "BRS/BTD", address: addresses.PairBRSBTD },
  ];

  console.log("=".repeat(60));
  console.log("  LP Pair Status on Sepolia");
  console.log("=".repeat(60));

  for (const pair of pairs) {
    console.log(`\n${pair.name} (${pair.address}):`);

    const [totalSupply, reserves, token0, token1] = await Promise.all([
      publicClient.readContract({ address: pair.address, abi: pairAbi, functionName: "totalSupply" }),
      publicClient.readContract({ address: pair.address, abi: pairAbi, functionName: "getReserves" }),
      publicClient.readContract({ address: pair.address, abi: pairAbi, functionName: "token0" }),
      publicClient.readContract({ address: pair.address, abi: pairAbi, functionName: "token1" }),
    ]);

    const [bal0, bal1] = await Promise.all([
      publicClient.readContract({ address: token0, abi: erc20Abi, functionName: "balanceOf", args: [pair.address] }),
      publicClient.readContract({ address: token1, abi: erc20Abi, functionName: "balanceOf", args: [pair.address] }),
    ]);

    console.log(`  Total Supply: ${totalSupply}`);
    console.log(`  Reserves: [${reserves[0]}, ${reserves[1]}]`);
    console.log(`  Token0 balance: ${bal0}`);
    console.log(`  Token1 balance: ${bal1}`);
    console.log(`  Stuck tokens: ${bal0 - reserves[0]}, ${bal1 - reserves[1]}`);
  }
}

main().catch(console.error);
