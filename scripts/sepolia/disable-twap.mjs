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

  const priceOracle = await viem.getContractAt(
    "contracts/PriceOracle.sol:PriceOracle",
    addresses.PriceOracle
  );

  console.log("Disabling TWAP (using spot prices)...");
  const tx = await priceOracle.write.setUseTWAP([false], { account: owner.account });
  await publicClient.waitForTransactionReceipt({ hash: tx });
  console.log("TWAP disabled. Prices will use spot prices now.");
  console.log("\nRun 'npm run sepolia:enable-twap' in 30 minutes to enable TWAP.");
}

main().catch(console.error);
