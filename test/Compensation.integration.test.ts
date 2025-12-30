/**
 * Compensation mechanism integration tests
 * Validates BTB and BRS compensation flows
 */

import { describe, it, beforeEach } from "node:test";
import { expect } from "chai";
import { deployFullSystem, getWallets, viem, networkHelpers } from "./helpers/setup-viem.js";

describe("Compensation Mechanisms (Integration)", function () {
  let fixture: any;

  async function deployCompensationFixture() {
    const [ownerWallet, user1Wallet] = await getWallets();

    // Deploy full system
    const fullSystem = await deployFullSystem();

    // Set BTB minimum price to $0.98 (required for compensation logic)
    const minBTBPrice = 98n * 10n ** 16n; // 0.98 USD (18 decimals)
    await fullSystem.configGov.write.setParam([2n, minBTBPrice], { account: ownerWallet.account }); // ParamType.MIN_BTB_PRICE = 2

    // Initialize BTD/USDC pool (required for getBTDPrice)
    await fullSystem.mockPoolBtdUsdc.write.initialize([
      fullSystem.btd.address,
      fullSystem.usdc.address
    ]);
    await fullSystem.mockPoolBtdUsdc.write.setReserves([
      1_000_000n * 10n ** 18n,  // 1M BTD
      1_000_000n * 10n ** 6n    // 1M USDC -> 1 BTD = 1 USD (at par)
    ]);

    // Initialize BTB/BTD pool
    await fullSystem.mockPoolBtbBtd.write.initialize([
      fullSystem.btb.address,
      fullSystem.btd.address
    ]);
    await fullSystem.mockPoolBtbBtd.write.setReserves([
      1000n * 10n ** 18n,  // 1000 BTB
      1000n * 10n ** 18n   // 1000 BTD -> 1 BTB = 1 BTD (at par)
    ]);

    // Initialize BRS/BTD pool
    await fullSystem.mockPoolBrsBtd.write.initialize([
      fullSystem.brs.address,
      fullSystem.btd.address
    ]);
    await fullSystem.mockPoolBrsBtd.write.setReserves([
      1000n * 10n ** 18n,  // 1000 BRS
      10_000n * 10n ** 18n // 10,000 BTD -> 1 BRS = 10 BTD (BRS at $10)
    ]);

    // Give user1 some WBTC for testing
    await fullSystem.wbtc.write.transfer(
      [user1Wallet.account.address, 10n * 10n ** 8n], // 10 WBTC
      { account: ownerWallet.account }
    );

    // Give user1 some USDC for pool setup
    await fullSystem.usdc.write.transfer(
      [user1Wallet.account.address, 1_000_000n * 10n ** 6n], // 1M USDC
      { account: ownerWallet.account }
    );

    // Give Treasury some BRS for compensation payouts
    await fullSystem.brs.write.transfer(
      [fullSystem.treasury.address, 1_000_000n * 10n ** 18n], // 1M BRS
      { account: ownerWallet.account }
    );

    return {
      owner: ownerWallet,
      user1: user1Wallet,
      system: fullSystem,
      tokens: {
        wbtc: fullSystem.wbtc,
        btd: fullSystem.btd,
        btb: fullSystem.btb,
        brs: fullSystem.brs,
        usdc: fullSystem.usdc
      },
      minter: fullSystem.minter,
      treasury: fullSystem.treasury,
      priceOracle: fullSystem.priceOracle,
      configCore: fullSystem.configCore,
      configGov: fullSystem.configGov
    };
  }

  beforeEach(async function () {
    fixture = await networkHelpers.loadFixture(deployCompensationFixture);
  });

  describe("BTB Compensation on BTD Redemption", function () {
    // SKIPPED: Requires TWAP oracle with 30min observation period
    it.skip("should mint BTB when CR < 100% during BTD redemption", async function () {
      const { owner, user1, system, tokens, minter, treasury, priceOracle, configGov } = fixture;

      // Step 1: User1 mint BTD with WBTC
      const wbtcAmount = 1n * 10n ** 8n; // 1 WBTC
      await tokens.wbtc.write.approve([minter.address, wbtcAmount], { account: user1.account });
      await minter.write.mintBTD([wbtcAmount], { account: user1.account });

      const btdBalance = await tokens.btd.read.balanceOf([user1.account.address]);
      console.log("User1 BTD balance after mint:", btdBalance.toString());
      expect(btdBalance > 0n).to.be.true;

      // Step 2: Simulate a WBTC price drop so CR < 100%
      // Assume current WBTC price is $50,000, minting about 50,000 BTD
      // We need the WBTC price low enough to push CR below 100%
      // Example: price falls to $25,000 -> CR = 25,000 / 50,000 = 50%

      // Set new WBTC price to $25,000 (50% drop)
      // Note: PriceOracle uses pool price, so we need to update BOTH oracles AND pool
      await system.mockBtcUsd.write.setAnswer([25_000n * 10n ** 8n]);
      await system.mockWbtcBtc.write.setAnswer([10n ** 8n]); // 1 WBTC = 1 BTC
      await system.mockPyth.write.setPrice([system.pythId, 2_500_000_000_000n, -8]); // $25,000 with 8 decimals

      // Update WBTC/USDC pool to reflect new price
      await system.mockPoolWbtcUsdc.write.setReserves([
        100n * 10n ** 8n,      // 100 WBTC (8 decimals)
        2_500_000n * 10n ** 6n // 2.5M USDC (6 decimals) -> $25k/WBTC
      ]);

      // Verify price updated
      const newWbtcPrice = await priceOracle.read.getWBTCPrice();
      console.log("New WBTC price:", newWbtcPrice.toString());

      // Step 3: User1 redeems BTD
      // With CR < 100%, they should receive partial WBTC plus BTB compensation
      const redeemAmount = btdBalance / 2n; // redeem half of BTD

      await tokens.btd.write.approve([minter.address, redeemAmount], { account: user1.account });

      const btbBalanceBefore = await tokens.btb.read.balanceOf([user1.account.address]);
      console.log("BTB balance before redeem:", btbBalanceBefore.toString());

      await minter.write.redeemBTD([redeemAmount], { account: user1.account });

      // Step 4: Verify BTB compensation was received
      const btbBalanceAfter = await tokens.btb.read.balanceOf([user1.account.address]);
      console.log("BTB balance after redeem:", btbBalanceAfter.toString());

      // Expect BTB compensation because CR < 100%
      expect(btbBalanceAfter > btbBalanceBefore).to.be.true;

      // BTB amount should cover the USD shortfall
      const btbReceived = btbBalanceAfter - btbBalanceBefore;
      console.log("BTB compensation received:", btbReceived.toString());
      expect(btbReceived > 0n).to.be.true;
    });

    it("should not mint BTB when CR >= 100% during BTD redemption", async function () {
      const { owner, user1, system, tokens, minter } = fixture;

      // Step 1: User1 mint BTD with WBTC
      const wbtcAmount = 1n * 10n ** 8n; // 1 WBTC
      await tokens.wbtc.write.approve([minter.address, wbtcAmount], { account: user1.account });
      await minter.write.mintBTD([wbtcAmount], { account: user1.account });

      const btdBalance = await tokens.btd.read.balanceOf([user1.account.address]);

      // Step 2: Keep WBTC price stable; CR should remain >= 100%
      // Leave price at the default $50,000

      // Step 3: User1 redeems BTD
      const redeemAmount = btdBalance / 2n;
      await tokens.btd.write.approve([minter.address, redeemAmount], { account: user1.account });

      const btbBalanceBefore = await tokens.btb.read.balanceOf([user1.account.address]);
      const wbtcBalanceBefore = await tokens.wbtc.read.balanceOf([user1.account.address]);

      await minter.write.redeemBTD([redeemAmount], { account: user1.account });

      // Step 4: Verify no BTB is received (CR >= 100%)
      const btbBalanceAfter = await tokens.btb.read.balanceOf([user1.account.address]);
      const wbtcBalanceAfter = await tokens.wbtc.read.balanceOf([user1.account.address]);

      // Should receive WBTC and no BTB
      expect(wbtcBalanceAfter > wbtcBalanceBefore).to.be.true;
      expect(btbBalanceAfter).to.equal(btbBalanceBefore); // BTB balance unchanged
    });
  });

  describe("BRS Compensation on Low BTB Price", function () {
    // SKIPPED: Requires TWAP oracle with 30min observation period
    it.skip("should mint BRS when BTB price < minBTBPrice during redemption", async function () {
      const { owner, user1, system, tokens, minter, configGov } = fixture;

      // Step 1: Set BTB minimum price (e.g., $0.98)
      const minBTBPrice = 98n * 10n ** 16n; // 0.98 USD (18 decimals)
      await configGov.write.setParam([2n, minBTBPrice], { account: owner.account }); // ParamType.MIN_BTB_PRICE = 2

      // Step 2: User1 mint BTD
      const wbtcAmount = 1n * 10n ** 8n;
      await tokens.wbtc.write.approve([minter.address, wbtcAmount], { account: user1.account });
      await minter.write.mintBTD([wbtcAmount], { account: user1.account });

      // Step 3: Simulate WBTC price drop to trigger BTB compensation
      await system.mockBtcUsd.write.setAnswer([25_000n * 10n ** 8n]);
      await system.mockWbtcBtc.write.setAnswer([10n ** 8n]);
      await system.mockPyth.write.setPrice([system.pythId, 2_500_000_000_000n, -8]);

      // Update WBTC/USDC pool
      await system.mockPoolWbtcUsdc.write.setReserves([
        100n * 10n ** 8n,
        2_500_000n * 10n ** 6n // $25k/WBTC
      ]);

      const btdBalance = await tokens.btd.read.balanceOf([user1.account.address]);
      const redeemAmount = btdBalance / 2n;

      // Step 4: Set BTB/BTD pool price so BTB < minBTBPrice
      // Example: 1 BTB = 0.95 BTD (market price below the floor)
      await system.mockPoolBtbBtd.write.setReserves([
        1000n * 10n ** 18n,  // 1000 BTB
        950n * 10n ** 18n    // 950 BTD -> 1 BTB = 0.95 BTD
      ]);

      // Step 5: Check price and CR
      const priceOracle = system.priceOracle;
      const btdPrice = await priceOracle.read.getBTDPrice();
      const btbPrice = await priceOracle.read.getBTBPrice();
      const brsPrice = await priceOracle.read.getBRSPrice();
      const minBTBPriceRead = await configGov.read.minBTBPrice();
      const cr = await minter.read.getCollateralRatio();

      console.log("BTD Price:", Number(btdPrice) / 1e18, "USD");
      console.log("BTB Price:", Number(btbPrice) / 1e18, "USD");
      console.log("BRS Price:", Number(brsPrice) / 1e18, "USD");
      console.log("minBTBPrice:", Number(minBTBPriceRead) / 1e18);
      console.log("minPriceInUSD:", Number(minBTBPriceRead * btdPrice / 10n**18n) / 1e18, "USD");
      console.log("CR:", Number(cr) / 1e18 * 100, "%");

      // Step 6: Redeem BTD
      await tokens.btd.write.approve([minter.address, redeemAmount], { account: user1.account });

      const brsBalanceBefore = await tokens.brs.read.balanceOf([user1.account.address]);
      console.log("BRS balance before redeem:", brsBalanceBefore.toString());

      await minter.write.redeemBTD([redeemAmount], { account: user1.account });

      // Step 6: Verify BRS compensation was received
      const brsBalanceAfter = await tokens.brs.read.balanceOf([user1.account.address]);
      console.log("BRS balance after redeem:", brsBalanceAfter.toString());

      // Should receive BRS compensation because BTB price < minBTBPrice
      expect(brsBalanceAfter > brsBalanceBefore).to.be.true;

      const brsCompensation = brsBalanceAfter - brsBalanceBefore;
      console.log("BRS compensation received:", brsCompensation.toString());
      expect(brsCompensation > 0n).to.be.true;
    });
  });

  describe("Combined Compensation Scenario", function () {
    // SKIPPED: Requires TWAP oracle with 30min observation period
    it.skip("should mint both BTB and BRS in extreme market conditions", async function () {
      const { owner, user1, system, tokens, minter, configGov } = fixture;

      // Step 1: Set BTB minimum price
      const minBTBPrice = 98n * 10n ** 16n;
      await configGov.write.setParam([2n, minBTBPrice], { account: owner.account }); // ParamType.MIN_BTB_PRICE = 2

      // Step 2: User1 mints a large amount of BTD
      const wbtcAmount = 5n * 10n ** 8n; // 5 WBTC
      await tokens.wbtc.write.approve([minter.address, wbtcAmount], { account: user1.account });
      await minter.write.mintBTD([wbtcAmount], { account: user1.account });

      const btdBalance = await tokens.btd.read.balanceOf([user1.account.address]);
      console.log("BTD balance:", btdBalance.toString());

      // Step 3: Simulate extreme market conditions
      // - WBTC price crashes 70% (from $50k to $15k) -> CR < 100%
      // - BTB market price collapses to $0.90 -> below minBTBPrice
      await system.mockBtcUsd.write.setAnswer([15_000n * 10n ** 8n]);
      await system.mockWbtcBtc.write.setAnswer([10n ** 8n]);
      await system.mockPyth.write.setPrice([system.pythId, 1_500_000_000_000n, -8]); // $15k

      // Update WBTC/USDC pool
      await system.mockPoolWbtcUsdc.write.setReserves([
        100n * 10n ** 8n,
        1_500_000n * 10n ** 6n // $15k/WBTC
      ]);

      // Set BTB price to $0.90
      await system.mockPoolBtbBtd.write.setReserves([
        1000n * 10n ** 18n,  // 1000 BTB
        900n * 10n ** 18n    // 900 BTD
      ]);

      // Step 4: Redeem BTD
      const redeemAmount = btdBalance / 2n;
      await tokens.btd.write.approve([minter.address, redeemAmount], { account: user1.account });

      const btbBalanceBefore = await tokens.btb.read.balanceOf([user1.account.address]);
      const brsBalanceBefore = await tokens.brs.read.balanceOf([user1.account.address]);

      await minter.write.redeemBTD([redeemAmount], { account: user1.account });

      // Step 5: Verify both BTB and BRS compensation
      const btbBalanceAfter = await tokens.btb.read.balanceOf([user1.account.address]);
      const brsBalanceAfter = await tokens.brs.read.balanceOf([user1.account.address]);

      const btbCompensation = btbBalanceAfter - btbBalanceBefore;
      const brsCompensation = brsBalanceAfter - brsBalanceBefore;

      console.log("BTB compensation:", btbCompensation.toString());
      console.log("BRS compensation:", brsCompensation.toString());

      // Should receive both BTB and BRS compensation
      expect(btbCompensation > 0n).to.be.true;
      expect(brsCompensation > 0n).to.be.true;
    });
  });

  describe("BTB Redemption for BTD", function () {
    // SKIPPED: Requires TWAP oracle with 30min observation period
    it.skip("should allow redeeming BTB for BTD when CR >= 100%", async function () {
      const { owner, user1, system, tokens, minter } = fixture;

      // Step 1: Create a low-CR scenario to obtain BTB
      // User1 mint BTD
      const wbtcAmount = 2n * 10n ** 8n;
      await tokens.wbtc.write.approve([minter.address, wbtcAmount], { account: user1.account });
      await minter.write.mintBTD([wbtcAmount], { account: user1.account });

      // Lower WBTC price to trigger BTB compensation
      await system.mockBtcUsd.write.setAnswer([25_000n * 10n ** 8n]);
      await system.mockWbtcBtc.write.setAnswer([10n ** 8n]);
      await system.mockPyth.write.setPrice([system.pythId, 2_500_000_000_000n, -8]);
      await system.mockPoolWbtcUsdc.write.setReserves([
        100n * 10n ** 8n,
        2_500_000n * 10n ** 6n // $25k/WBTC
      ]);

      const btdBalance = await tokens.btd.read.balanceOf([user1.account.address]);
      await tokens.btd.write.approve([minter.address, btdBalance / 2n], { account: user1.account });
      await minter.write.redeemBTD([btdBalance / 2n], { account: user1.account });

      const btbBalance = await tokens.btb.read.balanceOf([user1.account.address]);
      console.log("BTB balance after compensation:", btbBalance.toString());
      expect(btbBalance > 0n).to.be.true;

      // Step 2: Raise WBTC price so CR > 100% (need redemption headroom)
      // CR = collateral / liability = (1 WBTC * price) / 50k BTD
      // To push CR > 100%, price must exceed $50k
      // Set to $60k, giving CR = 60k / 50k = 120%
      await system.mockBtcUsd.write.setAnswer([60_000n * 10n ** 8n]);
      await system.mockWbtcBtc.write.setAnswer([10n ** 8n]);
      await system.mockPyth.write.setPrice([system.pythId, 6_000_000_000_000n, -8]);
      await system.mockPoolWbtcUsdc.write.setReserves([
        100n * 10n ** 8n,
        6_000_000n * 10n ** 6n // $60k/WBTC (20% over-collateralized)
      ]);

      // Step 3: Check CR and max redeemable
      const crAfterRecovery = await minter.read.getCollateralRatio();
      const totalWBTC = await minter.read.totalWBTC();
      const totalBTD = await minter.read.totalBTD();
      const wbtcPrice = await system.priceOracle.read.getWBTCPrice();
      const iusdPrice = await system.priceOracle.read.getIUSDPrice();

      console.log("CR after price recovery:", Number(crAfterRecovery) / 1e18 * 100, "%");
      console.log("Total WBTC:", Number(totalWBTC) / 1e8, "WBTC");
      console.log("Total BTD:", Number(totalBTD) / 1e18, "BTD");
      console.log("Collateral value:", Number(totalWBTC * wbtcPrice / 10n**8n) / 1e18, "USD");
      console.log("Liability value:", Number(totalBTD * iusdPrice / 10n**18n) / 1e18, "USD");

      // Step 4: Redeem BTB for BTD
      // maxRedeemableUSD = 60k - 50k = 10k
      // maxRedeemableBTD = 10k BTD
      // Redeem 5,000 BTB (< 10k limit)
      const redeemBtbAmount = 5000n * 10n ** 18n;
      await tokens.btb.write.approve([minter.address, redeemBtbAmount], { account: user1.account });

      const btdBalanceBefore = await tokens.btd.read.balanceOf([user1.account.address]);
      await minter.write.redeemBTB([redeemBtbAmount], { account: user1.account });

      // Step 4: Verify BTD was received
      const btdBalanceAfter = await tokens.btd.read.balanceOf([user1.account.address]);
      expect(btdBalanceAfter > btdBalanceBefore).to.be.true;

      // BTB should be burned
      const btbBalanceAfter = await tokens.btb.read.balanceOf([user1.account.address]);
      expect(btbBalanceAfter < btbBalance).to.be.true;
    });
  });
});
