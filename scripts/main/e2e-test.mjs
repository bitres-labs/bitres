/**
 * End-to-end test for the full local system.
 * Tests all core user flows after deployment + init.
 *
 * Run:
 *   npx hardhat run scripts/main/e2e-test.mjs --network localhost
 */

import fs from "fs";
import path from "path";
import hre from "hardhat";
import { createPublicClient, http, keccak256, parseEther, parseUnits, formatEther, formatUnits, stringToHex } from "viem";
import { hardhat as viemHardhat } from "viem/chains";

const ADDR_FILE = path.join(
  process.cwd(),
  "ignition/deployments/chain-31337/deployed_addresses.json"
);

let passed = 0;
let failed = 0;

function assert(condition, message) {
  if (!condition) {
    console.error(`   ✗ FAIL: ${message}`);
    failed++;
  } else {
    console.log(`   ✓ ${message}`);
    passed++;
  }
}

function loadAddresses() {
  const raw = JSON.parse(fs.readFileSync(ADDR_FILE, "utf8"));
  const map = {};
  for (const [k, v] of Object.entries(raw)) {
    map[k.replace("FullSystemLocal#", "")] = v;
  }
  return map;
}

async function main() {
  const addresses = loadAddresses();
  const connection = await hre.network.connect();
  const { viem } = connection;
  const wallets = await viem.getWalletClients();
  const [owner, , , ...users] = wallets;
  const user1 = users[0];
  const rpcUrl = hre.network.config?.url ?? "http://127.0.0.1:8545";
  const publicClient = createPublicClient({
    chain: viemHardhat,
    transport: http(rpcUrl),
  });

  const loadAbi = (relPath) =>
    JSON.parse(fs.readFileSync(path.join(process.cwd(), "artifacts", relPath), "utf8")).abi;

  const get = (key, abiName = key) => viem.getContractAt(abiName, addresses[key]);

  // Load contracts
  const brs = await get("BRS", "contracts/BRS.sol:BRS");
  const btd = await get("BTD", "contracts/BTD.sol:BTD");
  const btb = await get("BTB", "contracts/BTB.sol:BTB");
  const wbtc = await get("WBTC", "contracts/local/MockWBTC.sol:MockWBTC");
  const usdc = await get("USDC", "contracts/local/MockUSDC.sol:MockUSDC");
  const usdt = await get("USDT", "contracts/local/MockUSDT.sol:MockUSDT");
  const stBTD = await get("stBTD", "contracts/stBTD.sol:stBTD");
  const stBTB = await get("stBTB", "contracts/stBTB.sol:stBTB");
  const farming = await get("FarmingPool", "contracts/FarmingPool.sol:FarmingPool");
  const treasury = await get("Treasury", "contracts/Treasury.sol:Treasury");
  const minter = await get("Minter", "contracts/Minter.sol:Minter");
  const priceOracle = await get("PriceOracle", "contracts/PriceOracle.sol:PriceOracle");
  const interestPool = await get("InterestPool", "contracts/InterestPool.sol:InterestPool");
  const idealUSD = await get("IdealUSDManager", "contracts/IdealUSDManager.sol:IdealUSDManager");
  const configGov = await get("ConfigGov", "contracts/ConfigGov.sol:ConfigGov");
  const configCore = await get("ConfigCore", "contracts/ConfigCore.sol:ConfigCore");

  const btdAbi = loadAbi("contracts/BTD.sol/BTD.json");
  const btbAbi = loadAbi("contracts/BTB.sol/BTB.json");
  const minterAbi = loadAbi("contracts/Minter.sol/Minter.json");
  const farmingAbi = loadAbi("contracts/FarmingPool.sol/FarmingPool.json");
  const erc20Abi = loadAbi("contracts/local/MockWBTC.sol/MockWBTC.json");
  const stBTDAbi = loadAbi("contracts/stBTD.sol/stBTD.json");
  const stBTBAbi = loadAbi("contracts/stBTB.sol/stBTB.json");
  const interestPoolAbi = loadAbi("contracts/InterestPool.sol/InterestPool.json");

  // ===== TEST 1: System Configuration =====
  console.log("\n=== TEST 1: System Configuration ===");

  const poolCount = await farming.read.poolLength();
  assert(poolCount === 10n, `FarmingPool has ${poolCount} pools (expected 10)`);

  const mintFee = await configGov.read.mintFeeBP();
  assert(mintFee === 50n, `Mint fee = ${mintFee} bp (expected 50)`);

  const redeemFee = await configGov.read.redeemFeeBP();
  assert(redeemFee === 50n, `Redeem fee = ${redeemFee} bp (expected 50)`);

  const iusd = await idealUSD.read.getCurrentIUSD();
  assert(iusd === parseEther("1"), `IUSD = ${formatEther(iusd)} (expected 1.0)`);

  const [annualRate, monthlyFactor] = await idealUSD.read.getInflationParameters();
  assert(annualRate === 2n * 10n ** 16n, `Annual rate = ${annualRate} (expected 2e16 = 2%)`);

  // ===== TEST 2: PriceOracle =====
  console.log("\n=== TEST 2: PriceOracle ===");

  const btcPrice = await priceOracle.read.getWBTCPrice();
  assert(btcPrice > 0n, `BTC price = ${formatUnits(btcPrice, 18)} (> 0)`);

  const btdPrice = await priceOracle.read.getBTDPrice();
  assert(btdPrice > 0n, `BTD price = ${formatUnits(btdPrice, 18)} (> 0)`);

  const btbPrice = await priceOracle.read.getBTBPrice();
  assert(btbPrice > 0n, `BTB price = ${formatUnits(btbPrice, 18)} (> 0)`);

  // ===== TEST 3: Mint BTD =====
  console.log("\n=== TEST 3: Mint BTD ===");

  // user1 needs WBTC. Transfer from owner (who received tokens during init)
  const mintWbtcAmt = parseUnits("10", 8); // 10 WBTC
  await owner.writeContract({
    address: addresses.WBTC,
    abi: erc20Abi,
    functionName: "transfer",
    args: [user1.account.address, mintWbtcAmt],
  });

  const user1WbtcBefore = await wbtc.read.balanceOf([user1.account.address]);
  assert(user1WbtcBefore >= mintWbtcAmt, `User1 has ${formatUnits(user1WbtcBefore, 8)} WBTC`);

  // Approve Minter to spend WBTC
  await user1.writeContract({
    address: addresses.WBTC,
    abi: erc20Abi,
    functionName: "approve",
    args: [addresses.Minter, mintWbtcAmt],
  });

  // Calculate expected mint amount
  const [expectedBtd, expectedFee] = await minter.read.calculateMintAmount([parseUnits("1", 8)]); // 1 WBTC
  assert(expectedBtd > 0n, `1 WBTC mints ${formatEther(expectedBtd)} BTD (fee: ${formatEther(expectedFee)})`);

  // Mint BTD with 1 WBTC
  const btdBalBefore = await btd.read.balanceOf([user1.account.address]);
  await user1.writeContract({
    address: addresses.Minter,
    abi: minterAbi,
    functionName: "mintBTD",
    args: [parseUnits("1", 8)],
  });
  const btdBalAfter = await btd.read.balanceOf([user1.account.address]);
  const btdReceived = btdBalAfter - btdBalBefore;
  assert(btdReceived > 0n, `User1 received ${formatEther(btdReceived)} BTD from minting`);
  assert(btdReceived === expectedBtd, `Actual BTD matches calculateMintAmount`);

  // Check Treasury received WBTC
  const treasuryBal = await wbtc.read.balanceOf([addresses.Treasury]);
  assert(treasuryBal > 0n, `Treasury holds ${formatUnits(treasuryBal, 8)} WBTC`);

  // ===== TEST 4: Collateral Ratio =====
  console.log("\n=== TEST 4: Collateral Ratio ===");

  const cr = await minter.read.getCollateralRatio();
  // After first mint, CR should be ~100% (slightly different due to fees)
  assert(cr > 0n, `Collateral ratio = ${formatUnits(cr, 16)}%`);

  // ===== TEST 5: Redeem BTD =====
  console.log("\n=== TEST 5: Redeem BTD ===");

  const redeemAmount = parseEther("1000"); // Redeem 1000 BTD
  // Approve Minter to spend BTD
  await user1.writeContract({
    address: addresses.BTD,
    abi: btdAbi,
    functionName: "approve",
    args: [addresses.Minter, redeemAmount],
  });

  const [expectedWbtc, redeemFeeAmt] = await minter.read.calculateBurnAmount([redeemAmount]);
  assert(expectedWbtc > 0n, `Redeeming 1000 BTD returns ${formatUnits(expectedWbtc, 8)} WBTC (fee: ${formatUnits(redeemFeeAmt, 8)})`);

  const wbtcBefore = await wbtc.read.balanceOf([user1.account.address]);
  await user1.writeContract({
    address: addresses.Minter,
    abi: minterAbi,
    functionName: "redeemBTD",
    args: [redeemAmount],
  });
  const wbtcAfter = await wbtc.read.balanceOf([user1.account.address]);
  const wbtcReceived = wbtcAfter - wbtcBefore;
  assert(wbtcReceived > 0n, `User1 received ${formatUnits(wbtcReceived, 8)} WBTC from redemption`);

  // ===== TEST 6: stBTD Vault (ERC4626) =====
  console.log("\n=== TEST 6: stBTD Vault (ERC4626) ===");

  const vaultDeposit = parseEther("500");
  // Approve stBTD vault
  await user1.writeContract({
    address: addresses.BTD,
    abi: btdAbi,
    functionName: "approve",
    args: [addresses.stBTD, vaultDeposit],
  });

  const sharesBefore = await stBTD.read.balanceOf([user1.account.address]);
  await user1.writeContract({
    address: addresses.stBTD,
    abi: stBTDAbi,
    functionName: "deposit",
    args: [vaultDeposit, user1.account.address],
  });
  const sharesAfter = await stBTD.read.balanceOf([user1.account.address]);
  const sharesReceived = sharesAfter - sharesBefore;
  assert(sharesReceived > 0n, `User1 received ${formatEther(sharesReceived)} stBTD shares`);

  // Check total assets
  const totalAssets = await stBTD.read.totalAssets();
  assert(totalAssets > 0n, `stBTD total assets = ${formatEther(totalAssets)}`);

  // Redeem from vault
  const redeemShares = sharesReceived / 2n;
  const btdBeforeRedeem = await btd.read.balanceOf([user1.account.address]);
  await user1.writeContract({
    address: addresses.stBTD,
    abi: stBTDAbi,
    functionName: "redeem",
    args: [redeemShares, user1.account.address, user1.account.address],
  });
  const btdAfterRedeem = await btd.read.balanceOf([user1.account.address]);
  assert(btdAfterRedeem > btdBeforeRedeem, `User1 redeemed ${formatEther(btdAfterRedeem - btdBeforeRedeem)} BTD from stBTD`);

  // ===== TEST 7: FarmingPool Deposit/Withdraw/Claim =====
  console.log("\n=== TEST 7: FarmingPool ===");

  // Deposit USDC in pool 3
  const usdcAmount = parseUnits("1000", 6); // 1000 USDC
  await owner.writeContract({
    address: addresses.USDC,
    abi: erc20Abi,
    functionName: "transfer",
    args: [user1.account.address, usdcAmount],
  });
  await user1.writeContract({
    address: addresses.USDC,
    abi: erc20Abi,
    functionName: "approve",
    args: [addresses.FarmingPool, usdcAmount],
  });

  await user1.writeContract({
    address: addresses.FarmingPool,
    abi: farmingAbi,
    functionName: "deposit",
    args: [3n, usdcAmount], // pool 3 = USDC
  });
  const [stakedAmount,] = await farming.read.userInfo([3n, user1.account.address]);
  assert(stakedAmount === usdcAmount, `User1 staked ${formatUnits(stakedAmount, 6)} USDC in pool 3`);

  // Advance time to accumulate rewards
  const provider = hre.network?.provider ?? connection.provider;
  const advanceTime = async (seconds) => {
    if (provider?.request) {
      await provider.request({ method: "evm_increaseTime", params: [seconds] });
      await provider.request({ method: "evm_mine", params: [] });
    }
  };
  await advanceTime(3600); // 1 hour

  const pending = await farming.read.pendingReward([3n, user1.account.address]);
  assert(pending > 0n, `Pending BRS reward = ${formatEther(pending)}`);

  // Claim rewards
  const brsBalBefore = await brs.read.balanceOf([user1.account.address]);
  await user1.writeContract({
    address: addresses.FarmingPool,
    abi: farmingAbi,
    functionName: "claim",
    args: [3n],
  });
  const brsBalAfter = await brs.read.balanceOf([user1.account.address]);
  assert(brsBalAfter > brsBalBefore, `User1 claimed ${formatEther(brsBalAfter - brsBalBefore)} BRS`);

  // Withdraw from farming pool
  await user1.writeContract({
    address: addresses.FarmingPool,
    abi: farmingAbi,
    functionName: "withdraw",
    args: [3n, usdcAmount],
  });
  const [stakedAfterWithdraw,] = await farming.read.userInfo([3n, user1.account.address]);
  assert(stakedAfterWithdraw === 0n, `User1 withdrew all USDC from pool 3`);

  // ===== TEST 8: ConfigGov Parameters =====
  console.log("\n=== TEST 8: ConfigGov Parameters ===");

  const maxBtbRate = await configGov.read.maxBTBRate();
  assert(maxBtbRate === 2000n, `Max BTB rate = ${maxBtbRate} bp (expected 2000)`);

  const maxBtdRate = await configGov.read.maxBTDRate();
  assert(maxBtdRate === 2000n, `Max BTD rate = ${maxBtdRate} bp (expected 2000)`);

  const pceMaxDev = await configGov.read.pceMaxDeviation();
  assert(pceMaxDev > 0n, `PCE max deviation = ${pceMaxDev} (> 0)`);

  const baseRate = await configGov.read.baseRateDefault();
  assert(baseRate === 500n, `Base rate default = ${baseRate} bp (expected 500)`);

  // ===== TEST 9: ConfigCore Immutable References =====
  console.log("\n=== TEST 9: ConfigCore References ===");

  const coreBtd = await configCore.read.BTD();
  assert(coreBtd.toLowerCase() === addresses.BTD.toLowerCase(), `ConfigCore.BTD matches`);

  const coreBtb = await configCore.read.BTB();
  assert(coreBtb.toLowerCase() === addresses.BTB.toLowerCase(), `ConfigCore.BTB matches`);

  const coreBrs = await configCore.read.BRS();
  assert(coreBrs.toLowerCase() === addresses.BRS.toLowerCase(), `ConfigCore.BRS matches`);

  const coreWbtc = await configCore.read.WBTC();
  assert(coreWbtc.toLowerCase() === addresses.WBTC.toLowerCase(), `ConfigCore.WBTC matches`);

  const coreTreasury = await configCore.read.TREASURY();
  assert(coreTreasury.toLowerCase() === addresses.Treasury.toLowerCase(), `ConfigCore.TREASURY matches`);

  // ===== TEST 10: Treasury Balances =====
  console.log("\n=== TEST 10: Treasury Balances ===");

  const [tWbtc, tBrs, tBtd] = await treasury.read.getBalances();
  assert(tWbtc > 0n, `Treasury WBTC = ${formatUnits(tWbtc, 8)}`);
  console.log(`   info: Treasury BRS = ${formatEther(tBrs)}, BTD = ${formatEther(tBtd)}`);

  // ===== TEST 11: Access Control =====
  console.log("\n=== TEST 11: Access Control ===");

  // Non-owner cannot set ConfigGov params
  let accessReverted = false;
  try {
    await user1.writeContract({
      address: addresses.ConfigGov,
      abi: loadAbi("contracts/ConfigGov.sol/ConfigGov.json"),
      functionName: "setParam",
      args: [0n, 100n], // MintFeeBp = 100
    });
  } catch (e) {
    accessReverted = true;
  }
  assert(accessReverted, `Non-owner cannot setParam on ConfigGov`);

  // Non-owner cannot mint BTD directly (bypass Minter)
  let mintReverted = false;
  try {
    const MINTER_ROLE = keccak256(stringToHex("MINTER_ROLE"));
    const hasMinterRole = await btd.read.hasRole([MINTER_ROLE, user1.account.address]);
    assert(!hasMinterRole, `User1 does not have BTD MINTER_ROLE`);
  } catch (e) {
    // If hasRole reverts, that's also fine
    mintReverted = true;
  }

  // ===== TEST 12: FarmingPool Reward Rate =====
  console.log("\n=== TEST 12: Reward Economics ===");

  const rewardPerSec = await farming.read.currentRewardPerSecond();
  assert(rewardPerSec > 0n, `BRS reward/sec = ${formatEther(rewardPerSec)}`);

  const brsInFarming = await brs.read.balanceOf([addresses.FarmingPool]);
  assert(brsInFarming > 0n, `FarmingPool BRS balance = ${formatEther(brsInFarming)}`);

  // ===== SUMMARY =====
  console.log("\n" + "=".repeat(50));
  console.log(`E2E Test Results: ${passed} passed, ${failed} failed`);
  console.log("=".repeat(50));

  if (failed > 0) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error("E2E test error:", err);
  process.exit(1);
});
