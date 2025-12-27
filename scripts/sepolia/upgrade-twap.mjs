/**
 * Deploy new TWAPOracle and update PriceOracle
 *
 * Run: npx hardhat run scripts/sepolia/upgrade-twap.mjs --network sepolia
 */

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

  console.log("=== Upgrade TWAPOracle ===\n");
  console.log("Deployer:", owner.account.address);
  console.log("Old TWAPOracle:", addresses.TWAPOracle);

  // Step 1: Deploy new TWAPOracle
  console.log("\nStep 1: Deploying new TWAPOracle...");
  const newTwapOracle = await viem.deployContract("contracts/UniswapV2TWAPOracle.sol:UniswapV2TWAPOracle");
  console.log("New TWAPOracle:", newTwapOracle.address);

  // Step 2: Update PriceOracle to use new TWAPOracle
  console.log("\nStep 2: Updating PriceOracle...");
  const priceOracle = await viem.getContractAt(
    "contracts/PriceOracle.sol:PriceOracle",
    addresses.PriceOracle
  );

  const tx = await priceOracle.write.setTWAPOracle([newTwapOracle.address], { account: owner.account });
  await publicClient.waitForTransactionReceipt({ hash: tx });
  console.log("PriceOracle updated to use new TWAPOracle");

  // Step 3: Initialize TWAP observations
  console.log("\nStep 3: Taking first TWAP observations...");
  const pairs = [
    { name: "WBTC/USDC", addr: addresses.PairWBTCUSDC },
    { name: "BTD/USDC", addr: addresses.PairBTDUSDC },
    { name: "BTB/BTD", addr: addresses.PairBTBBTD },
    { name: "BRS/BTD", addr: addresses.PairBRSBTD },
  ];

  for (const pair of pairs) {
    try {
      const updateTx = await newTwapOracle.write.update([pair.addr], { account: owner.account });
      await publicClient.waitForTransactionReceipt({ hash: updateTx });
      console.log("  OK", pair.name);
    } catch (e) {
      console.log("  FAIL", pair.name, e.message?.slice(0, 50));
    }
  }

  // Step 4: Update deployed_addresses.json
  console.log("\nStep 4: Updating deployed_addresses.json...");
  raw["FullSystemSepolia#TWAPOracle"] = newTwapOracle.address;
  fs.writeFileSync(ADDR_FILE, JSON.stringify(raw, null, 2));
  console.log("Updated");

  console.log("\n=== Done ===");
  console.log("New TWAPOracle:", newTwapOracle.address);
  console.log("\nNOTE: Wait 30 minutes, then run:");
  console.log("  npm run sepolia:enable-twap");
  console.log("  npm run sepolia:init-farm");
}

main().catch(console.error);
