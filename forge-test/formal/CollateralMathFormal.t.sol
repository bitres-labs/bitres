// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/CollateralMath.sol";
import "../../contracts/libraries/Constants.sol";

/**
 * @title CollateralMath Formal Verification Tests
 * @notice Formal verification tests using Halmos symbolic execution
 * @dev Tests prefixed with "check_" are symbolic tests for Halmos
 *      Tests prefixed with "test_" are concrete tests for Foundry
 */
contract CollateralMathFormalTest is Test {

    /**
     * @notice Verify collateralValue is monotonic in both inputs
     * @dev If wbtcBalance1 <= wbtcBalance2 and price is same, value1 <= value2
     */
    function check_collateralValue_monotonic_balance(
        uint128 wbtcBalance1,
        uint128 wbtcBalance2,
        uint128 wbtcPrice
    ) public pure {
        // Avoid zero values
        vm.assume(wbtcPrice > 0);
        vm.assume(wbtcBalance1 <= wbtcBalance2);

        uint256 value1 = CollateralMath.collateralValue(wbtcBalance1, wbtcPrice);
        uint256 value2 = CollateralMath.collateralValue(wbtcBalance2, wbtcPrice);

        // Monotonicity: more collateral means higher or equal value
        assert(value1 <= value2);
    }

    /**
     * @notice Verify collateralValue is monotonic in price
     */
    function check_collateralValue_monotonic_price(
        uint128 wbtcBalance,
        uint128 wbtcPrice1,
        uint128 wbtcPrice2
    ) public pure {
        vm.assume(wbtcBalance > 0);
        vm.assume(wbtcPrice1 <= wbtcPrice2);

        uint256 value1 = CollateralMath.collateralValue(wbtcBalance, wbtcPrice1);
        uint256 value2 = CollateralMath.collateralValue(wbtcBalance, wbtcPrice2);

        assert(value1 <= value2);
    }

    /**
     * @notice Verify zero balance always returns zero value
     */
    function check_collateralValue_zero_balance(uint256 wbtcPrice) public pure {
        uint256 value = CollateralMath.collateralValue(0, wbtcPrice);
        assert(value == 0);
    }

    /**
     * @notice Verify zero price always returns zero value
     */
    function check_collateralValue_zero_price(uint256 wbtcBalance) public pure {
        uint256 value = CollateralMath.collateralValue(wbtcBalance, 0);
        assert(value == 0);
    }

    /**
     * @notice Verify liability value is monotonic in BTD supply
     */
    function check_liabilityValue_monotonic(
        uint128 btdSupply1,
        uint128 btdSupply2,
        uint128 stBTDEquivalent,
        uint128 iusdPrice
    ) public pure {
        vm.assume(iusdPrice > 0);
        vm.assume(btdSupply1 <= btdSupply2);

        uint256 value1 = CollateralMath.liabilityValue(btdSupply1, stBTDEquivalent, iusdPrice);
        uint256 value2 = CollateralMath.liabilityValue(btdSupply2, stBTDEquivalent, iusdPrice);

        assert(value1 <= value2);
    }

    /**
     * @notice Verify maxRedeemableUSD is always <= collateral value
     */
    function check_maxRedeemable_bounded(
        uint128 collateralValue_,
        uint128 liabilityValue_
    ) public pure {
        uint256 maxRedeem = CollateralMath.maxRedeemableUSD(collateralValue_, liabilityValue_);

        // maxRedeemable should never exceed collateral
        assert(maxRedeem <= collateralValue_);
    }

    /**
     * @notice Verify maxRedeemableUSD is zero when under-collateralized
     */
    function check_maxRedeemable_zero_undercollateralized(
        uint128 collateralValue_,
        uint128 liabilityValue_
    ) public pure {
        vm.assume(collateralValue_ < liabilityValue_);

        uint256 maxRedeem = CollateralMath.maxRedeemableUSD(collateralValue_, liabilityValue_);
        assert(maxRedeem == 0);
    }

    /**
     * @notice Verify maxRedeemable equals surplus when overcollateralized
     */
    function check_maxRedeemable_equals_surplus(
        uint128 collateralValue_,
        uint128 liabilityValue_
    ) public pure {
        vm.assume(collateralValue_ >= liabilityValue_);

        uint256 maxRedeem = CollateralMath.maxRedeemableUSD(collateralValue_, liabilityValue_);
        uint256 expected = uint256(collateralValue_) - uint256(liabilityValue_);

        assert(maxRedeem == expected);
    }
}
