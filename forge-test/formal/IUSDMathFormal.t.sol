// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/IUSDMath.sol";
import "../../contracts/libraries/Constants.sol";

/**
 * @title IUSDMath Formal Verification Tests
 * @notice Formal verification for IUSD adjustment factor calculations
 * @dev Uses Halmos for symbolic execution
 */
contract IUSDMathFormalTest is Test {

    /**
     * @notice Adjustment factor should be 1e18 when actual inflation equals target
     * @dev If current/previous equals monthlyGrowthFactor, factor should be 1e18
     */
    function check_adjustmentFactor_unity(
        uint64 previous,
        uint64 monthlyGrowthFactor
    ) public pure {
        vm.assume(previous > 0);
        vm.assume(monthlyGrowthFactor >= 1e18); // At least 1x growth
        vm.assume(monthlyGrowthFactor <= 1.1e18); // At most 10% monthly growth

        // When actual inflation = target, factor should be 1e18
        // current / previous = monthlyGrowthFactor / 1e18
        // So current = previous * monthlyGrowthFactor / 1e18
        uint256 current = (uint256(previous) * monthlyGrowthFactor) / Constants.PRECISION_18;
        vm.assume(current > 0);

        (, uint256 factor) = IUSDMath.adjustmentFactor(current, previous, monthlyGrowthFactor);

        // Factor should be approximately 1e18 (within rounding tolerance)
        assert(factor >= 0.99e18 && factor <= 1.01e18);
    }

    /**
     * @notice Higher actual inflation should result in higher adjustment factor
     * @dev If current1 < current2 with same previous and target, factor1 < factor2
     */
    function check_adjustmentFactor_monotonic(
        uint64 previous,
        uint64 current1,
        uint64 current2,
        uint64 monthlyGrowthFactor
    ) public pure {
        vm.assume(previous > 0);
        vm.assume(current1 > 0);
        vm.assume(current2 > 0);
        vm.assume(current1 <= current2);
        vm.assume(monthlyGrowthFactor >= 1e18);

        (, uint256 factor1) = IUSDMath.adjustmentFactor(current1, previous, monthlyGrowthFactor);
        (, uint256 factor2) = IUSDMath.adjustmentFactor(current2, previous, monthlyGrowthFactor);

        // Higher current PCE (more inflation) means higher adjustment factor
        assert(factor1 <= factor2);
    }

    /**
     * @notice Actual inflation multiplier should be greater than 1e18 when prices increase
     * @dev If current > previous, actual inflation multiplier > 1e18
     */
    function check_inflationMultiplier_increases(
        uint64 previous,
        uint64 current,
        uint64 monthlyGrowthFactor
    ) public pure {
        vm.assume(previous > 0);
        vm.assume(current > previous);
        vm.assume(monthlyGrowthFactor >= 1e18);

        (uint256 actualInflationMultiplier, ) = IUSDMath.adjustmentFactor(current, previous, monthlyGrowthFactor);

        // If current > previous, inflation multiplier > 1e18
        assert(actualInflationMultiplier > Constants.PRECISION_18);
    }

    /**
     * @notice Actual inflation multiplier equals 1e18 when prices unchanged
     * @dev If current == previous, actual inflation multiplier == 1e18
     */
    function check_inflationMultiplier_unity(
        uint64 value,
        uint64 monthlyGrowthFactor
    ) public pure {
        vm.assume(value > 0);
        vm.assume(monthlyGrowthFactor >= 1e18);

        (uint256 actualInflationMultiplier, ) = IUSDMath.adjustmentFactor(value, value, monthlyGrowthFactor);

        // If current == previous, inflation multiplier == 1e18
        assert(actualInflationMultiplier == Constants.PRECISION_18);
    }

    /**
     * @notice Factor should be < 1e18 when actual inflation is below target
     * @dev If actual inflation < target monthly growth, factor < 1e18
     */
    function check_adjustmentFactor_below_target(
        uint64 previous,
        uint64 monthlyGrowthFactor
    ) public pure {
        vm.assume(previous > 0);
        vm.assume(previous <= type(uint64).max / 2); // Prevent overflow
        vm.assume(monthlyGrowthFactor > 1e18); // Must have positive target growth
        vm.assume(monthlyGrowthFactor <= 1.1e18);

        // Current = previous (no inflation), but target expects growth
        uint256 current = previous;

        (, uint256 factor) = IUSDMath.adjustmentFactor(current, previous, monthlyGrowthFactor);

        // Actual inflation (0%) < target inflation, so factor < 1e18
        assert(factor < Constants.PRECISION_18);
    }
}
