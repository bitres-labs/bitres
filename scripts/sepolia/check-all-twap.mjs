import { createPublicClient, http } from "viem";
import { sepolia } from "viem/chains";
import fs from "fs";

const addresses = JSON.parse(fs.readFileSync("./ignition/deployments/chain-11155111/deployed_addresses.json", "utf8"));

const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(process.env.SEPOLIA_RPC_URL),
});

const twapAbi = [
  { inputs: [{ name: "pair", type: "address" }], name: "isTWAPReady", outputs: [{ type: "bool" }], stateMutability: "view", type: "function" },
  { inputs: [{ name: "pair", type: "address" }], name: "getObservationInfo", outputs: [{ type: "uint32" }, { type: "uint32" }, { type: "uint32" }], stateMutability: "view", type: "function" },
];

const configCoreAbi = [
  { inputs: [], name: "POOL_WBTC_USDC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "POOL_BTD_USDC", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "POOL_BTB_BTD", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
  { inputs: [], name: "POOL_BRS_BTD", outputs: [{ type: "address" }], stateMutability: "view", type: "function" },
];

async function main() {
  const configCore = addresses["FullSystemSepolia#ConfigCore"];
  const twapOracle = addresses["FullSystemSepolia#TWAPOracle"];
  const now = Math.floor(Date.now() / 1000);

  console.log("Current timestamp:", now);
  console.log("");

  for (const poolName of ["POOL_WBTC_USDC", "POOL_BTD_USDC", "POOL_BTB_BTD", "POOL_BRS_BTD"]) {
    const poolAddr = await publicClient.readContract({
      address: configCore,
      abi: configCoreAbi,
      functionName: poolName,
    });

    const isReady = await publicClient.readContract({
      address: twapOracle,
      abi: twapAbi,
      functionName: "isTWAPReady",
      args: [poolAddr],
    });

    const [olderTs, newerTs, elapsed] = await publicClient.readContract({
      address: twapOracle,
      abi: twapAbi,
      functionName: "getObservationInfo",
      args: [poolAddr],
    });

    const olderAge = now - Number(olderTs);
    const newerAge = now - Number(newerTs);

    console.log(poolName + ":");
    console.log("  Ready: " + isReady);
    console.log("  Older: timestamp=" + olderTs + ", age=" + Math.floor(olderAge/60) + " min");
    console.log("  Newer: timestamp=" + newerTs + ", age=" + Math.floor(newerAge/60) + " min");
    console.log("");
  }
}

main();
