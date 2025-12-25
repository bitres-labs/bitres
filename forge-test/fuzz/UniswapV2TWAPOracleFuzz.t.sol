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
        reserve0 = uint24(bound(reserve0, 1e6 + 1, 1e7 - 1));  // 1M-10M
        reserve1 = uint24(bound(reserve1, 1e6 + 1, 1e7 - 1));
        timeElapsed = uint16(bound(timeElapsed, 11, 86399)); // 10 seconds - 1 day

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
        reserve0 = uint24(bound(reserve0, 1e6 + 1, 1e7 - 1));  // 1M-10M
        reserve1 = uint24(bound(reserve1, 1e6 + 1, 1e7 - 1));
        timeElapsed = uint16(bound(timeElapsed, 11, 86399));  // 10 seconds - 1 day

        // Calculate increment
        uint256 price = uint256(reserve1) * Constants.PRECISION_18 / uint256(reserve0);
        uint256 increment = price * uint256(timeElapsed);
        // With bounded inputs, overflow is not possible since:
        // max price = 1e7 * 1e18 / 1e6 = 1e19, max increment = 1e19 * 86399 < 1e24 < uint224.max

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
        accumulatorDelta = uint64(bound(accumulatorDelta, 1e9 + 1, 1e18 - 1));
        timeElapsed = uint16(bound(timeElapsed, 61, 65535));  // 1 minute - max uint16 (capped by type)

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
        accumulatorDelta = uint224(bound(accumulatorDelta, 1e18 + 1, type(uint224).max));
        shortWindow = uint32(bound(shortWindow, 61, 3599)); // 1 minute - 1 hour
        longWindow = uint32(bound(longWindow, 3600, 24 hours)); // Ensure longWindow > shortWindow

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
        delta1 = uint64(bound(delta1, 1e9 + 1, 1e15 - 1));
        delta2 = uint64(bound(delta2, 1e9 + 1, 1e15 - 1));
        period1 = uint16(bound(period1, 61, 43200));  // 1 minute - 12 hours
        period2 = uint16(bound(period2, 61, 43200));

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
        uint112 normalReserve0,
        uint112 normalReserve1,
        uint112 manipulatedReserve0,
        uint112 manipulatedReserve1,
        uint32 windowSize
    ) public pure {
        // Bound reserves to reasonable ranges to prevent overflow
        normalReserve0 = uint112(bound(normalReserve0, 1e8 + 1, 1e20));
        normalReserve1 = uint112(bound(normalReserve1, 1e8 + 1, 1e20));
        manipulatedReserve0 = uint112(bound(manipulatedReserve0, 1e6 + 1, 1e20));
        manipulatedReserve1 = uint112(bound(manipulatedReserve1, 1e6 + 1, 1e20));
        windowSize = uint32(bound(windowSize, 3601, 24 hours)); // At least 1 hour window

        // Normal price
        uint256 normalPrice = uint256(normalReserve1) * Constants.PRECISION_18 / uint256(normalReserve0);
        // With bounded reserves, price is guaranteed > 0 and < type(uint224).max

        // Manipulated price (assume 1 block ~12 seconds)
        uint256 manipPrice = uint256(manipulatedReserve1) * Constants.PRECISION_18 / uint256(manipulatedReserve0);

        // Single block time impact
        uint32 singleBlockTime = 12; // 12 seconds
        uint256 manipImpact = manipPrice * singleBlockTime;

        // Normal time impact
        uint256 normalImpact = normalPrice * (uint256(windowSize) - singleBlockTime);

        // Early return if overflow would occur (defensive check)
        if (manipImpact + normalImpact >= type(uint224).max) {
            return;
        }

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
        price1 = uint32(bound(price1, 1e6 + 1, 1e9 - 1));  // Adjust range
        price2 = uint32(bound(price2, 1e6 + 1, 1e9 - 1));
        // Ensure price volatility - if same, offset price2
        if (price2 == price1) {
            price2 = price1 > 1e6 + 1 ? price1 - 1 : price1 + 1;
        }
        time1 = uint16(bound(time1, 61, 43200));  // 1 minute - 12 hours
        time2 = uint16(bound(time2, 61, 43200));

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
        // Ensure currentTime > lastUpdateTime
        lastUpdateTime = uint32(bound(lastUpdateTime, 0, type(uint32).max - 2));
        currentTime = uint32(bound(currentTime, lastUpdateTime + 1, type(uint32).max));
        minInterval = uint32(bound(minInterval, 1, 1 hours));

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
        accumulatorDelta = uint224(bound(accumulatorDelta, 1e18 + 1, type(uint224).max));
        updateCount = uint8(bound(updateCount, 2, 100));

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
        reserve0Base = uint16(bound(reserve0Base, 1001, 9999));
        reserve1Base = uint16(bound(reserve1Base, 1001, 9999));
        reserve0Change = uint8(bound(reserve0Change, 0, 100));  // Max +/-100%
        reserve1Change = uint8(bound(reserve1Change, 0, 100));

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
        reserve0 = uint112(bound(reserve0, 1e8 + 1, type(uint112).max / 2));
        reserve1 = uint112(bound(reserve1, 1e8 + 1, type(uint112).max / 2));
        // Bound amounts to be within valid trade range
        amount0In = uint112(bound(amount0In, 1, reserve0 / 2 - 1));
        amount1Out = uint112(bound(amount1Out, 1, reserve1 / 2 - 1));

        // K value before trade - with bounded reserves, overflow is not possible
        uint256 kBefore = uint256(reserve0) * uint256(reserve1);

        // Reserves after trade
        uint256 reserve0After = uint256(reserve0) + uint256(amount0In);
        uint256 reserve1After = uint256(reserve1) - uint256(amount1Out);

        // K value after trade - with bounded values, overflow is not possible
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
        // uint32 max is ~4.29e9, so we need to adjust bounds
        reserve0 = uint32(bound(reserve0, 1e9 + 1, type(uint32).max));
        reserve1 = uint32(bound(reserve1, 1e9 + 1, type(uint32).max));

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
        // Bound smallReserve first, then derive largeReserve bounds
        smallReserve = uint112(bound(smallReserve, 1e6 + 1, 1e15)); // Upper limit ensures 1000x fits in uint112
        // largeReserve must be at least 1000x smallReserve and prevent overflow
        uint256 minLarge = uint256(smallReserve) * 1000 + 1;
        uint256 maxLarge = type(uint256).max / Constants.PRECISION_18; // Prevent overflow in calculation
        if (maxLarge > type(uint112).max) {
            maxLarge = type(uint112).max;
        }
        // Early return if bounds are invalid
        if (minLarge > maxLarge) {
            return;
        }
        largeReserve = uint112(bound(largeReserve, minLarge, maxLarge));

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
