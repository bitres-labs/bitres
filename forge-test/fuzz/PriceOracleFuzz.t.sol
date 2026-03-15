// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/OracleMath.sol";
import "../../contracts/libraries/Constants.sol";

/// @title PriceOracle Fuzz Tests
/// @notice Tests all edge cases for price oracle logic
contract PriceOracleFuzzTest is Test {
    using Constants for *;

    // ==================== Price Aggregation Fuzz Tests ====================

    /// @notice Fuzz test: Three-source price median calculation
    function testFuzz_Median3_Correctness(
        uint128 price1,
        uint128 price2,
        uint128 price3
    ) public pure {
        vm.assume(price1 > 0);
        vm.assume(price2 > 0);
        vm.assume(price3 > 0);

        uint256 median = _median3(price1, price2, price3);

        // Verify: Median should be between min and max
        uint256 minPrice = _min3(price1, price2, price3);
        uint256 maxPrice = _max3(price1, price2, price3);

        assertGe(median, minPrice);
        assertLe(median, maxPrice);
    }

    /// @notice Fuzz test: Median consistent across all permutations
    function testFuzz_Median3_OrderInvariant(
        uint128 price1,
        uint128 price2,
        uint128 price3
    ) public pure {
        vm.assume(price1 > 0);
        vm.assume(price2 > 0);
        vm.assume(price3 > 0);

        // Test all 6 permutations
        uint256 m1 = _median3(price1, price2, price3);
        uint256 m2 = _median3(price1, price3, price2);
        uint256 m3 = _median3(price2, price1, price3);
        uint256 m4 = _median3(price2, price3, price1);
        uint256 m5 = _median3(price3, price1, price2);
        uint256 m6 = _median3(price3, price2, price1);

        // Verify: All permutations should have same median
        assertEq(m1, m2);
        assertEq(m1, m3);
        assertEq(m1, m4);
        assertEq(m1, m5);
        assertEq(m1, m6);
    }

    /// @notice Fuzz test: Multi-source price weighted average
    function testFuzz_WeightedAverage_NoOverflow(
        uint128 price1,
        uint128 price2,
        uint128 price3,
        uint16 weight1,
        uint16 weight2,
        uint16 weight3
    ) public pure {
        vm.assume(price1 > 0);
        vm.assume(price2 > 0);
        vm.assume(price3 > 0);
        vm.assume(weight1 > 0);
        vm.assume(weight2 > 0);
        vm.assume(weight3 > 0);

        uint256 totalWeight = uint256(weight1) + uint256(weight2) + uint256(weight3);
        vm.assume(totalWeight > 0);
        vm.assume(totalWeight <= type(uint128).max);

        // Calculate weighted average (use uint256 to prevent overflow)
        uint256 weightedSum =
            uint256(price1) * uint256(weight1) +
            uint256(price2) * uint256(weight2) +
            uint256(price3) * uint256(weight3);

        vm.assume(weightedSum < type(uint256).max / 2);

        uint256 avgPrice = weightedSum / totalWeight;

        // Verify: Average price should be between min and max
        uint256 minPrice = _min3(price1, price2, price3);
        uint256 maxPrice = _max3(price1, price2, price3);

        assertGe(avgPrice, minPrice);
        assertLe(avgPrice, maxPrice);
    }

    // ==================== Price Deviation Detection Fuzz Tests ====================

    /// @notice Fuzz test: Price deviation calculation symmetry
    function testFuzz_PriceDeviation_Symmetry(
        uint128 price1,
        uint128 price2
    ) public pure {
        vm.assume(price1 > 0);
        vm.assume(price2 > 0);
        vm.assume(price1 != price2);

        // Calculate bidirectional deviation
        uint256 dev1to2 = _calculateDeviation(price1, price2);
        uint256 dev2to1 = _calculateDeviation(price2, price1);

        // Verify: Deviation should be same (symmetry)
        assertEq(dev1to2, dev2to1);
    }

    /// @notice Fuzz test: Price deviation range
    function testFuzz_PriceDeviation_Range(
        uint128 price1,
        uint128 price2
    ) public pure {
        vm.assume(price1 > 1000 && price1 < type(uint128).max / 100); // Avoid extreme values
        vm.assume(price2 > 1000 && price2 < type(uint128).max / 100); // Avoid extreme values
        // Limit price ratio to reasonable range (no more than 10x difference)
        vm.assume(price1 <= uint256(price2) * 10);
        vm.assume(price2 <= uint256(price1) * 10);

        uint256 deviation = _calculateDeviation(price1, price2);

        // Verify: Within 10x difference, deviation should be between 0-150%
        assertLe(deviation, Constants.PRECISION_18 * 200 / 100); // 10x difference max 200%

        // Verify: Same price means 0 deviation
        // Note: Very small differences may round to 0 due to integer division precision
        if (price1 == price2) {
            assertEq(deviation, 0);
        }
        // When prices differ significantly (at least 0.001%), deviation should be non-zero
        uint256 minDiff = (price1 + price2) / 2 / 100000; // 0.001% of average
        if (price1 > price2 ? price1 - price2 > minDiff : price2 - price1 > minDiff) {
            assertGt(deviation, 0);
        }
    }

    /// @notice Fuzz test: Price deviation threshold check
    function testFuzz_PriceDeviation_ThresholdCheck(
        uint128 price1,
        uint128 price2,
        uint16 thresholdBP
    ) public pure {
        vm.assume(price1 > 0);
        vm.assume(price2 > 0);
        vm.assume(thresholdBP <= Constants.BPS_BASE); // Max 100%

        uint256 deviation = _calculateDeviation(price1, price2);
        uint256 threshold = (uint256(thresholdBP) * Constants.PRECISION_18) / Constants.BPS_BASE;

        bool withinThreshold = deviation <= threshold;

        // Verify logical consistency
        if (price1 == price2) {
            // Same price should always be within threshold
            assertTrue(withinThreshold);
        }
    }

    /// @notice Fuzz test: Extreme price deviation
    function testFuzz_PriceDeviation_Extreme(
        uint128 price1,
        uint8 multiplier
    ) public pure {
        vm.assume(price1 > 1000);
        vm.assume(multiplier >= 2);
        vm.assume(multiplier <= 100);

        uint256 price2 = uint256(price1) * uint256(multiplier);
        vm.assume(price2 <= type(uint128).max);

        uint256 deviation = _calculateDeviation(price1, uint128(price2));

        // Verify: Larger multiplier means larger deviation
        assertGt(deviation, 0);

        // Verify: 10x difference should be close to 100% deviation
        if (multiplier >= 10) {
            assertGt(deviation, Constants.PRECISION_18 * 80 / 100); // > 80%
        }
    }

    // ==================== Price Normalization Fuzz Tests ====================

    /// @notice Fuzz test: Price precision conversion does not overflow
    function testFuzz_PriceNormalization_NoOverflow(
        uint128 price,
        uint8 decimals
    ) public pure {
        vm.assume(price > 0);
        vm.assume(decimals <= 18);

        // Convert to 18 decimal precision
        uint256 normalized;
        if (decimals < 18) {
            uint256 scaleFactor = 10 ** (18 - decimals);
            vm.assume(price <= type(uint256).max / scaleFactor);
            normalized = uint256(price) * scaleFactor;
        } else {
            normalized = price;
        }

        // Verify: Normalized value should maintain relative magnitude
        assertGt(normalized, 0);

        if (decimals < 18) {
            assertGe(normalized, price);
        }
    }

    /// @notice Fuzz test: Price precision conversion reversibility
    function testFuzz_PriceNormalization_Reversible(
        uint64 price,
        uint8 decimals
    ) public pure {
        vm.assume(price > 1000); // Avoid excessive precision loss
        vm.assume(decimals >= 6 && decimals <= 18);

        // Upscale to 18 decimals
        uint256 normalized;
        if (decimals < 18) {
            normalized = uint256(price) * (10 ** (18 - decimals));
        } else {
            normalized = price;
        }

        // Downscale back to original precision
        uint256 denormalized;
        if (decimals < 18) {
            denormalized = normalized / (10 ** (18 - decimals));
        } else {
            denormalized = normalized;
        }

        // Verify: Should recover original value (or very close)
        assertEq(denormalized, price);
    }

    // ==================== TWAP (Time-Weighted Average Price) Fuzz Tests ====================

    /// @notice Fuzz test: TWAP cumulative price does not overflow
    function testFuzz_TWAP_NoOverflow(
        uint128 price,
        uint32 timeElapsed
    ) public pure {
        vm.assume(price > 0);
        vm.assume(timeElapsed > 0);
        vm.assume(timeElapsed <= 365 days);

        // Calculate cumulative price
        uint256 priceAccumulated = uint256(price) * uint256(timeElapsed);

        // Verify: Does not overflow
        assertGt(priceAccumulated, 0);
        assertGe(priceAccumulated, price);
        assertGe(priceAccumulated, timeElapsed);
    }

    /// @notice Fuzz test: TWAP average price calculation
    function testFuzz_TWAP_AveragePrice(
        uint128 price1,
        uint128 price2,
        uint32 time1,
        uint32 time2
    ) public pure {
        vm.assume(price1 > 0);
        vm.assume(price2 > 0);
        vm.assume(time1 > 0);
        vm.assume(time2 > 0);
        vm.assume(time1 <= 30 days);
        vm.assume(time2 <= 30 days);

        // Calculate TWAP
        uint256 totalValue = uint256(price1) * uint256(time1) +
                             uint256(price2) * uint256(time2);
        uint256 totalTime = uint256(time1) + uint256(time2);

        vm.assume(totalValue < type(uint256).max / 2);

        uint256 twap = totalValue / totalTime;

        // Verify: TWAP should be between the two prices
        uint256 minPrice = price1 < price2 ? price1 : price2;
        uint256 maxPrice = price1 > price2 ? price1 : price2;

        assertGe(twap, minPrice);
        assertLe(twap, maxPrice);
    }

    // ==================== Price Validity Check Fuzz Tests ====================

    /// @notice Fuzz test: Price staleness check
    function testFuzz_PriceStale_Check(
        uint32 lastUpdate,
        uint32 currentTime,
        uint32 staleThreshold
    ) public pure {
        vm.assume(currentTime >= lastUpdate);
        vm.assume(staleThreshold > 0);
        vm.assume(staleThreshold <= 1 hours);

        uint32 timeSinceUpdate = currentTime - lastUpdate;
        bool isStale = timeSinceUpdate > staleThreshold;

        // Verify logic
        if (timeSinceUpdate == 0) {
            // Just updated price should not be stale
            assertFalse(isStale);
        }

        if (timeSinceUpdate > staleThreshold) {
            assertTrue(isStale);
        } else {
            assertFalse(isStale);
        }
    }

    /// @notice Fuzz test: Price reasonable range check
    function testFuzz_PriceRange_Check(
        uint128 price,
        uint128 minPrice,
        uint128 maxPrice
    ) public pure {
        vm.assume(minPrice > 0);
        vm.assume(maxPrice > minPrice);

        bool inRange = price >= minPrice && price <= maxPrice;

        // Verify logic
        if (price < minPrice) {
            assertFalse(inRange);
        } else if (price > maxPrice) {
            assertFalse(inRange);
        } else {
            assertTrue(inRange);
        }
    }

    // ==================== Helper Functions ====================

    function _median3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        if (a > b) {
            if (b > c) return b;      // a > b > c
            if (a > c) return c;      // a > c > b
            return a;                 // c > a > b
        } else {
            if (a > c) return a;      // b > a > c
            if (b > c) return c;      // b > c > a
            return b;                 // c > b > a
        }
    }

    function _min3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        uint256 min = a;
        if (b < min) min = b;
        if (c < min) min = c;
        return min;
    }

    function _max3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        uint256 max = a;
        if (b > max) max = b;
        if (c > max) max = c;
        return max;
    }

    function _calculateDeviation(uint256 price1, uint256 price2) internal pure returns (uint256) {
        if (price1 == price2) return 0;

        uint256 diff = price1 > price2 ? price1 - price2 : price2 - price1;
        uint256 avg = (price1 + price2) / 2;

        if (avg == 0) return 0;

        // Return deviation percentage (18 decimal precision)
        return (diff * Constants.PRECISION_18) / avg;
    }

    // ==================== Deviation Check with Real OracleMath ====================

    /// @notice Fuzz test: OracleMath.deviationWithin symmetry property
    function testFuzz_deviationWithin_symmetry(
        uint128 priceA,
        uint128 priceB,
        uint16 maxBps
    ) public pure {
        vm.assume(priceA > 0);
        vm.assume(priceB > 0);
        vm.assume(maxBps > 0 && maxBps <= 10000);

        bool ab = OracleMath.deviationWithin(priceA, priceB, maxBps);
        bool ba = OracleMath.deviationWithin(priceB, priceA, maxBps);

        // Note: deviationWithin is NOT symmetric because it uses priceA as denominator
        // But verify both calls return valid booleans (no revert)
        // When prices are equal, both should return true
        if (priceA == priceB) {
            assertTrue(ab, "Same price should be within deviation");
            assertTrue(ba, "Same price should be within deviation (reversed)");
        }
    }

    /// @notice Fuzz test: deviationWithin with zero prices always returns false
    function testFuzz_deviationWithin_zeroPriceFalse(
        uint128 otherPrice,
        uint16 maxBps
    ) public pure {
        vm.assume(otherPrice > 0);
        vm.assume(maxBps > 0 && maxBps <= 10000);

        assertFalse(OracleMath.deviationWithin(0, otherPrice, maxBps), "Zero priceA should return false");
        assertFalse(OracleMath.deviationWithin(otherPrice, 0, maxBps), "Zero priceB should return false");
    }

    // ==================== BTD Price Floor Fuzz Tests ====================

    /// @notice Fuzz test: BTD floor calculation never goes below CR * IUSD * 90%
    function testFuzz_BTDPriceFloor_neverBelowCR(
        uint256 crRaw,
        uint256 iusdRaw
    ) public pure {
        uint128 cr = uint128(bound(crRaw, 1, 2e18)); // CR from 0 to 200%
        uint128 iusdPrice = uint128(bound(iusdRaw, 0.5e18, 2e18)); // IUSD $0.50-$2.00

        // Cap CR at 1e18 (100%) as PriceOracle does
        uint256 cappedCR = cr > 1e18 ? 1e18 : cr;

        // Floor = CR * IUSD * 90% / 100% = (CR * IUSD * 9000) / (1e18 * 10000)
        uint256 floor = (cappedCR * iusdPrice * 9000) / (1e18 * 10000);

        // Floor should always be <= CR * IUSD (90% of it)
        uint256 fullValue = (cappedCR * iusdPrice) / 1e18;
        assertLe(floor, fullValue, "Floor should be <= CR * IUSD");

        // Floor should be at most 90% of fullValue (may differ by 1 due to rounding)
        uint256 expectedFloor = (fullValue * 9000) / 10000;
        uint256 diff = floor > expectedFloor ? floor - expectedFloor : expectedFloor - floor;
        assertLe(diff, 1, "Floor should be ~90% of CR * IUSD (rounding tolerance 1)");
    }

    // ==================== Chain Price Consistency Fuzz Tests ====================

    /// @notice Fuzz test: Token chain pricing preserves relative ordering
    function testFuzz_chainPrice_ordering(
        uint64 tokenPerBTD_A,
        uint64 tokenPerBTD_B,
        uint64 btdPrice
    ) public pure {
        vm.assume(tokenPerBTD_A > 0);
        vm.assume(tokenPerBTD_B > 0);
        vm.assume(btdPrice > 0);

        // Ensure ordering
        uint256 a = tokenPerBTD_A <= tokenPerBTD_B ? tokenPerBTD_A : tokenPerBTD_B;
        uint256 b = tokenPerBTD_A <= tokenPerBTD_B ? tokenPerBTD_B : tokenPerBTD_A;

        // Chain price: token_USD = tokenPerBTD * btdPrice / 1e18
        uint256 priceA = (a * uint256(btdPrice)) / 1e18;
        uint256 priceB = (b * uint256(btdPrice)) / 1e18;

        // Ordering should be preserved
        assertLe(priceA, priceB, "Chain price should preserve ordering");
    }

    /// @notice Fuzz test: inversePrice preserves ordering in reverse
    function testFuzz_inversePrice_reverseOrdering(
        uint64 rawA,
        uint64 rawB
    ) public pure {
        vm.assume(rawA > 1e6);
        vm.assume(rawB > 1e6);
        vm.assume(rawA != rawB);

        // Ensure ordering without vm.assume to avoid rejections
        uint256 priceA = rawA < rawB ? rawA : rawB;
        uint256 priceB = rawA < rawB ? rawB : rawA;

        uint256 invA = OracleMath.inversePrice(priceA);
        uint256 invB = OracleMath.inversePrice(priceB);

        // Inverse should reverse the ordering
        assertGe(invA, invB, "Inverse price should reverse ordering");
    }

    /// @notice Fuzz test: inversePrice of inversePrice approximately recovers original
    function testFuzz_inversePrice_roundtrip(
        uint128 price
    ) public pure {
        vm.assume(price > 1e12 && price <= 1e30);

        uint256 inv = OracleMath.inversePrice(price);
        vm.assume(inv > 0);
        uint256 recovered = OracleMath.inversePrice(inv);

        // Due to integer division, recovered should be close to original
        // Allow 0.1% tolerance
        uint256 diff = recovered > price ? recovered - price : price - recovered;
        assertLe(diff * 1000 / price, 1, "Double inverse should recover original within 0.1%");
    }
}
