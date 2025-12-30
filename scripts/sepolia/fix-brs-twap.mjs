/**
 * Fix BRS/BTD TWAP - Force initialize with a second observation
 * 
 * The issue: BRS/BTD only has one observation (in newer slot), older slot is empty.
 * Solution: Wait for newer to be >= 30 min old, then TWAP will be ready.
 * 
 * This script checks the current status and provides guidance.
 */

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
  { inputs: [{ name: "pair", type: "address" }], name: "updateIfNeeded", outputs: [{ type: "bool" }], stateMutability: "nonpayable", type: "function" },
];

const BRS_BTD_PAIR = addresses["FullSystemSepolia#PairBRSBTD"];
const TWAP_ORACLE = addresses["FullSystemSepolia#TWAPOracle"];
const PERIOD = 30 * 60; // 30 minutes in seconds

async function main() {
  console.log("=".repeat(60));
  console.log("  BRS/BTD TWAP Fix");
  console.log("=".repeat(60));
  
  const now = Math.floor(Date.now() / 1000);
  
  const isReady = await publicClient.readContract({
    address: TWAP_ORACLE,
    abi: twapAbi,
    functionName: "isTWAPReady",
    args: [BRS_BTD_PAIR],
  });
  
  const [olderTs, newerTs] = await publicClient.readContract({
    address: TWAP_ORACLE,
    abi: twapAbi,
    functionName: "getObservationInfo",
    args: [BRS_BTD_PAIR],
  });
  
  const newerAge = now - Number(newerTs);
  const timeRemaining = PERIOD - newerAge;
  
  console.log("\nCurrent Status:");
  console.log("  Ready:", isReady);
  console.log("  Newer observation age:", Math.floor(newerAge / 60), "min");
  console.log("  Older timestamp:", olderTs == 0 ? "NOT SET" : olderTs);
  
  if (isReady) {
    console.log("\n✓ BRS/BTD TWAP is ready!");
    return;
  }
  
  if (timeRemaining > 0) {
    console.log("\n⏳ Time until ready:", Math.ceil(timeRemaining / 60), "minutes");
    console.log("   The newer observation needs to be at least 30 min old.");
    console.log("   Please wait and run this script again.");
  } else {
    console.log("\n✓ Newer observation is old enough. TWAP should be ready.");
    console.log("   If still showing not ready, there may be another issue.");
  }
}

main().catch(console.error);
