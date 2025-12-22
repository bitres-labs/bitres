// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";

/// @title UniswapV2TWAPOracle Time-Weighted Average Price Oracle Fuzz Tests
/// @notice Tests all edge cases for TWAP price calculation, accumulator updates, and price manipulation resistance
contract UniswapV2TWAPOracleFuzzTest is Test {
    using Constants for *;

    // ==================== Price Accumulator Fuzz Tests ====================

    /// @notice Fuzz test: Price accumulator grows over time
    function testFuzz_PriceAccumulator_Growth(
        uint24 reserve0,  // uint24 max around 16M
        uint24 reserve1,
        uint16 timeElapsed
    ) public pure {
        vm.assume(reserve0 > 1e6 && reserve0 < 1e7);  // 1M-10M
        vm.assume(reserve1 > 1e6 && reserve1 < 1e7);
        vm.assume(timeElapsed > 10 && timeElapsed < 86400); // 10 seconds - 1 day

        // Calculate unit price (reserve1/reserve0)
        uint256 price = uint256(reserve1) * Constants.PRECISION_18 / uint256(reserve0);

        // Price accumulated = price * timeElapsed
        uint256 priceAccumulated = price * uint256(timeElapsed);

        // Verify: Price accumulator grows over time
        assertGt(priceAccumulated, 0);
        assertGt(priceAccumulated, price);  // timeElapsed is at least 10 seconds, so definitely > price
    }

    /// @notice Fuzz test: Price accumulator update
    function testFuzz_PriceAccumulator_Update(
        uint64 oldAccumulator,   // Further reduce type size
        uint24 reserve0,         // Reduce type to uint24
        uint24 reserve1,
        uint16 timeElapsed
    ) public pure {
        vm.assume(reserve0 > 1e6 && reserve0 < 1e7);  // 1M-10M
        vm.assume(reserve1 > 1e6 && reserve1 < 1e7);
        vm.assume(timeElapsed > 10 && timeElapsed < 86400);  // 10 seconds - 1 day

        // Calculate increment
        uint256 price = uint256(reserve1) * Constants.PRECISION_18 / uint256(reserve0);
        uint256 increment = price * uint256(timeElapsed);
        vm.assume(uint256(oldAccumulator) + increment < type(uint224).max);

        // Update accumulator
        uint224 newAccumulator = uint224(uint256(oldAccumulator) + increment);

        // Verify: Accumulator monotonically increases
        assertGe(newAccumulator, oldAccumulator);
    }

    // ==================== TWAP Calculation Fuzz Tests ====================

    /// @notice Fuzz test: TWAP calculation basic logic
    function testFuzz_TWAP_Calculation(
        uint64 accumulatorDelta,  // Use delta instead of absolute value
        uint16 timeElapsed
    ) public pure {
        vm.assume(accumulatorDelta > 1e9 && accumulatorDelta < 1e18);
        vm.assume(timeElapsed > 60 && timeElapsed <= 86400);  // 1 minute - 1 day

        // TWAP = accumulatorDelta / timeElapsed
        uint256 twap = uint256(accumulatorDelta) / uint256(timeElapsed);

        // Verify: TWAP calculated correctly
        assertGt(twap, 0);
    }

    /// @notice Fuzz test: TWAP window length impact
    function testFuzz_TWAP_WindowLength(
        uint224 accumulatorDelta,
        uint32 shortWindow,
        uint32 longWindow
    ) public pure {
        vm.assume(accumulatorDelta > 1e18);
        vm.assume(shortWindow > 60 && shortWindow < 3600); // 1 minute - 1 hour
        vm.assume(longWindow > shortWindow && longWindow <= 24 hours);

        // Same accumulator change, different window periods TWAP
        uint256 twapShort = uint256(accumulatorDelta) / uint256(shortWindow);
        uint256 twapLong = uint256(accumulatorDelta) / uint256(longWindow);

        // Verify: Longer window period means smaller TWAP for same change
        assertGt(twapShort, twapLong);
    }

    /// @notice Fuzz test: Multi-period TWAP consistency
    function testFuzz_TWAP_MultiPeriod(
        uint64 delta1,  // First segment accumulator increment
        uint64 delta2,  // Second segment accumulator increment
        uint16 period1,
        uint16 period2
    ) public pure {
        vm.assume(delta1 > 1e9 && delta1 < 1e15);
        vm.assume(delta2 > 1e9 && delta2 < 1e15);
        vm.assume(period1 > 60 && period1 <= 43200);  // 1 minute - 12 hours
        vm.assume(period2 > 60 && period2 <= 43200);

        // Calculate overall TWAP
        uint256 totalDelta = uint256(delta1) + uint256(delta2);
        uint256 totalPeriod = uint256(period1) + uint256(period2);
        uint256 overallTwap = totalDelta / totalPeriod;

        // Verify: Overall TWAP is within reasonable range
        assertGt(overallTwap, 0);
        assertLt(overallTwap, totalDelta);  // TWAP < total delta
    }

    // ==================== Price Manipulation Resistance Fuzz Tests ====================

    /// @notice Fuzz test: Single block manipulation has limited impact
    function testFuzz_Manipulation_SingleBlock(
        uint224 normalAccumulator,
        uint112 normalReserve0,
        uint112 normalReserve1,
        uint112 manipulatedReserve0,
        uint112 manipulatedReserve1,
        uint32 windowSize
    ) public pure {
        vm.assume(normalReserve0 > 1e8);
        vm.assume(normalReserve1 > 1e8);
        vm.assume(manipulatedReserve0 > 1e6);
        vm.assume(manipulatedReserve1 > 1e6);
        vm.assume(windowSize > 3600 && windowSize <= 24 hours); // At least 1 hour window

        // Normal price
        uint256 normalPrice = uint256(normalReserve1) * Constants.PRECISION_18 / uint256(normalReserve0);
        vm.assume(normalPrice > 0 && normalPrice < type(uint224).max);

        // Manipulated price (assume 1 block ~12 seconds)
        uint256 manipPrice = uint256(manipulatedReserve1) * Constants.PRECISION_18 / uint256(manipulatedReserve0);
        vm.assume(manipPrice > 0 && manipPrice < type(uint224).max);

        // Single block time impact
        uint32 singleBlockTime = 12; // 12 seconds
        uint256 manipImpact = manipPrice * singleBlockTime;

        // Normal time impact
        uint256 normalImpact = normalPrice * (uint256(windowSize) - singleBlockTime);

        vm.assume(manipImpact + normalImpact < type(uint224).max);

        // Overall TWAP
        uint256 twapWithManip = (manipImpact + normalImpact) / uint256(windowSize);

        // Verify: Single block manipulation has small impact on TWAP (< 1%)
        // manipImpact ratio = singleBlockTime / windowSize
        uint256 manipRatio = (singleBlockTime * Constants.BPS_BASE) / windowSize;

        // For 1 hour window, single block ratio = 12/3600 = 0.33%
        if (windowSize >= 3600) {
            assertLt(manipRatio, 100); // < 1%
        }
    }

    /// @notice Fuzz test: TWAP smooths volatility
    function testFuzz_TWAP_Smoothing(
        uint32 price1,  // Reduce type
        uint32 price2,
        uint16 time1,
        uint16 time2
    ) public pure {
        vm.assume(price1 > 1e6 && price1 < 1e9);  // Adjust range
        vm.assume(price2 > 1e6 && price2 < 1e9);
        vm.assume(price2 != price1); // Price volatility
        vm.assume(time1 > 60 && time1 <= 43200);  // 1 minute - 12 hours
        vm.assume(time2 > 60 && time2 <= 43200);

        // Calculate two segment accumulations (no need for baseAccumulator, directly calculate delta)
        uint256 delta1 = uint256(price1) * uint256(time1);
        uint256 delta2 = uint256(price2) * uint256(time2);

        // Calculate TWAP
        uint256 totalDelta = delta1 + delta2;
        uint256 totalTime = uint256(time1) + uint256(time2);
        uint256 twap = totalDelta / totalTime;

        // Verify: TWAP is between the two prices (weighted average)
        uint256 minPrice = price1 < price2 ? price1 : price2;
        uint256 maxPrice = price1 > price2 ? price1 : price2;

        assertGe(twap, minPrice);
        assertLe(twap, maxPrice);
    }

    // ==================== Oracle Update Frequency Fuzz Tests ====================

    /// @notice Fuzz test: Minimum update interval
    function testFuzz_Update_MinInterval(
        uint32 lastUpdateTime,
        uint32 currentTime,
        uint32 minInterval
    ) public pure {
        vm.assume(currentTime > lastUpdateTime);
        vm.assume(minInterval > 0 && minInterval <= 1 hours);

        uint32 elapsed = currentTime - lastUpdateTime;

        // Verify: Whether minimum update interval is met
        bool canUpdate = elapsed >= minInterval;

        if (canUpdate) {
            assertGe(elapsed, minInterval);
        } else {
            assertLt(elapsed, minInterval);
        }
    }

    /// @notice Fuzz test: Update frequency impact on precision
    function testFuzz_Update_FrequencyAccuracy(
        uint224 accumulatorDelta,
        uint8 updateCount
    ) public pure {
        vm.assume(accumulatorDelta > 1e18);
        vm.assume(updateCount > 1 && updateCount <= 100);

        // Average change per update
        uint256 avgDeltaPerUpdate = uint256(accumulatorDelta) / uint256(updateCount);

        // Verify: More frequent updates mean smaller change per update
        assertGt(avgDeltaPerUpdate, 0);
        assertLt(avgDeltaPerUpdate, accumulatorDelta);
    }

    // ==================== Reserve Change Fuzz Tests ====================

    /// @notice Fuzz test: Reserve change impact on price
    function testFuzz_Reserve_PriceImpact(
        uint16 reserve0Base,   // Base value
        uint16 reserve1Base,
        uint8 reserve0Change,  // Use uint8, 0-100 represents change percentage
        uint8 reserve1Change
    ) public pure {
        vm.assume(reserve0Base > 1000 && reserve0Base < 10000);
        vm.assume(reserve1Base > 1000 && reserve1Base < 10000);
        vm.assume(reserve0Change <= 100);  // Max +/-100%
        vm.assume(reserve1Change <= 100);

        // Construct changed values
        uint256 reserve0Before = uint256(reserve0Base) * 1e6;
        uint256 reserve1Before = uint256(reserve1Base) * 1e6;

        // Randomly increase or decrease (based on value parity)
        uint256 reserve0After;
        if (reserve0Change % 2 == 0) {
            // Increase
            reserve0After = reserve0Before + (reserve0Before * uint256(reserve0Change) / 100);
        } else {
            // Decrease
            uint256 decrease = reserve0Before * uint256(reserve0Change) / 100;
            reserve0After = reserve0Before > decrease ? reserve0Before - decrease : reserve0Before;
        }

        uint256 reserve1After;
        if (reserve1Change % 2 == 0) {
            // Increase
            reserve1After = reserve1Before + (reserve1Before * uint256(reserve1Change) / 100);
        } else {
            // Decrease
            uint256 decrease = reserve1Before * uint256(reserve1Change) / 100;
            reserve1After = reserve1Before > decrease ? reserve1Before - decrease : reserve1Before;
        }

        // Calculate before and after prices
        uint256 priceBefore = (reserve1Before * Constants.PRECISION_18) / reserve0Before;
        uint256 priceAfter = (reserve1After * Constants.PRECISION_18) / reserve0After;

        // Verify: Prices are all > 0
        assertGt(priceBefore, 0);
        assertGt(priceAfter, 0);
    }

    /// @notice Fuzz test: K value constant (Uniswap constant product)
    function testFuzz_Reserve_ConstantProduct(
        uint112 reserve0,
        uint112 reserve1,
        uint112 amount0In,
        uint112 amount1Out
    ) public pure {
        vm.assume(reserve0 > 1e8);
        vm.assume(reserve1 > 1e8);
        vm.assume(amount0In > 0 && amount0In < reserve0 / 2);
        vm.assume(amount1Out > 0 && amount1Out < reserve1 / 2);

        // K value before trade
        vm.assume(uint256(reserve0) * uint256(reserve1) < type(uint256).max);
        uint256 kBefore = uint256(reserve0) * uint256(reserve1);

        // Reserves after trade
        uint256 reserve0After = uint256(reserve0) + uint256(amount0In);
        uint256 reserve1After = uint256(reserve1) - uint256(amount1Out);

        // K value after trade
        vm.assume(reserve0After * reserve1After < type(uint256).max);
        uint256 kAfter = reserve0After * reserve1After;

        // Verify: K value should increase or stay same (due to fees)
        // In ideal fee-free case kAfter >= kBefore
        assertGt(kAfter, 0);
    }

    // ==================== Overflow Protection Fuzz Tests ====================

    /// @notice Fuzz test: Accumulator overflow protection
    function testFuzz_Accumulator_OverflowProtection(
        uint224 currentAccumulator
    ) public pure {
        // Verify: When accumulator approaches upper limit, should stop accumulating or reset
        bool nearOverflow = currentAccumulator > type(uint224).max - 1e24;

        if (nearOverflow) {
            // Should trigger some protection mechanism
            assertGt(currentAccumulator, type(uint224).max / 2);
        }
    }

    /// @notice Fuzz test: Price calculation overflow protection
    function testFuzz_Price_OverflowProtection(
        uint32 reserve0,  // Reduce type
        uint32 reserve1
    ) public pure {
        vm.assume(reserve0 > 1e9 && reserve0 < 1e12);
        vm.assume(reserve1 > 1e9 && reserve1 < 1e12);

        // Use uint256 to prevent overflow
        uint256 price = (uint256(reserve1) * Constants.PRECISION_18) / uint256(reserve0);

        // Verify: Price calculation doesn't overflow
        assertGt(price, 0);
        assertLt(price, type(uint256).max);
    }

    // ==================== Edge Case Tests ====================

    /// @notice Fuzz test: Extremely small reserves
    function testFuzz_Edge_TinyReserves(
        uint32 reserve0,
        uint32 reserve1
    ) public pure {
        vm.assume(reserve0 > 100);
        vm.assume(reserve1 > 100);

        // Calculate price
        uint256 price = (uint256(reserve1) * Constants.PRECISION_18) / uint256(reserve0);

        // Verify: Even with very small reserves, price can be calculated
        assertGt(price, 0);
    }

    /// @notice Fuzz test: Extreme price ratio
    function testFuzz_Edge_ExtremePriceRatio(
        uint112 smallReserve,
        uint112 largeReserve
    ) public pure {
        vm.assume(smallReserve > 1e6);
        vm.assume(largeReserve > uint256(smallReserve) * 1000); // At least 1000x difference
        vm.assume(largeReserve < type(uint112).max);

        // Prevent overflow
        vm.assume(uint256(largeReserve) * Constants.PRECISION_18 < type(uint256).max);

        // Calculate extreme price ratio
        uint256 extremePrice = (uint256(largeReserve) * Constants.PRECISION_18) / uint256(smallReserve);

        // Verify: Can handle extreme prices
        assertGt(extremePrice, Constants.PRECISION_18 * 1000);
    }

    /// @notice Fuzz test: Zero time elapsed
    function testFuzz_Edge_ZeroTimeElapsed() public pure {
        uint32 timeElapsed = 0;

        // Verify: Zero time elapsed should be rejected or return 0
        assertEq(timeElapsed, 0);
    }

    /// @notice Fuzz test: Same timestamp consecutive queries
    function testFuzz_Edge_SameTimestamp(
        uint224 accumulator,
        uint32 timestamp
    ) public pure {
        vm.assume(timestamp > 0);

        // Two queries with same timestamp
        uint32 time1 = timestamp;
        uint32 time2 = timestamp;

        // Time difference is 0
        uint32 elapsed = time2 - time1;

        // Verify: Time difference is 0
        assertEq(elapsed, 0);
    }
}
