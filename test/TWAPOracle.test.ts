/**
 * UniswapV2TWAPOracle Contract Tests
 * Tests TWAP calculation with time acceleration and price fluctuations
 *
 * Note: update() is now internal, all updates go through updateIfNeeded()
 * which enforces >= 30 minute intervals between observations
 */

import { describe, it, beforeEach } from "node:test";
import { expect } from "chai";
import hre from "hardhat";
import { parseUnits } from "viem";

// Get viem from network connection (Hardhat 3.0)
const { viem, networkHelpers } = await hre.network.connect();

describe("UniswapV2TWAPOracle", function () {
  // Contracts
  let twapOracle: any;
  let pair: any;
  let token0: any; // WBTC (8 decimals)
  let token1: any; // USDC (6 decimals)

  // Accounts
  let owner: any;
  let trader: any;

  // Test client for time manipulation
  let testClient: any;
  let publicClient: any;

  // Constants
  const PERIOD = 30 * 60; // 30 minutes in seconds
  const INITIAL_WBTC = parseUnits("10", 8); // 10 WBTC
  const INITIAL_USDC = parseUnits("900000", 6); // 900,000 USDC ($90,000 per BTC)

  async function deployFixture() {
    const wallets = await viem.getWalletClients();
    [owner, trader] = wallets;

    testClient = await viem.getTestClient();
    publicClient = await viem.getPublicClient();

    // Deploy mock tokens
    token0 = await viem.deployContract("contracts/local/MockWBTC.sol:MockWBTC", [
      owner.account.address,
    ]);
    token1 = await viem.deployContract("contracts/local/MockUSDC.sol:MockUSDC", [
      owner.account.address,
    ]);

    // Deploy UniswapV2Pair
    pair = await viem.deployContract("contracts/local/UniswapV2Pair.sol:UniswapV2Pair");

    // Initialize pair with tokens (sorted order)
    const addr0 = token0.address.toLowerCase();
    const addr1 = token1.address.toLowerCase();
    if (addr0 < addr1) {
      await pair.write.initialize([token0.address, token1.address]);
    } else {
      await pair.write.initialize([token1.address, token0.address]);
      // Swap references if order changed
      [token0, token1] = [token1, token0];
    }

    // Deploy TWAP Oracle
    twapOracle = await viem.deployContract(
      "contracts/UniswapV2TWAPOracle.sol:UniswapV2TWAPOracle"
    );

    // Add initial liquidity
    await token0.write.transfer([pair.address, INITIAL_WBTC]);
    await token1.write.transfer([pair.address, INITIAL_USDC]);
    await pair.write.mint([owner.account.address]);

    // Advance time and sync to start price accumulation
    // (First mint doesn't accumulate price because reserves were 0)
    await testClient.increaseTime({ seconds: 1 });
    await testClient.mine({ blocks: 1 });
    await pair.write.sync();

    // Transfer tokens to trader for swaps
    await token0.write.transfer([trader.account.address, parseUnits("100", 8)]);
    await token1.write.transfer([trader.account.address, parseUnits("10000000", 6)]);

    return { twapOracle, pair, token0, token1, owner, trader };
  }

  async function getSpotPrice(): Promise<number> {
    const [reserve0, reserve1] = await pair.read.getReserves();
    // Price of token0 in token1 (WBTC in USDC)
    // Adjust for decimals: WBTC(8) -> USDC(6)
    const price = (Number(reserve1) / 1e6) / (Number(reserve0) / 1e8);
    return price;
  }

  async function swap(amountIn: bigint, zeroForOne: boolean) {
    const [reserve0, reserve1] = await pair.read.getReserves();

    // Calculate output amount (with 0.3% fee)
    const amountInWithFee = amountIn * 997n;
    let amountOut: bigint;

    if (zeroForOne) {
      // Sell token0 for token1
      amountOut = (amountInWithFee * reserve1) / (reserve0 * 1000n + amountInWithFee);
      await token0.write.transfer([pair.address, amountIn], { account: trader.account });
      await pair.write.swap([0n, amountOut, trader.account.address, "0x"], {
        account: trader.account,
      });
    } else {
      // Sell token1 for token0
      amountOut = (amountInWithFee * reserve0) / (reserve1 * 1000n + amountInWithFee);
      await token1.write.transfer([pair.address, amountIn], { account: trader.account });
      await pair.write.swap([amountOut, 0n, trader.account.address, "0x"], {
        account: trader.account,
      });
    }

    return amountOut;
  }

  async function advanceTime(seconds: number) {
    await testClient.increaseTime({ seconds });
    await testClient.mine({ blocks: 1 });
  }

  beforeEach(async function () {
    await deployFixture();
  });

  describe("Basic Functionality", function () {
    it("should record first observation via updateIfNeeded", async function () {
      // First call should succeed (no observation yet)
      const result = await twapOracle.write.updateIfNeeded([pair.address]);

      const [olderTs, newerTs] = await twapOracle.read.getObservationInfo([pair.address]);

      expect(Number(olderTs)).to.equal(0); // No older observation yet
      expect(Number(newerTs)).to.be.gt(0); // Newer observation recorded
    });

    it("should record two observations after PERIOD passes", async function () {
      // First observation
      await twapOracle.write.updateIfNeeded([pair.address]);

      // Advance time >= PERIOD
      await advanceTime(PERIOD + 60);

      // Second observation
      await twapOracle.write.updateIfNeeded([pair.address]);

      const [olderTs, newerTs, elapsed] = await twapOracle.read.getObservationInfo([pair.address]);

      expect(Number(olderTs)).to.be.gt(0);
      expect(Number(newerTs)).to.be.gt(Number(olderTs));
      expect(Number(elapsed)).to.be.gte(PERIOD);
    });

    it("should skip update if called before PERIOD", async function () {
      // First observation
      await twapOracle.write.updateIfNeeded([pair.address]);
      const [, newerTs1] = await twapOracle.read.getObservationInfo([pair.address]);

      // Try to update before PERIOD - should be skipped
      await advanceTime(PERIOD / 2);
      await twapOracle.write.updateIfNeeded([pair.address]);

      const [, newerTs2] = await twapOracle.read.getObservationInfo([pair.address]);

      // Timestamp should NOT change (update was skipped)
      expect(Number(newerTs2)).to.equal(Number(newerTs1));
    });

    it("should report needsUpdate correctly", async function () {
      // Initially needs update (no observation)
      let needs = await twapOracle.read.needsUpdate([pair.address]);
      expect(needs).to.be.true;

      // After first observation, doesn't need update
      await twapOracle.write.updateIfNeeded([pair.address]);
      needs = await twapOracle.read.needsUpdate([pair.address]);
      expect(needs).to.be.false;

      // After PERIOD, needs update again
      await advanceTime(PERIOD + 1);
      needs = await twapOracle.read.needsUpdate([pair.address]);
      expect(needs).to.be.true;
    });

    it("should report TWAP ready after PERIOD", async function () {
      await twapOracle.write.updateIfNeeded([pair.address]);
      await advanceTime(PERIOD + 60);
      await twapOracle.write.updateIfNeeded([pair.address]);

      const ready = await twapOracle.read.isTWAPReady([pair.address]);
      expect(ready).to.be.true;
    });
  });

  describe("TWAP Calculation with Price Changes", function () {
    it("should calculate correct TWAP with stable price", async function () {
      const initialPrice = await getSpotPrice();
      console.log(`\n    Initial spot price: $${initialPrice.toFixed(2)}`);

      // Check token order
      const pairToken0 = await pair.read.token0();

      // First observation
      await twapOracle.write.updateIfNeeded([pair.address]);

      // Advance time without trades
      await advanceTime(PERIOD + 60);

      // Second observation
      await twapOracle.write.updateIfNeeded([pair.address]);

      // Determine actual decimals based on token order
      const isWbtcToken0 = pairToken0.toLowerCase() === token0.address.toLowerCase();
      const t0Decimals = isWbtcToken0 ? 8 : 6;
      const t1Decimals = isWbtcToken0 ? 6 : 8;

      // Get TWAP price
      const twapPrice = await twapOracle.read.getTWAPPrice([pair.address, t0Decimals, t1Decimals]);
      const twapPriceNum = Number(twapPrice) / 1e18;

      console.log(`    TWAP price: $${twapPriceNum.toFixed(2)}`);
      console.log(`    Difference: ${(((twapPriceNum - initialPrice) / initialPrice) * 100).toFixed(4)}%`);

      // TWAP should match initial price (within 0.1% tolerance)
      expect(Math.abs(twapPriceNum - initialPrice) / initialPrice).to.be.lt(0.001);
    });

    it("should calculate TWAP with price fluctuations", async function () {
      console.log("\n    === Price Fluctuation Test ===");

      const spotPrices: { time: number; price: number }[] = [];
      let totalTime = 0;

      // Record initial state
      const initialPrice = await getSpotPrice();
      spotPrices.push({ time: 0, price: initialPrice });
      console.log(`    t=0min: Spot price $${initialPrice.toFixed(2)}`);

      // First observation
      await twapOracle.write.updateIfNeeded([pair.address]);

      // Simulate trades over 35 minutes
      const tradeSchedule = [
        { minutesAfter: 5, sellWbtc: true, amount: parseUnits("0.5", 8) }, // Sell 0.5 WBTC -> price drops
        { minutesAfter: 10, sellWbtc: false, amount: parseUnits("50000", 6) }, // Buy with 50k USDC -> price rises
        { minutesAfter: 15, sellWbtc: true, amount: parseUnits("1", 8) }, // Sell 1 WBTC -> price drops
        { minutesAfter: 20, sellWbtc: false, amount: parseUnits("100000", 6) }, // Buy with 100k -> price rises
        { minutesAfter: 25, sellWbtc: true, amount: parseUnits("0.3", 8) }, // Sell 0.3 WBTC -> slight drop
        { minutesAfter: 32, sellWbtc: false, amount: parseUnits("30000", 6) }, // Buy with 30k -> slight rise
      ];

      let lastMinute = 0;
      for (const trade of tradeSchedule) {
        // Advance to trade time
        const minutesToAdvance = trade.minutesAfter - lastMinute;
        await advanceTime(minutesToAdvance * 60);
        totalTime += minutesToAdvance * 60;
        lastMinute = trade.minutesAfter;

        // Execute trade
        await swap(trade.amount, trade.sellWbtc);

        // Record spot price
        const spotPrice = await getSpotPrice();
        spotPrices.push({ time: totalTime, price: spotPrice });
        console.log(
          `    t=${trade.minutesAfter}min: ${trade.sellWbtc ? "SELL" : "BUY "} -> Spot $${spotPrice.toFixed(2)}`
        );
      }

      // Advance to 35 minutes total
      await advanceTime((35 - lastMinute) * 60);
      totalTime = 35 * 60;

      // Second observation (>= 30 min since first)
      await twapOracle.write.updateIfNeeded([pair.address]);

      // Calculate expected TWAP (time-weighted average)
      let weightedSum = 0;
      for (let i = 0; i < spotPrices.length - 1; i++) {
        const duration = spotPrices[i + 1].time - spotPrices[i].time;
        weightedSum += spotPrices[i].price * duration;
      }
      // Add last segment
      weightedSum += spotPrices[spotPrices.length - 1].price * (totalTime - spotPrices[spotPrices.length - 1].time);
      const expectedTWAP = weightedSum / totalTime;

      // Get actual TWAP
      const twapPrice = await twapOracle.read.getTWAPPrice([pair.address, 8, 6]);
      const actualTWAP = Number(twapPrice) / 1e18;

      console.log(`\n    Expected TWAP (calculated): $${expectedTWAP.toFixed(2)}`);
      console.log(`    Actual TWAP (contract):     $${actualTWAP.toFixed(2)}`);
      console.log(`    Final spot price:           $${spotPrices[spotPrices.length - 1].price.toFixed(2)}`);

      // TWAP should be between min and max spot prices
      const minPrice = Math.min(...spotPrices.map((p) => p.price));
      const maxPrice = Math.max(...spotPrices.map((p) => p.price));
      console.log(`    Price range: $${minPrice.toFixed(2)} - $${maxPrice.toFixed(2)}`);

      expect(actualTWAP).to.be.gte(minPrice * 0.99); // Allow 1% tolerance
      expect(actualTWAP).to.be.lte(maxPrice * 1.01);
    });

    it("should resist flash loan attack (instant price manipulation)", async function () {
      console.log("\n    === Flash Loan Resistance Test ===");

      // First observation at normal price
      await twapOracle.write.updateIfNeeded([pair.address]);
      const normalPrice = await getSpotPrice();
      console.log(`    Normal price: $${normalPrice.toFixed(2)}`);

      // Advance 31 minutes
      await advanceTime(31 * 60);

      // Simulate flash loan attack: massive swap to manipulate price
      console.log("    Simulating flash loan attack...");
      await swap(parseUnits("5", 8), true); // Dump 5 WBTC
      const manipulatedPrice = await getSpotPrice();
      console.log(`    Manipulated spot price: $${manipulatedPrice.toFixed(2)}`);

      // Take second observation immediately after manipulation
      await twapOracle.write.updateIfNeeded([pair.address]);

      // Get TWAP - should still be close to normal price
      const twapPrice = await twapOracle.read.getTWAPPrice([pair.address, 8, 6]);
      const actualTWAP = Number(twapPrice) / 1e18;
      console.log(`    TWAP price: $${actualTWAP.toFixed(2)}`);

      // TWAP should be much closer to normal price than manipulated price
      const twapDeviation = Math.abs(actualTWAP - normalPrice) / normalPrice;
      const spotDeviation = Math.abs(manipulatedPrice - normalPrice) / normalPrice;

      console.log(`    TWAP deviation from normal: ${(twapDeviation * 100).toFixed(2)}%`);
      console.log(`    Spot deviation from normal: ${(spotDeviation * 100).toFixed(2)}%`);

      // TWAP deviation should be much smaller than spot deviation
      expect(twapDeviation).to.be.lt(spotDeviation * 0.1); // TWAP affected < 10% of spot movement
    });

    it("should calculate TWAP from observation to NOW (not between observations)", async function () {
      console.log("\n    === TWAP 'to NOW' Logic Test ===");

      const initialPrice = await getSpotPrice();
      console.log(`    t=0: Initial spot price: $${initialPrice.toFixed(2)}`);

      // First observation at t=0
      await twapOracle.write.updateIfNeeded([pair.address]);

      // Advance 35 minutes (past PERIOD)
      await advanceTime(35 * 60);

      // Second observation at t=35min
      await twapOracle.write.updateIfNeeded([pair.address]);

      // Get TWAP immediately after second observation
      const pairToken0 = await pair.read.token0();
      const isWbtcToken0 = pairToken0.toLowerCase() === token0.address.toLowerCase();
      const t0Dec = isWbtcToken0 ? 8 : 6;
      const t1Dec = isWbtcToken0 ? 6 : 8;

      const twapAtT35 = await twapOracle.read.getTWAPPrice([pair.address, t0Dec, t1Dec]);
      const twapAtT35Num = Number(twapAtT35) / 1e18;
      console.log(`    t=35min: TWAP = $${twapAtT35Num.toFixed(2)} (reference: obs1 at t=0)`);

      // Advance 15 more minutes to t=50min, then make a big trade
      await advanceTime(15 * 60);

      // Big sell to drop price
      await swap(parseUnits("2", 8), true); // Sell 2 WBTC
      const priceAfterSell = await getSpotPrice();
      console.log(`    t=50min: Trade executed, spot = $${priceAfterSell.toFixed(2)}`);

      // Advance another 15 minutes so the new price accumulates
      await advanceTime(15 * 60);

      // Now at t=65min, TWAP should include the lower price
      // Reference is obs2 (t=35min, since 65-35=30min >= PERIOD)
      // TWAP = weighted avg from t=35min to t=65min:
      //   - t=35min to t=50min (15min): $90k
      //   - t=50min to t=65min (15min): ~$62k
      const twapAtT65 = await twapOracle.read.getTWAPPrice([pair.address, t0Dec, t1Dec]);
      const twapAtT65Num = Number(twapAtT65) / 1e18;
      console.log(`    t=65min: TWAP = $${twapAtT65Num.toFixed(2)} (reference: obs2 at t=35min)`);

      // Calculate expected TWAP: (15min * $90k + 15min * $62.5k) / 30min ≈ $76k
      const expectedTwap = (15 * initialPrice + 15 * priceAfterSell) / 30;
      console.log(`    Expected TWAP: ~$${expectedTwap.toFixed(2)}`);

      // TWAP should have decreased significantly from the initial price
      const twapChange = ((twapAtT65Num - initialPrice) / initialPrice) * 100;
      console.log(`    TWAP change from initial: ${twapChange.toFixed(2)}%`);

      // Verify: TWAP should be between initial price and current spot
      expect(twapAtT65Num).to.be.lt(initialPrice); // Lower than initial
      expect(twapAtT65Num).to.be.gt(priceAfterSell); // Higher than current spot

      // Verify: TWAP should be close to expected (within 5%)
      const accuracy = Math.abs(twapAtT65Num - expectedTwap) / expectedTwap;
      console.log(`    TWAP accuracy vs expected: ${(accuracy * 100).toFixed(2)}%`);
      expect(accuracy).to.be.lt(0.05);

      console.log(`    ✓ TWAP correctly reflects recent price changes (obs → NOW)`);
    });
  });

  describe("Edge Cases", function () {
    it("should enforce PERIOD between updates", async function () {
      // Take first observation
      await twapOracle.write.updateIfNeeded([pair.address]);
      const [, newerTs1] = await twapOracle.read.getObservationInfo([pair.address]);

      // Try rapid updates - they should all be skipped
      for (let i = 0; i < 5; i++) {
        await advanceTime(60); // 1 minute each
        await twapOracle.write.updateIfNeeded([pair.address]);
      }

      // Check timestamp hasn't changed (updates were skipped)
      const [, newerTs2] = await twapOracle.read.getObservationInfo([pair.address]);
      expect(Number(newerTs2)).to.equal(Number(newerTs1));

      // Should still need PERIOD to pass
      const ready = await twapOracle.read.isTWAPReady([pair.address]);
      expect(ready).to.be.false;

      // Advance remaining time to complete PERIOD
      await advanceTime(PERIOD);
      await twapOracle.write.updateIfNeeded([pair.address]);

      const readyNow = await twapOracle.read.isTWAPReady([pair.address]);
      expect(readyNow).to.be.true;
    });

    it("should revert getTWAP when no observation is old enough", async function () {
      // Take first observation - it's at current time, not old enough
      await twapOracle.write.updateIfNeeded([pair.address]);

      let reverted = false;
      try {
        await twapOracle.read.getTWAP([pair.address]);
      } catch (e: any) {
        reverted = true;
        expect(e.message).to.include("No observation >= PERIOD ago");
      }
      expect(reverted).to.be.true;
    });

    it("should revert getTWAP before PERIOD elapsed from observation", async function () {
      // First observation
      await twapOracle.write.updateIfNeeded([pair.address]);

      // Advance less than PERIOD
      await advanceTime(PERIOD - 60); // 29 minutes

      // Still not old enough
      let reverted = false;
      try {
        await twapOracle.read.getTWAP([pair.address]);
      } catch (e: any) {
        reverted = true;
        expect(e.message).to.include("No observation >= PERIOD ago");
      }
      expect(reverted).to.be.true;

      // Advance past PERIOD
      await advanceTime(120); // 2 more minutes

      // Now should work
      const twap = await twapOracle.read.getTWAP([pair.address]);
      expect(twap > 0n).to.be.true;
    });
  });

  describe("Gas Usage", function () {
    it("should have reasonable gas cost for updateIfNeeded", async function () {
      const hash = await twapOracle.write.updateIfNeeded([pair.address]);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });

      console.log(`\n    Gas used for updateIfNeeded(): ${receipt.gasUsed}`);
      expect(Number(receipt.gasUsed)).to.be.lt(120000); // Should be under 120k gas
    });

    it("should use minimal gas when update is skipped", async function () {
      // First update
      await twapOracle.write.updateIfNeeded([pair.address]);

      // Second call before PERIOD - should be skipped
      await advanceTime(60); // Only 1 minute
      const hash = await twapOracle.write.updateIfNeeded([pair.address]);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });

      console.log(`\n    Gas used for skipped update: ${receipt.gasUsed}`);
      // Skipped update should use less gas (just the check, no state change)
      expect(Number(receipt.gasUsed)).to.be.lt(30000);
    });
  });
});
