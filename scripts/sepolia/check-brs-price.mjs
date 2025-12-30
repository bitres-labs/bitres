import { createPublicClient, http } from "viem";
import { sepolia } from "viem/chains";
import fs from "fs";

const addresses = JSON.parse(fs.readFileSync("./ignition/deployments/chain-11155111/deployed_addresses.json", "utf8"));

const publicClient = createPublicClient({
  chain: sepolia,
  transport: http(process.env.SEPOLIA_RPC_URL),
});

const priceOracleAbi = [
  { inputs: [], name: "getBRSPrice", outputs: [{ type: "uint256" }], stateMutability: "view", type: "function" },
];

async function main() {
  try {
    const brsPrice = await publicClient.readContract({
      address: addresses["FullSystemSepolia#PriceOracle"],
      abi: priceOracleAbi,
      functionName: "getBRSPrice",
    });
    console.log("BRS Price:", brsPrice);
  } catch (err) {
    console.log("Full error:", err.message);
    if (err.cause) {
      console.log("Cause:", err.cause.reason || err.cause);
    }
  }
}

main();
