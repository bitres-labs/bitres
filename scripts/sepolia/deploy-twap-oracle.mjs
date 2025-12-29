/**
 * Deploy only the TWAP Oracle contract to Sepolia
 * Updates the deployed_addresses.json with the new address
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
  console.log("Deploying new TWAP Oracle to Sepolia...");

  const { viem } = await hre.network.connect();
  const publicClient = await viem.getPublicClient();
  const [deployer] = await viem.getWalletClients();

  console.log(`Deployer: ${deployer.account.address}`);

  // Deploy new TWAP Oracle
  const twapOracle = await viem.deployContract(
    "contracts/UniswapV2TWAPOracle.sol:UniswapV2TWAPOracle",
    []
  );

  console.log(`New TWAP Oracle deployed at: ${twapOracle.address}`);

  // Update addresses file
  if (fs.existsSync(ADDR_FILE)) {
    const addresses = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
    addresses["FullSystemSepolia#TWAPOracle"] = twapOracle.address;
    fs.writeFileSync(ADDR_FILE, JSON.stringify(addresses, null, 2));
    console.log("Updated deployed_addresses.json");
  }

  return twapOracle.address;
}

main()
  .then((address) => {
    console.log(`Done! New TWAP Oracle: ${address}`);
    process.exit(0);
  })
  .catch((err) => {
    console.error("Deployment failed:", err);
    process.exit(1);
  });
