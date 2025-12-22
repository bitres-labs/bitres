// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./OracleMath.sol";

/**
 * @title PriceBlend - Price Blending and Deviation Validation Library
 * @notice Provides median calculation and deviation verification for multiple price sources
 * @dev Used for oracle price aggregation and anomaly detection
 */
library PriceBlend {
    /**
     * @notice Calculate median of three prices
     * @dev Uses sorting network algorithm:
     *      1. Compare a and b, swap to make a <= b
     *      2. Compare b and c, swap to make b <= c
     *      3. Compare a and b again, swap to make a <= b
     *      Final order: a <= b <= c, median is b
     *
     *      Advantages:
     *      - Fixed 3 comparisons, no loops, low gas cost
     *      - Resistant to extreme values (more robust than average)
     *
     *      Use cases:
     *      - Multi-oracle price aggregation (Chainlink + Uniswap + Curve)
     *      - Anomalous price filtering
     *
     *      Examples:
     *      median3(100, 200, 150) = 150
     *      median3(100, 200, 1000) = 200 (filters out anomaly 1000)
     *
     * @param a Price 1 (18 decimals)
     * @param b Price 2 (18 decimals)
     * @param c Price 3 (18 decimals)
     * @return Median price (18 decimals)
     */
    function median3(uint256 a, uint256 b, uint256 c) internal pure returns (uint256) {
        if (a > b) (a, b) = (b, a);
        if (b > c) (b, c) = (c, b);
        if (a > b) (a, b) = (b, a);
        return b;
    }

    /**
     * @notice Validate that spot price deviation from reference price is within allowed range
     * @dev Use cases:
     *      - Validate consistency between AMM spot price and Chainlink oracle price
     *      - Prevent price manipulation attacks
     *      - Ensure reliability of multi-source prices
     *
     *      Security mechanism:
     *      Transaction will revert with error if deviation is too large
     *
     *      Example:
     *      - spot = 65000e18, ref = 64000e18, maxBps = 200 (2%)
     *      - Deviation = 1000 / 64000 ≈ 1.56%
     *      - 1.56% < 2%, validation passes
     *
     * @param spot Spot price (18 decimals)
     * @param ref Reference price (18 decimals)
     * @param maxBps Maximum allowed deviation (basis points, 200 = 2%)
     */
    function validateSpotAgainstRef(uint256 spot, uint256 ref, uint256 maxBps) internal pure {
        require(OracleMath.deviationWithin(spot, ref, maxBps), "Price deviation too large");
    }

    /**
     * @notice Multi-source price blending: Calculate median and validate all prices are within allowed deviation
     * @dev Complete multi-source price aggregation flow:
     *      1. Sort all prices
     *      2. Calculate median
     *      3. Validate all prices deviate from median by <= maxBps
     *      4. If any price deviates too much, the entire call fails
     *
     *      Use cases:
     *      - Aggregation of 5 or more oracle sources
     *      - Scenarios requiring strict validation of all source data consistency
     *      - Preventing single source anomaly from affecting final price
     *
     *      Algorithm:
     *      - Uses insertion sort (gas optimized for small arrays)
     *      - Median takes middle value (odd) or average of two middle values (even)
     *      - Comprehensive deviation check
     *
     *      Example:
     *      prices = [100e18, 102e18, 101e18, 99e18, 103e18]
     *      maxBps = 300 (3%)
     *      After sorting: [99, 100, 101, 102, 103]
     *      Median: 101
     *      Validation: All prices deviate from 101 by <= 3% ✓
     *      Returns: 101e18
     *
     * @param prices Price array (18 decimals), at least 2 elements
     * @param maxBps Maximum allowed deviation (basis points, e.g., 300=3%)
     * @return Median price (18 decimals)
     */
    function blendMultiSource(
        uint256[] memory prices,
        uint256 maxBps
    ) internal pure returns (uint256) {
        uint256 len = prices.length;
        require(len >= 2, "Need at least 2 prices");

        // Insertion sort (gas optimized for small arrays of 5-10 elements)
        for (uint256 i = 1; i < len; i++) {
            uint256 key = prices[i];
            uint256 j = i;
            while (j > 0 && prices[j - 1] > key) {
                prices[j] = prices[j - 1];
                j--;
            }
            prices[j] = key;
        }

        // Calculate median
        uint256 median;
        if (len % 2 == 1) {
            // Odd: Take middle value
            median = prices[len / 2];
        } else {
            // Even: Take average of two middle values
            uint256 mid1 = prices[len / 2 - 1];
            uint256 mid2 = prices[len / 2];
            median = (mid1 + mid2) / 2;
        }

        // Validate all prices deviate from median within allowed range
        for (uint256 i = 0; i < len; i++) {
            require(
                OracleMath.deviationWithin(prices[i], median, maxBps),
                "Price source deviation too large"
            );
        }

        return median;
    }

    /**
     * @notice Validate that all prices are within allowed deviation from each other
     * @dev More strict validation: Checks deviation between any two prices, not just from median
     *
     *      Use cases:
     *      - Extremely high security requirement scenarios
     *      - Need to ensure high consistency across all source data
     *      - Used for early warning and anomaly detection
     *
     *      Algorithm:
     *      - O(n^2) complexity, only suitable for small number of price sources (<=5)
     *      - Checks all price pairs
     *
     *      Example:
     *      prices = [100e18, 101e18, 102e18]
     *      maxBps = 200 (2%)
     *      Checks: |100-101|/100≈1%, |100-102|/100=2%, |101-102|/101≈1%
     *      Result: All deviations <= 2% ✓
     *
     * @param prices Price array (18 decimals), at least 2 elements
     * @param maxBps Maximum allowed deviation (basis points, e.g., 200=2%)
     * @return Whether all prices are within allowed deviation
     */
    function validateAllWithinBounds(
        uint256[] memory prices,
        uint256 maxBps
    ) internal pure returns (bool) {
        uint256 len = prices.length;
        require(len >= 2, "Need at least 2 prices");

        // Check all price pairs
        for (uint256 i = 0; i < len; i++) {
            for (uint256 j = i + 1; j < len; j++) {
                if (!OracleMath.deviationWithin(prices[i], prices[j], maxBps)) {
                    return false;
                }
            }
        }

        return true;
    }
}
