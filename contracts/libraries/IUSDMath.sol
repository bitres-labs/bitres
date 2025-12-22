// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./Constants.sol";

/**
 * @title IUSDMath - IUSD Adjustment Factor Calculation Library
 * @notice Calculate IUSD price adjustment factor based on PCE index
 * @dev Used to adjust IUSD price based on actual inflation rate, making it track real purchasing power
 */
library IUSDMath {
    /**
     * @notice Calculate IUSD adjustment factor
     * @dev Core logic:
     *      1. Calculate actual inflation multiplier = Current PCE / Previous PCE
     *      2. Calculate adjustment factor = Actual Inflation Multiplier / Target Growth Multiplier
     *
     *      Formula:
     *      - Actual Inflation Multiplier = (Current PCE × 1e18) / Previous PCE
     *      - Adjustment Factor = (Actual Inflation Multiplier × 1e18) / Monthly Growth Factor
     *
     *      Adjustment factor meaning:
     *      - factor = 1e18: Actual inflation = Target inflation, no adjustment
     *      - factor > 1e18: Actual inflation > Target inflation, IUSD price adjusted upward
     *      - factor < 1e18: Actual inflation < Target inflation, IUSD price adjusted downward
     *
     *      Example:
     *      Assume target monthly growth rate = 0.2% (monthlyGrowthFactor = 1.002e18)
     *      - Current PCE = 102, Previous PCE = 100
     *      - Actual Inflation Multiplier = 102 × 1e18 / 100 = 1.02e18 (2% growth)
     *      - Adjustment Factor = 1.02e18 × 1e18 / 1.002e18 ≈ 1.018e18
     *      - Indicates actual inflation is higher than target, IUSD price needs 1.8% upward adjustment
     *
     * @param current Current PCE index (any precision, integer recommended)
     * @param previous Previous PCE index (any precision, integer recommended)
     * @param monthlyGrowthFactor Monthly target growth factor (18 decimals, e.g., 1.002e18 for 0.2% monthly growth)
     * @return actualInflationMultiplier Actual inflation multiplier (18 decimals)
     * @return factor Adjustment factor (18 decimals)
     */
    function adjustmentFactor(
        uint256 current,
        uint256 previous,
        uint256 monthlyGrowthFactor
    ) internal pure returns (uint256 actualInflationMultiplier, uint256 factor) {
        require(current > 0 && previous > 0, "Invalid PCE values");
        // Actual inflation multiplier = Current PCE / Previous PCE (18 decimals)
        actualInflationMultiplier = (current * Constants.PRECISION_18) / previous;
        // Optimization: factor = (current * 1e18 / previous) * 1e18 / monthlyGrowthFactor
        //             = (current * 1e36) / (previous * monthlyGrowthFactor)
        // Multiply first, divide later to avoid precision loss
        factor = (current * Constants.PRECISION_18 * Constants.PRECISION_18) / (previous * monthlyGrowthFactor);
    }
}
