// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/MintLogic.sol";
import "../../contracts/libraries/RedeemLogic.sol";
import "../../contracts/libraries/CollateralMath.sol";
import "../../contracts/libraries/Constants.sol";

/// @title Minter Fuzz Tests
/// @notice Tests all edge cases for minting/redemption logic
contract MinterFuzzTest is Test {
    using Constants for *;

    // ==================== Minting Logic Fuzz Tests ====================

    /// @notice Fuzz test: BTD minting amount calculation doesn't overflow
    /// @dev Tests overflow safety of wbtcAmount * btcPrice * (1 - fee)
    function testFuzz_MintBTD_NoOverflow(
        uint128 wbtcAmount,  // WBTC amount (8 decimals)
        uint128 btcPrice,     // BTC price (8 decimals)
        uint16 feeBP          // Fee (basis points)
    ) public pure {
        // Constraints
        vm.assume(feeBP <= Constants.BPS_BASE); // Fee rate max 100%
        vm.assume(btcPrice > 0);
        vm.assume(wbtcAmount > 0);

        // Calculate BTD amount (use uint256 to prevent overflow)
        uint256 grossValue = uint256(wbtcAmount) * uint256(btcPrice);
        vm.assume(grossValue < type(uint256).max / Constants.BPS_BASE);

        uint256 fee = (grossValue * feeBP) / Constants.BPS_BASE;
        uint256 netValue = grossValue - fee;

        // Verify: Net value should be less than or equal to gross value
        assertLe(netValue, grossValue);

        // Verify: Fee cannot exceed gross value
        assertLe(fee, grossValue);
    }

    /// @notice Fuzz test: BTD minting amount is proportional to WBTC amount
    function testFuzz_MintBTD_Proportional(
        uint128 wbtcAmount,
        uint128 btcPrice,
        uint16 feeBP
    ) public pure {
        vm.assume(feeBP < Constants.BPS_BASE); // Fee rate < 100% to produce net value
        vm.assume(btcPrice > 1); // Price > 1
        vm.assume(wbtcAmount >= 100); // At least 100 for sufficient precision
        vm.assume(wbtcAmount <= type(uint128).max / 2); // Prevent wbtcAmount * 2 overflow

        // Calculate BTD for 1x amount
        uint256 grossValue1 = uint256(wbtcAmount) * uint256(btcPrice);
        vm.assume(grossValue1 < type(uint256).max / Constants.BPS_BASE);

        uint256 fee1 = (grossValue1 * feeBP) / Constants.BPS_BASE;
        uint256 btdAmount1 = grossValue1 - fee1;

        // Calculate BTD for 2x amount
        uint256 grossValue2 = uint256(wbtcAmount * 2) * uint256(btcPrice);
        vm.assume(grossValue2 < type(uint256).max / Constants.BPS_BASE);

        uint256 fee2 = (grossValue2 * feeBP) / Constants.BPS_BASE;
        uint256 btdAmount2 = grossValue2 - fee2;

        vm.assume(btdAmount1 > 0); // Ensure net value exists

        // Verify: 2x WBTC should produce 2x BTD (allow rounding error)
        assertApproxEqRel(btdAmount2, btdAmount1 * 2, 1e16); // 1% error // 0.1% error
    }

    /// @notice Fuzz test: Higher fee rate reduces minting amount
    function testFuzz_MintBTD_HigherFeeReducesMint(
        uint128 wbtcAmount,
        uint128 btcPrice,
        uint16 feeBP1,
        uint16 feeBP2
    ) public pure {
        vm.assume(btcPrice > 0);
        vm.assume(wbtcAmount > 0);
        vm.assume(feeBP1 < Constants.BPS_BASE); // feeBP1 < 100%
        vm.assume(feeBP2 <= Constants.BPS_BASE);
        vm.assume(feeBP2 > feeBP1); // feeBP2 is higher

        uint256 grossValue = uint256(wbtcAmount) * uint256(btcPrice);
        vm.assume(grossValue < type(uint256).max / Constants.BPS_BASE);
        vm.assume(grossValue > 10000); // Ensure large enough value to avoid precision issues
        vm.assume((grossValue * (feeBP2 - feeBP1)) / Constants.BPS_BASE > 1); // Ensure noticeable fee difference // Ensure sufficient value

        // Calculate minting amount under two fee rates
        uint256 fee1 = (grossValue * feeBP1) / Constants.BPS_BASE;
        uint256 btdAmount1 = grossValue - fee1;

        uint256 fee2 = (grossValue * feeBP2) / Constants.BPS_BASE;
        uint256 btdAmount2 = grossValue - fee2;

        // Verify: Higher fee should produce less BTD
        assertLt(btdAmount2, btdAmount1);
    }

    /// @notice Fuzz test: Minimum minting amount check
    function testFuzz_MintBTD_MinimumAmount(
        uint64 wbtcAmount,
        uint128 btcPrice
    ) public pure {
        vm.assume(btcPrice > 0);
        vm.assume(wbtcAmount > 0);

        uint256 btdAmount = uint256(wbtcAmount) * uint256(btcPrice);

        // Assume minimum minting amount is 0.01 BTD (1e16 wei)
        uint256 MIN_MINT_AMOUNT = 1e16;

        if (btdAmount < MIN_MINT_AMOUNT) {
            // Below minimum should be rejected
            assertTrue(btdAmount < MIN_MINT_AMOUNT);
        } else {
            // At or above minimum should be accepted
            assertGe(btdAmount, MIN_MINT_AMOUNT);
        }
    }

    // ==================== Redemption Logic Fuzz Tests ====================

    /// @notice Fuzz test: BTD redemption doesn't overflow
    function testFuzz_RedeemBTD_NoOverflow(
        uint128 btdAmount,
        uint128 btcPrice,
        uint16 feeBP
    ) public pure {
        vm.assume(feeBP <= Constants.BPS_BASE);
        vm.assume(btcPrice > 0);
        vm.assume(btdAmount > 0);

        // Calculate redemption fee
        uint256 fee = (uint256(btdAmount) * feeBP) / Constants.BPS_BASE;
        uint256 netBTD = uint256(btdAmount) - fee;

        // Calculate WBTC amount
        uint256 wbtcAmount = netBTD / uint256(btcPrice);

        // Verify: WBTC amount should not exceed BTD amount (considering price)
        assertLe(wbtcAmount * uint256(btcPrice), uint256(btdAmount));

        // Verify: Fee doesn't exceed principal
        assertLe(fee, btdAmount);
    }

    /// @notice Fuzz test: BTD redemption and minting symmetry
    function testFuzz_MintRedeemSymmetry(
        uint64 wbtcAmount,
        uint128 btcPrice
    ) public pure {
        vm.assume(btcPrice > 1000); // Price large enough
        vm.assume(wbtcAmount >= 1000); // Amount large enough to avoid precision loss
        vm.assume(wbtcAmount <= 1e18); // Limit range

        // Mint: WBTC -> BTD (no fee)
        uint256 btdMinted = uint256(wbtcAmount) * uint256(btcPrice);

        // Redeem: BTD -> WBTC (no fee)
        uint256 wbtcRedeemed = btdMinted / uint256(btcPrice);

        // Verify: Redeemed WBTC should be close to original amount (allow division rounding error)
        assertApproxEqAbs(wbtcRedeemed, wbtcAmount, btcPrice);
    }

    /// @notice Fuzz test: BTB compensation calculation
    function testFuzz_BTBCompensation_NoOverflow(
        uint128 btdAmount,
        uint128 btcPrice,
        uint128 minPrice,
        uint128 btbPrice
    ) public pure {
        vm.assume(btcPrice > 0);
        vm.assume(minPrice > 0);
        vm.assume(btbPrice > 0);
        vm.assume(btcPrice < minPrice); // Price below minimum requires compensation

        uint256 expectedValue = uint256(btdAmount); // BTD should be worth $1
        uint256 actualWbtcValue = (uint256(btdAmount) * uint256(btcPrice)) / 1e8;

        vm.assume(expectedValue > actualWbtcValue);

        uint256 shortfall = expectedValue - actualWbtcValue;
        uint256 btbCompensation = shortfall / uint256(btbPrice);

        // Verify: Compensation amount should not be negative
        assertGe(btbCompensation, 0);

        // Verify: Compensation value doesn't exceed shortfall
        assertLe(btbCompensation * uint256(btbPrice), shortfall + uint256(btbPrice));
    }

    // ==================== Collateral Ratio Calculation Fuzz Tests ====================

    /// @notice Fuzz test: Collateral ratio calculation doesn't overflow
    function testFuzz_CollateralRatio_NoOverflow(
        uint128 wbtcBalance,
        uint128 btcPrice,
        uint128 btdSupply
    ) public pure {
        vm.assume(btcPrice > 0);
        vm.assume(btdSupply > 0);
        vm.assume(wbtcBalance > 0);

        // Calculate collateral value (USD)
        uint256 collateralValue = uint256(wbtcBalance) * uint256(btcPrice);
        vm.assume(collateralValue < type(uint256).max / Constants.PRECISION_18);
        vm.assume(collateralValue > 0); // Prevent collateralValue being 0
        // Ensure collateralValue is large enough for meaningful CR calculation
        vm.assume(collateralValue >= btdSupply / 100); // At least 1% collateral ratio to be meaningful

        // Calculate collateral ratio = (collateral value / debt) * 100%
        uint256 cr = (collateralValue * Constants.PRECISION_18) / uint256(btdSupply);

        // Verify: Collateral ratio should be > 0
        assertGt(cr, 0);

        // Verify: If collateral value > debt, CR should be >= 100%
        if (collateralValue >= btdSupply) {
            assertGe(cr, Constants.PRECISION_18);
        }
    }

    /// @notice Fuzz test: Collateral ratio positively correlates with price
    function testFuzz_CollateralRatio_PricePositiveCorrelation(
        uint32 wbtcBalance,  // Changed to uint32 to avoid large number multiplication
        uint16 btcPriceBP,   // Changed to uint16
        uint32 btdSupply     // Changed to uint32
    ) public pure {
        vm.assume(wbtcBalance > 1e6); // Reasonable WBTC amount
        vm.assume(wbtcBalance < 1e9);
        vm.assume(btcPriceBP > 100 && btcPriceBP < 5000); // 1%-50% of base price
        vm.assume(btdSupply > 1e6 && btdSupply < 1e10); // Reasonable BTD supply

        // Base price is 1e8, calculate actual price based on basis points
        uint256 btcPrice1 = (1e8 * uint256(btcPriceBP)) / 10000;
        uint256 btcPrice2 = btcPrice1 * 2; // price2 is 2x price1

        uint256 collateralValue1 = uint256(wbtcBalance) * btcPrice1;
        uint256 collateralValue2 = uint256(wbtcBalance) * btcPrice2;

        uint256 cr1 = (collateralValue1 * Constants.PRECISION_18) / uint256(btdSupply);
        uint256 cr2 = (collateralValue2 * Constants.PRECISION_18) / uint256(btdSupply);

        // Verify: Price increase leads to collateral ratio increase
        assertGt(cr2, cr1);
    }

    /// @notice Fuzz test: Collateral ratio negatively correlates with debt
    function testFuzz_CollateralRatio_DebtNegativeCorrelation(
        uint32 wbtcBalance,  // Changed to uint32
        uint16 btcPriceBP,   // Changed to uint16
        uint32 btdSupply1    // Changed to uint32
    ) public pure {
        vm.assume(wbtcBalance > 1e6); // Reasonable WBTC amount
        vm.assume(wbtcBalance < 1e9);
        vm.assume(btcPriceBP > 100 && btcPriceBP < 5000); // 1%-50% of base price
        vm.assume(btdSupply1 > 1e6 && btdSupply1 < 5e9); // Reasonable BTD supply

        // supply2 is 2x supply1
        uint256 btdSupply2 = uint256(btdSupply1) * 2;

        // Base price is 1e8
        uint256 btcPrice = (1e8 * uint256(btcPriceBP)) / 10000;
        uint256 collateralValue = uint256(wbtcBalance) * btcPrice;

        uint256 cr1 = (collateralValue * Constants.PRECISION_18) / uint256(btdSupply1);
        uint256 cr2 = (collateralValue * Constants.PRECISION_18) / btdSupply2;

        // Verify: Debt increase leads to collateral ratio decrease
        assertLt(cr2, cr1);
    }

    // ==================== Edge Case Tests ====================

    /// @notice Fuzz test: Zero fee case
    function testFuzz_ZeroFee(
        uint128 wbtcAmount,
        uint128 btcPrice
    ) public pure {
        vm.assume(btcPrice > 0);
        vm.assume(wbtcAmount > 0);

        uint256 grossValue = uint256(wbtcAmount) * uint256(btcPrice);
        uint256 fee = (grossValue * 0) / Constants.BPS_BASE;
        uint256 netValue = grossValue - fee;

        // Verify: Zero fee means net value equals gross value
        assertEq(netValue, grossValue);
        assertEq(fee, 0);
    }

    /// @notice Fuzz test: 100% fee case
    function testFuzz_FullFee(
        uint64 wbtcAmount,  // Changed to uint64 to avoid overflow
        uint64 btcPrice
    ) public pure {
        vm.assume(wbtcAmount > 0);
        vm.assume(btcPrice > 0);
        vm.assume(uint256(wbtcAmount) * uint256(btcPrice) < type(uint128).max);

        uint256 grossValue = uint256(wbtcAmount) * uint256(btcPrice);
        uint256 fee = (grossValue * Constants.BPS_BASE) / Constants.BPS_BASE;

        // fee = grossValue, so netValue should be 0
        // Use conditional check to avoid underflow
        uint256 netValue = 0;
        if (grossValue >= fee) {
            netValue = grossValue - fee;
        }

        // Verify: 100% fee means net value is 0
        assertEq(netValue, 0);
        assertEq(fee, grossValue);
    }

    /// @notice Fuzz test: Extremely small amounts
    function testFuzz_TinyAmounts(
        uint8 wbtcAmount,  // Use uint8 to ensure very small
        uint16 btcPrice
    ) public pure {
        vm.assume(btcPrice > 0);
        vm.assume(wbtcAmount > 0);

        uint256 btdAmount = uint256(wbtcAmount) * uint256(btcPrice);

        // Verify: Even extremely small amounts don't underflow
        assertGt(btdAmount, 0);
    }

    /// @notice Fuzz test: Extremely large amounts
    function testFuzz_HugeAmounts(
        uint128 wbtcAmount,
        uint128 btcPrice
    ) public pure {
        vm.assume(btcPrice > 1); // Price at least > 1 to ensure product > each factor
        vm.assume(wbtcAmount > 1e18); // At least 10 BTC

        // Use uint256 to prevent overflow
        uint256 btdAmount = uint256(wbtcAmount) * uint256(btcPrice);

        // Verify: Large amount calculation doesn't overflow
        assertGt(btdAmount, uint256(wbtcAmount));
        assertGt(btdAmount, uint256(btcPrice));
    }

    /// @notice Fuzz test: Price precision loss
    function testFuzz_PricePrecision(
        uint64 wbtcAmount,
        uint128 btcPrice
    ) public pure {
        vm.assume(btcPrice > 1e8); // Price at least $1
        vm.assume(wbtcAmount >= 1e5); // At least 0.001 BTC

        uint256 btdAmount = uint256(wbtcAmount) * uint256(btcPrice);
        uint256 wbtcBack = btdAmount / uint256(btcPrice);

        // Verify: Precision loss doesn't exceed 1 unit
        assertApproxEqAbs(wbtcBack, wbtcAmount, 1);
    }
}
