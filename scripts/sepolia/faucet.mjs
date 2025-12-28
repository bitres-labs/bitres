/**
 * Sepolia Token Faucet
 *
 * Distribute test tokens to specified addresses on Sepolia testnet.
 *
 * Usage:
 *   npx hardhat run scripts/sepolia/faucet.mjs --network sepolia
 *
 * Environment:
 *   FAUCET_RECIPIENTS - Comma-separated addresses to fund (optional)
 *
 * Default amounts:
 *   - 10 WBTC
 *   - 100,000 USDC
 *   - 100,000 USDT
 *   - 10 WETH (wrapped, not native ETH)
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";
import { parseEther, parseUnits } from "viem";

const CHAIN_ID = 11155111;
const ADDR_FILE = path.join(
  process.cwd(),
  `ignition/deployments/chain-${CHAIN_ID}/deployed_addresses.json`
);

// Default amounts to distribute
const AMOUNTS = {
  WBTC: parseUnits("10", 8),        // 10 WBTC
  USDC: parseUnits("100000", 6),    // 100,000 USDC
  USDT: parseUnits("100000", 6),    // 100,000 USDT
  WETH: parseEther("10"),           // 10 WETH
};

function loadAddresses() {
  if (!fs.existsSync(ADDR_FILE)) {
    throw new Error(`deployed_addresses.json not found at ${ADDR_FILE}`);
  }
  const raw = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  const map = {};
  for (const [k, v] of Object.entries(raw)) {
    const key = k.replace("FullSystemSepolia#", "");
    map[key] = v;
  }
  return map;
}

async function main() {
  console.log("=".repeat(60));
  console.log("  Bitres Sepolia Token Faucet");
  console.log("=".repeat(60));

  const addresses = loadAddresses();

  const connection = await hre.network.connect();
  const { viem } = connection;
  const wallets = await viem.getWalletClients();
  const [owner] = wallets;

  console.log(`\n=> Faucet operator: ${owner.account.address}`);

  // Get recipients from env or use default test addresses
  let recipients = process.env.FAUCET_RECIPIENTS
    ? process.env.FAUCET_RECIPIENTS.split(",").map((a) => a.trim())
    : [];

  if (recipients.length === 0) {
    console.log("\n⚠ No recipients specified. Skipping faucet distribution.");
    console.log("To distribute tokens, set FAUCET_RECIPIENTS environment variable:");
    console.log("  FAUCET_RECIPIENTS=0x123...,0x456... npx hardhat run scripts/sepolia/faucet.mjs --network sepolia");
    process.exit(0); // Exit successfully - no recipients is not an error
  }

  console.log(`\n=> Recipients (${recipients.length}):`);
  recipients.forEach((r) => console.log(`   - ${r}`));

  // Load token contracts
  const loadAbi = (relPath) =>
    JSON.parse(fs.readFileSync(path.join(process.cwd(), "artifacts", relPath), "utf8")).abi;

  const tokens = {
    WBTC: {
      address: addresses.WBTC,
      abi: loadAbi("contracts/local/MockWBTC.sol/MockWBTC.json"),
      amount: AMOUNTS.WBTC,
      decimals: 8,
    },
    USDC: {
      address: addresses.USDC,
      abi: loadAbi("contracts/local/MockUSDC.sol/MockUSDC.json"),
      amount: AMOUNTS.USDC,
      decimals: 6,
    },
    USDT: {
      address: addresses.USDT,
      abi: loadAbi("contracts/local/MockUSDT.sol/MockUSDT.json"),
      amount: AMOUNTS.USDT,
      decimals: 6,
    },
    WETH: {
      address: addresses.WETH,
      abi: loadAbi("contracts/local/MockWETH.sol/MockWETH.json"),
      amount: AMOUNTS.WETH,
      decimals: 18,
    },
  };

  console.log("\n=> Distributing tokens...\n");

  for (const recipient of recipients) {
    console.log(`Funding ${recipient}:`);

    for (const [symbol, token] of Object.entries(tokens)) {
      try {
        await owner.writeContract({
          address: token.address,
          abi: token.abi,
          functionName: "transfer",
          args: [recipient, token.amount],
          account: owner.account,
        });
        const displayAmount = Number(token.amount) / 10 ** token.decimals;
        console.log(`   ✓ ${displayAmount.toLocaleString()} ${symbol}`);
      } catch (err) {
        console.log(`   ✗ ${symbol}: ${err.message?.slice(0, 50) || err}`);
      }
    }
    console.log("");
  }

  console.log("=".repeat(60));
  console.log("  ✅ Faucet distribution complete!");
  console.log("=".repeat(60));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
