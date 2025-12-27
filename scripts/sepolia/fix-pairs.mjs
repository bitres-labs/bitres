/**
 * Fix stuck LP pairs on Sepolia
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";
import { createPublicClient, http, parseEther } from "viem";
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
  const { viem } = await hre.network.connect();
  const [owner] = await viem.getWalletClients();
  const rpcUrl = hre.network.config?.url || process.env.SEPOLIA_RPC_URL;

  const publicClient = createPublicClient({
    chain: sepolia,
    transport: http(rpcUrl, { timeout: 60000 }),
  });

  const loadAbi = (relPath) =>
    JSON.parse(fs.readFileSync(path.join(process.cwd(), "artifacts", relPath), "utf8")).abi;

  const pairAbi = loadAbi("contracts/local/UniswapV2Pair.sol/UniswapV2Pair.json");
  const brsAbi = loadAbi("contracts/BRS.sol/BRS.json");
  const btdAbi = loadAbi("contracts/BTD.sol/BTD.json");

  console.log("=".repeat(60));
  console.log("  Fix Stuck LP Pairs on Sepolia");
  console.log("=".repeat(60));

  // Fix BTB/BTD - has tokens but no LP minted
  console.log("\n=> Fixing BTB/BTD pair...");
  const pairBTBBTD = addresses.PairBTBBTD;

  const btbBtdSupply = await publicClient.readContract({
    address: pairBTBBTD,
    abi: pairAbi,
    functionName: "totalSupply",
  });

  if (btbBtdSupply === 0n) {
    console.log("   Calling mint on BTB/BTD pair...");
    const hash = await owner.writeContract({
      address: pairBTBBTD,
      abi: pairAbi,
      functionName: "mint",
      args: [owner.account.address],
      account: owner.account,
    });
    console.log(`   TX: ${hash}`);
    await publicClient.waitForTransactionReceipt({ hash });
    console.log("   ✓ BTB/BTD LP minted");
  } else {
    console.log(`   ⏭ BTB/BTD already has LP (supply: ${btbBtdSupply})`);
  }

  // Fix BRS/BTD - empty, need to add tokens and mint
  console.log("\n=> Fixing BRS/BTD pair...");
  const pairBRSBTD = addresses.PairBRSBTD;

  const brsBtdSupply = await publicClient.readContract({
    address: pairBRSBTD,
    abi: pairAbi,
    functionName: "totalSupply",
  });

  if (brsBtdSupply === 0n) {
    // Check if there are tokens already
    const brsBalance = await publicClient.readContract({
      address: addresses.BRS,
      abi: brsAbi,
      functionName: "balanceOf",
      args: [pairBRSBTD],
    });

    if (brsBalance === 0n) {
      // Need to transfer tokens first
      console.log("   Transferring BRS and BTD to pair...");

      // Get BRS from owner
      const ownerBRS = await publicClient.readContract({
        address: addresses.BRS,
        abi: brsAbi,
        functionName: "balanceOf",
        args: [owner.account.address],
      });
      console.log(`   Owner BRS balance: ${ownerBRS}`);

      if (ownerBRS < parseEther("0.1")) {
        console.log("   ⚠ Not enough BRS in owner account, skipping");
        return;
      }

      // Transfer BRS
      let hash = await owner.writeContract({
        address: addresses.BRS,
        abi: brsAbi,
        functionName: "transfer",
        args: [pairBRSBTD, parseEther("0.1")],
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash });
      console.log("   ✓ BRS transferred");

      // Transfer BTD
      hash = await owner.writeContract({
        address: addresses.BTD,
        abi: btdAbi,
        functionName: "transfer",
        args: [pairBRSBTD, parseEther("0.001")],
        account: owner.account,
      });
      await publicClient.waitForTransactionReceipt({ hash });
      console.log("   ✓ BTD transferred");
    }

    // Mint LP
    console.log("   Calling mint on BRS/BTD pair...");
    const hash = await owner.writeContract({
      address: pairBRSBTD,
      abi: pairAbi,
      functionName: "mint",
      args: [owner.account.address],
      account: owner.account,
    });
    console.log(`   TX: ${hash}`);
    await publicClient.waitForTransactionReceipt({ hash });
    console.log("   ✓ BRS/BTD LP minted");
  } else {
    console.log(`   ⏭ BRS/BTD already has LP (supply: ${brsBtdSupply})`);
  }

  console.log("\n" + "=".repeat(60));
  console.log("  ✅ LP pairs fixed!");
  console.log("=".repeat(60));
}

main().catch(console.error);
