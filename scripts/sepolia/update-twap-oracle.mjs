/**
 * Update TWAP Oracle address in PriceOracle contract
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";

const CHAIN_ID = 11155111;
const ADDR_FILE = path.join(
  process.cwd(),
  `ignition/deployments/chain-${CHAIN_ID}/deployed_addresses.json`
);

async function main() {
  const addresses = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));

  const priceOracleAddr = addresses["FullSystemSepolia#PriceOracle"];
  const twapOracleAddr = addresses["FullSystemSepolia#TWAPOracle"];

  console.log(`PriceOracle: ${priceOracleAddr}`);
  console.log(`New TWAP Oracle: ${twapOracleAddr}`);

  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();
  const [owner] = await viem.getWalletClients();

  console.log(`Owner: ${owner.account.address}`);

  // Get PriceOracle contract
  const priceOracle = await viem.getContractAt("PriceOracle", priceOracleAddr);

  // Check current TWAP Oracle (try different function names for compatibility)
  let currentTwap;
  try {
    currentTwap = await priceOracle.read.getTWAPOracleAddress();
  } catch {
    try {
      currentTwap = await priceOracle.read.twapOracle();
    } catch {
      currentTwap = "unknown";
    }
  }
  console.log(`Current TWAP Oracle: ${currentTwap}`);

  // Update TWAP Oracle
  console.log("Updating TWAP Oracle address...");
  const tx = await priceOracle.write.setTWAPOracle([twapOracleAddr], {
    account: owner.account
  });
  await publicClient.waitForTransactionReceipt({ hash: tx });

  // Verify
  let newTwap;
  try {
    newTwap = await priceOracle.read.twapOracle();
  } catch {
    newTwap = twapOracleAddr;
  }
  console.log(`Updated TWAP Oracle: ${newTwap}`);
}

main()
  .then(() => {
    console.log("Done!");
    process.exit(0);
  })
  .catch((err) => {
    console.error("Failed:", err);
    process.exit(1);
  });
