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

  const connection = await hre.network.connect();
  const { viem } = connection;
  const wallets = await viem.getWalletClients();
  const [owner] = wallets;

  const rpcUrl = hre.network.config?.url || process.env.SEPOLIA_RPC_URL;
  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(rpcUrl, { timeout: 60000 }),
  });

  console.log("=== Fix TWAP Observations ===\n");

  const loadAbi = (relPath) =>
    JSON.parse(fs.readFileSync(path.join(process.cwd(), "artifacts", relPath), "utf8")).abi;

  const pairAbi = loadAbi("contracts/local/UniswapV2Pair.sol/UniswapV2Pair.json");
  const twapOracleAbi = loadAbi("contracts/UniswapV2TWAPOracle.sol/UniswapV2TWAPOracle.json");

  const pairs = [
    { name: "WBTC/USDC", addr: addresses.PairWBTCUSDC },
    { name: "BTD/USDC", addr: addresses.PairBTDUSDC },
    { name: "BTB/BTD", addr: addresses.PairBTBBTD },
    { name: "BRS/BTD", addr: addresses.PairBRSBTD },
  ];

  // Step 1: Call sync on all pairs to update cumulative prices
  console.log("Step 1: Syncing pairs...");
  for (const pair of pairs) {
    try {
      const tx = await owner.writeContract({
        address: pair.addr,
        abi: pairAbi,
        functionName: "sync",
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash: tx });
      console.log("  OK", pair.name, "synced");
    } catch (e) {
      console.log("  FAIL", pair.name, e.message?.slice(0, 50));
    }
  }

  // Step 2: Check current cumulative prices
  console.log("\nStep 2: Current cumulative prices...");
  for (const pair of pairs) {
    const p0 = await publicClient.readContract({
      address: pair.addr,
      abi: pairAbi,
      functionName: "price0CumulativeLast",
    });
    const p1 = await publicClient.readContract({
      address: pair.addr,
      abi: pairAbi,
      functionName: "price1CumulativeLast",
    });
    console.log("  ", pair.name, "p0=", p0.toString().slice(0,15), "p1=", p1.toString().slice(0,15));
  }

  // Step 3: Update TWAP observations
  console.log("\nStep 3: Taking fresh TWAP observations...");
  const twapOracle = await viem.getContractAt(
    "contracts/UniswapV2TWAPOracle.sol:UniswapV2TWAPOracle",
    addresses.TWAPOracle
  );

  for (const pair of pairs) {
    try {
      const tx = await twapOracle.write.update([pair.addr], { account: owner.account });
      await publicClient.waitForTransactionReceipt({ hash: tx });
      console.log("  OK", pair.name, "TWAP updated");
    } catch (e) {
      console.log("  FAIL", pair.name, e.message?.slice(0, 50));
    }
  }

  // Step 4: Check observations
  console.log("\nStep 4: Current observations...");
  for (const pair of pairs) {
    const obs0 = await publicClient.readContract({
      address: addresses.TWAPOracle,
      abi: twapOracleAbi,
      functionName: "pairObservations",
      args: [pair.addr, 0],
    });
    const obs1 = await publicClient.readContract({
      address: addresses.TWAPOracle,
      abi: twapOracleAbi,
      functionName: "pairObservations",
      args: [pair.addr, 1],
    });
    console.log("  ", pair.name);
    console.log("    Obs0: ts=", obs0[0], "p0=", obs0[1].toString().slice(0,20));
    console.log("    Obs1: ts=", obs1[0], "p0=", obs1[1].toString().slice(0,20));

    // Check if obs1 > obs0 (correct order)
    if (obs1[1] > obs0[1]) {
      console.log("    Status: CORRECT (obs1 > obs0)");
    } else {
      console.log("    Status: WRONG (obs1 <= obs0) - needs re-init");
    }
  }

  console.log("\n=== Done ===");
  console.log("Wait 30 minutes and run again to take second observation.");
}

main().catch(console.error);
