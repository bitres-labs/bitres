/**
 * UniswapV2TWAPOracle Contract Tests
 * Tests TWAP calculation with time acceleration and price fluctuations
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
    it("should record first observation", async function () {
      await twapOracle.write.update([pair.address]);

      const [olderTs, newerTs] = await twapOracle.read.getObservationInfo([pair.address]);

      expect(Number(olderTs)).to.equal(0); // No older observation yet
      expect(Number(newerTs)).to.be.gt(0); // Newer observation recorded
    });

    it("should record two observations after time passes", async function () {
      // First observation
      await twapOracle.write.update([pair.address]);

      // Advance time
      await advanceTime(PERIOD + 60);

      // Second observation
      await twapOracle.write.update([pair.address]);

      const [olderTs, newerTs, elapsed] = await twapOracle.read.getObservationInfo([pair.address]);

      expect(Number(olderTs)).to.be.gt(0);
      expect(Number(newerTs)).to.be.gt(Number(olderTs));
      expect(Number(elapsed)).to.be.gte(PERIOD);
    });

    it("should report TWAP not ready before PERIOD", async function () {
      await twapOracle.write.update([pair.address]);
      await advanceTime(PERIOD / 2); // Only half the period
      await twapOracle.write.update([pair.address]);

      const ready = await twapOracle.read.isTWAPReady([pair.address]);
      expect(ready).to.be.false;
    });

    it("should report TWAP ready after PERIOD", async function () {
      await twapOracle.write.update([pair.address]);
      await advanceTime(PERIOD + 60);
      await twapOracle.write.update([pair.address]);

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
      const pairToken1 = await pair.read.token1();
      console.log(`    Pair token0: ${pairToken0}`);
      console.log(`    Pair token1: ${pairToken1}`);
      console.log(`    Our token0 (WBTC): ${token0.address}`);
      console.log(`    Our token1 (USDC): ${token1.address}`);

      // Check pair's cumulative values before first observation
      const p0Before = await pair.read.price0CumulativeLast();
      const [r0, r1, tsLast] = await pair.read.getReserves();
      const currentBlock = await publicClient.getBlock();
      console.log(`    Pair price0CumulativeLast: ${p0Before}`);
      console.log(`    Pair reserves: ${r0}, ${r1}, tsLast=${tsLast}`);
      console.log(`    Current block.timestamp: ${currentBlock.timestamp}`);

      // First observation
      await twapOracle.write.update([pair.address]);

      // Advance time without trades
      await advanceTime(PERIOD + 60);

      // Second observation
      await twapOracle.write.update([pair.address]);

      // Debug: check observations
      const obs0 = await twapOracle.read.pairObservations([pair.address, 0n]);
      const obs1 = await twapOracle.read.pairObservations([pair.address, 1n]);
      console.log(`    Obs0: ts=${obs0[0]}, p0Cum=${obs0[1]}, p1Cum=${obs0[2]}`);
      console.log(`    Obs1: ts=${obs1[0]}, p0Cum=${obs1[1]}, p1Cum=${obs1[2]}`);
      console.log(`    Delta p0Cum: ${obs1[1] - obs0[1]}`);
      console.log(`    Time elapsed: ${obs1[0] - obs0[0]}`);

      // Debug: check raw TWAP value
      const twapRaw = await twapOracle.read.getTWAP([pair.address]);
      console.log(`    getTWAP raw: ${twapRaw}`);

      // Determine actual decimals based on token order
      const isWbtcToken0 = pairToken0.toLowerCase() === token0.address.toLowerCase();
      const t0Decimals = isWbtcToken0 ? 8 : 6;
      const t1Decimals = isWbtcToken0 ? 6 : 8;
      console.log(`    Using decimals: token0=${t0Decimals}, token1=${t1Decimals}`);

      // Get TWAP price
      const twapPrice = await twapOracle.read.getTWAPPrice([pair.address, t0Decimals, t1Decimals]);
      console.log(`    getTWAPPrice raw: ${twapPrice}`);
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
      await twapOracle.write.update([pair.address]);

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

      // Second observation
      await twapOracle.write.update([pair.address]);

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
      await twapOracle.write.update([pair.address]);
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
      await twapOracle.write.update([pair.address]);

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
  });

  describe("Edge Cases", function () {
    it("should handle multiple rapid updates correctly", async function () {
      // Take many observations in quick succession
      await twapOracle.write.update([pair.address]);

      for (let i = 0; i < 5; i++) {
        await advanceTime(60); // 1 minute each
        await twapOracle.write.update([pair.address]);
      }

      // Should still need PERIOD to pass
      const ready = await twapOracle.read.isTWAPReady([pair.address]);
      expect(ready).to.be.false;

      // Advance remaining time
      await advanceTime(PERIOD);
      await twapOracle.write.update([pair.address]);

      const readyNow = await twapOracle.read.isTWAPReady([pair.address]);
      expect(readyNow).to.be.true;
    });

    it("should revert getTWAP with only one observation", async function () {
      await twapOracle.write.update([pair.address]);

      let reverted = false;
      try {
        await twapOracle.read.getTWAP([pair.address]);
      } catch (e: any) {
        reverted = true;
        expect(e.message).to.include("Need two observations");
      }
      expect(reverted).to.be.true;
    });

    it("should revert getTWAP before PERIOD elapsed", async function () {
      await twapOracle.write.update([pair.address]);
      await advanceTime(PERIOD / 2);
      await twapOracle.write.update([pair.address]);

      let reverted = false;
      try {
        await twapOracle.read.getTWAP([pair.address]);
      } catch (e: any) {
        reverted = true;
        expect(e.message).to.include("Observation period too short");
      }
      expect(reverted).to.be.true;
    });
  });

  describe("Gas Usage", function () {
    it("should have reasonable gas cost for update", async function () {
      const hash = await twapOracle.write.update([pair.address]);
      const receipt = await publicClient.waitForTransactionReceipt({ hash });

      console.log(`\n    Gas used for update(): ${receipt.gasUsed}`);
      expect(Number(receipt.gasUsed)).to.be.lt(120000); // Should be under 120k gas
    });
  });
});
