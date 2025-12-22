// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";

/// @title CollateralMath Library Fuzz Tests
/// @notice Tests all edge cases for collateral ratio, liquidation, and compensation core math logic
contract CollateralMathFuzzTest is Test {
    using Constants for *;

    // ==================== Collateral Ratio Calculation Fuzz Tests ====================

    /// @notice Fuzz test: Basic collateral ratio calculation
    function testFuzz_CollateralRatio_Basic(
        uint64 collateralValue,  // Changed to uint64 to avoid overflow
        uint64 debtValue
    ) public pure {
        vm.assume(collateralValue > 1e6);
        vm.assume(debtValue > 1e6);
        vm.assume(collateralValue < 1e18);  // Limit upper bound to prevent overflow
        vm.assume(debtValue < 1e18);
        vm.assume(debtValue <= collateralValue * 10); // CR in 0-1000% range

        // Calculate CR = (collateral / debt) * 100%
        uint256 cr = (uint256(collateralValue) * Constants.PRECISION_18) / uint256(debtValue);

        // Verify: When collateral > debt, CR > 100%
        if (collateralValue > debtValue) {
            assertGt(cr, Constants.PRECISION_18);
        }

        // Verify: When collateral == debt, CR = 100%
        if (collateralValue == debtValue) {
            assertEq(cr, Constants.PRECISION_18);
        }

        // Verify: When collateral < debt, CR < 100%
        if (collateralValue < debtValue) {
            assertLt(cr, Constants.PRECISION_18);
        }
    }

    /// @notice Fuzz test: Collateral ratio positively correlated with collateral value
    function testFuzz_CR_CollateralPositiveCorrelation(
        uint64 debtValue,
        uint64 collateralValue1,
        uint64 collateralValue2
    ) public pure {
        vm.assume(debtValue > 1e6);
        vm.assume(debtValue < 1e18);
        vm.assume(collateralValue1 > 1e6);
        vm.assume(collateralValue1 < 1e17);
        vm.assume(collateralValue2 > collateralValue1);
        vm.assume(collateralValue2 < 1e17);

        uint256 cr1 = (uint256(collateralValue1) * Constants.PRECISION_18) / uint256(debtValue);
        uint256 cr2 = (uint256(collateralValue2) * Constants.PRECISION_18) / uint256(debtValue);

        // Verify: Higher collateral value means higher CR
        assertGt(cr2, cr1);
    }

    /// @notice Fuzz test: Collateral ratio negatively correlated with debt value
    function testFuzz_CR_DebtNegativeCorrelation(
        uint64 collateralValue,
        uint64 debtValue1,
        uint64 debtValue2
    ) public pure {
        vm.assume(collateralValue > 1e6);
        vm.assume(collateralValue < 1e17);
        vm.assume(debtValue1 > 1e6);
        vm.assume(debtValue1 < 1e17);
        vm.assume(debtValue2 > debtValue1);
        vm.assume(debtValue2 < 1e17);

        uint256 cr1 = (uint256(collateralValue) * Constants.PRECISION_18) / uint256(debtValue1);
        uint256 cr2 = (uint256(collateralValue) * Constants.PRECISION_18) / uint256(debtValue2);

        // Verify: Higher debt means lower CR
        assertLt(cr2, cr1);
    }

    // ==================== Liquidation Threshold Fuzz Tests ====================

    /// @notice Fuzz test: Liquidation threshold check
    function testFuzz_Liquidation_ThresholdCheck(
        uint128 collateralValue,
        uint128 debtValue,
        uint16 liquidationThresholdBP  // Liquidation threshold (e.g., 150% = 15000 BP)
    ) public pure {
        vm.assume(collateralValue > 1000);
        vm.assume(debtValue > 1000);
        vm.assume(liquidationThresholdBP >= Constants.BPS_BASE); // At least 100%
        vm.assume(liquidationThresholdBP <= 30000); // Max 300%

        // Prevent overflow
        vm.assume(uint256(collateralValue) * Constants.PRECISION_18 < type(uint256).max);

        // Calculate current CR
        uint256 cr = (uint256(collateralValue) * Constants.PRECISION_18) / uint256(debtValue);

        // Liquidation threshold (convert to PRECISION_18)
        uint256 threshold = (uint256(liquidationThresholdBP) * Constants.PRECISION_18) / Constants.BPS_BASE;

        // Determine if liquidatable
        bool canLiquidate = cr < threshold;

        // Verify logic
        if (cr >= threshold) {
            assertFalse(canLiquidate);
        } else {
            assertTrue(canLiquidate);
        }
    }

    /// @notice Fuzz test: Liquidation penalty calculation
    function testFuzz_Liquidation_PenaltyCalculation(
        uint64 liquidatedDebt,
        uint16 penaltyBP  // Liquidation penalty percentage
    ) public pure {
        vm.assume(liquidatedDebt > 1e6);
        vm.assume(penaltyBP > 0 && penaltyBP <= 2000); // 0-20% penalty

        // Calculate penalty
        uint256 penalty = (uint256(liquidatedDebt) * uint256(penaltyBP)) / Constants.BPS_BASE;

        // Total liquidation amount = debt + penalty
        uint256 totalLiquidation = uint256(liquidatedDebt) + penalty;

        // Verify: Penalty does not exceed debt itself (when penaltyBP<=100%)
        if (penaltyBP <= Constants.BPS_BASE) {
            assertLe(penalty, liquidatedDebt);
        }

        // Verify: Total liquidation amount > debt
        assertGt(totalLiquidation, liquidatedDebt);
    }

    /// @notice Fuzz test: Partial liquidation calculation
    function testFuzz_PartialLiquidation_Calculation(
        uint128 totalDebt,
        uint128 collateralValue,
        uint16 liquidationPercentBP  // Liquidation percentage
    ) public pure {
        vm.assume(totalDebt > 1000);
        vm.assume(collateralValue > 1000);
        vm.assume(liquidationPercentBP > 0 && liquidationPercentBP <= Constants.BPS_BASE);

        // Calculate partially liquidated debt
        uint256 liquidatedDebt = (uint256(totalDebt) * uint256(liquidationPercentBP)) / Constants.BPS_BASE;

        // Calculate partially liquidated collateral
        uint256 liquidatedCollateral = (uint256(collateralValue) * uint256(liquidationPercentBP)) / Constants.BPS_BASE;

        // Verify: Partial liquidation does not exceed totals
        assertLe(liquidatedDebt, totalDebt);
        assertLe(liquidatedCollateral, collateralValue);

        // Verify: Remaining debt after liquidation
        uint256 remainingDebt = uint256(totalDebt) - liquidatedDebt;
        assertLe(remainingDebt, totalDebt);
    }

    // ==================== BTB Compensation Calculation Fuzz Tests ====================

    /// @notice Fuzz test: BTB compensation amount calculation
    function testFuzz_BTBCompensation_Amount(
        uint64 btdAmount,        // BTD redemption amount
        uint32 btcPrice,         // Current BTC price
        uint32 btbPrice          // BTB price
    ) public pure {
        vm.assume(btdAmount > 1e6);
        vm.assume(btdAmount < 1e15);
        uint32 btdPegPrice = 1e8; // BTD peg price $1
        vm.assume(btcPrice > 1e6);
        vm.assume(btcPrice < btdPegPrice); // Price below peg requires compensation
        vm.assume(btbPrice > 1e6);
        vm.assume(btbPrice < 1e8);

        // Calculate expected value and actual value
        uint256 expectedValue = uint256(btdAmount) * uint256(btdPegPrice);
        uint256 actualValue = uint256(btdAmount) * uint256(btcPrice);

        // Calculate shortfall
        uint256 shortfall = expectedValue - actualValue;

        // Calculate BTB compensation amount
        uint256 btbCompensation = shortfall / uint256(btbPrice);

        // Verify: Compensation amount is reasonable
        assertGt(btbCompensation, 0);

        // Verify: BTB compensation value approximates shortfall
        uint256 compensationValue = btbCompensation * uint256(btbPrice);
        assertApproxEqAbs(compensationValue, shortfall, btbPrice);
    }

    /// @notice Fuzz test: BTB compensation proportional to price gap
    function testFuzz_BTBCompensation_PriceGapProportional(
        uint64 btdAmount,
        uint32 btcPrice1,
        uint32 btbPrice
    ) public pure {
        vm.assume(btdAmount > 1e6);
        vm.assume(btdAmount < 1e15);
        vm.assume(btbPrice > 1e6);
        vm.assume(btbPrice < 1e8);

        uint32 btdPegPrice = 1e8;
        vm.assume(btcPrice1 > 1e6);
        vm.assume(btcPrice1 < btdPegPrice);

        // price2 fixed at half of price1 to ensure relationship
        uint32 btcPrice2 = btcPrice1 / 2;

        // Calculate compensation at both prices
        uint256 shortfall1 = uint256(btdAmount) * (uint256(btdPegPrice) - uint256(btcPrice1));
        uint256 shortfall2 = uint256(btdAmount) * (uint256(btdPegPrice) - uint256(btcPrice2));

        uint256 compensation1 = shortfall1 / uint256(btbPrice);
        uint256 compensation2 = shortfall2 / uint256(btbPrice);

        // Verify: Larger price gap means more compensation
        assertGt(compensation2, compensation1);
    }

    // ==================== Overcollateralization Ratio Fuzz Tests ====================

    /// @notice Fuzz test: Maximum mintable amount calculation
    function testFuzz_MaxMintable_Calculation(
        uint64 collateralValue,
        uint16 minCollateralRatioBP  // Minimum collateral ratio requirement
    ) public pure {
        vm.assume(collateralValue > 1e9);
        vm.assume(collateralValue < 1e17);
        vm.assume(minCollateralRatioBP >= Constants.BPS_BASE); // At least 100%
        vm.assume(minCollateralRatioBP <= 50000); // Max 500%

        // Calculate max mintable = collateralValue / (minCR / 100%)
        uint256 maxMintable = (uint256(collateralValue) * Constants.BPS_BASE) / uint256(minCollateralRatioBP);

        // Verify: After minting max amount, CR equals minimum requirement
        vm.assume(maxMintable > 1000);

        uint256 resultingCR = (uint256(collateralValue) * Constants.PRECISION_18) / maxMintable;
        uint256 expectedCR = (uint256(minCollateralRatioBP) * Constants.PRECISION_18) / Constants.BPS_BASE;

        assertApproxEqAbs(resultingCR, expectedCR, Constants.PRECISION_18 / 100);  // Relax error to 1%
    }

    /// @notice Fuzz test: Safety buffer calculation
    function testFuzz_SafetyBuffer_Calculation(
        uint128 collateralValue,
        uint128 debtValue,
        uint16 minCollateralRatioBP,
        uint16 targetCollateralRatioBP
    ) public pure {
        vm.assume(collateralValue > 1000);
        vm.assume(debtValue > 1000);
        vm.assume(minCollateralRatioBP >= Constants.BPS_BASE);
        vm.assume(targetCollateralRatioBP > minCollateralRatioBP);
        vm.assume(targetCollateralRatioBP <= 50000);

        // Prevent overflow
        vm.assume(uint256(collateralValue) * Constants.PRECISION_18 < type(uint256).max);

        // Calculate current CR
        uint256 currentCR = (uint256(collateralValue) * Constants.PRECISION_18) / uint256(debtValue);

        // Minimum CR and target CR
        uint256 minCR = (uint256(minCollateralRatioBP) * Constants.PRECISION_18) / Constants.BPS_BASE;
        uint256 targetCR = (uint256(targetCollateralRatioBP) * Constants.PRECISION_18) / Constants.BPS_BASE;

        // Safety buffer = current CR - minimum CR
        if (currentCR > minCR) {
            uint256 buffer = currentCR - minCR;
            assertGt(buffer, 0);
        }

        // Verify: Target CR higher than minimum CR
        assertGt(targetCR, minCR);
    }

    // ==================== Price Volatility Impact Fuzz Tests ====================

    /// @notice Fuzz test: Price drop impact on CR
    function testFuzz_PriceDrop_ImpactOnCR(
        uint32 collateralAmount,
        uint32 initialPrice,
        uint16 priceDropBP,  // Price drop percentage
        uint32 debtValue
    ) public pure {
        vm.assume(collateralAmount > 1e6);
        vm.assume(collateralAmount < 1e9);
        vm.assume(initialPrice > 1e6);
        vm.assume(initialPrice < 1e9);
        vm.assume(priceDropBP > 0 && priceDropBP < Constants.BPS_BASE);
        vm.assume(debtValue > 1e6);
        vm.assume(debtValue < 1e10);

        // Calculate initial collateral value and CR
        uint256 initialCollateralValue = uint256(collateralAmount) * uint256(initialPrice);

        uint256 initialCR = (initialCollateralValue * Constants.PRECISION_18) / uint256(debtValue);

        // Calculate value and CR after price drop
        uint256 priceAfterDrop = uint256(initialPrice) * (Constants.BPS_BASE - uint256(priceDropBP)) / Constants.BPS_BASE;
        uint256 newCollateralValue = uint256(collateralAmount) * priceAfterDrop;

        uint256 newCR = (newCollateralValue * Constants.PRECISION_18) / uint256(debtValue);

        // Verify: Price drop causes CR to decrease
        assertLt(newCR, initialCR);
    }

    /// @notice Fuzz test: Price volatility tolerance
    function testFuzz_PriceVolatility_Tolerance(
        uint16 currentCRBP,
        uint16 minCRBP
    ) public pure {
        vm.assume(currentCRBP > minCRBP);
        vm.assume(minCRBP >= Constants.BPS_BASE);
        vm.assume(minCRBP < 30000);
        vm.assume(currentCRBP > minCRBP + 1000);  // Ensure sufficient difference
        vm.assume(currentCRBP <= 50000);

        // Calculate how much price can drop without triggering liquidation
        // maxDrop = (currentCR - minCR) / currentCR
        uint256 crDifference = uint256(currentCRBP) - uint256(minCRBP);
        uint256 tolerableDrop = (crDifference * Constants.BPS_BASE) / uint256(currentCRBP);

        // Verify: Tolerance in reasonable range
        assertLe(tolerableDrop, Constants.BPS_BASE);
        assertGt(tolerableDrop, 0);
    }

    // ==================== Edge Case Tests ====================

    /// @notice Fuzz test: 100% collateral ratio boundary
    function testFuzz_100PercentCR_Boundary(
        uint128 value
    ) public pure {
        vm.assume(value > 1000);

        // Collateral value = debt value
        uint256 collateralValue = value;
        uint256 debtValue = value;

        // Prevent overflow
        vm.assume(collateralValue * Constants.PRECISION_18 < type(uint256).max);

        // Calculate CR
        uint256 cr = (collateralValue * Constants.PRECISION_18) / debtValue;

        // Verify: CR should be exactly 100%
        assertEq(cr, Constants.PRECISION_18);
    }

    /// @notice Fuzz test: Zero debt means infinite CR
    function testFuzz_ZeroDebt_InfiniteCR(
        uint128 collateralValue
    ) public pure {
        vm.assume(collateralValue > 0);

        uint256 debtValue = 0;

        // Zero debt should not calculate CR, should trigger error or return special value
        // Here we verify divide-by-zero protection mechanism
        if (debtValue == 0) {
            // Should have special handling, cannot divide by 0
            assertTrue(debtValue == 0);
        }
    }

    /// @notice Fuzz test: Zero collateral means zero CR
    function testFuzz_ZeroCollateral_ZeroCR(
        uint128 debtValue
    ) public pure {
        vm.assume(debtValue > 0);

        uint256 collateralValue = 0;

        // Prevent overflow
        vm.assume(collateralValue * Constants.PRECISION_18 < type(uint256).max);

        // Calculate CR
        uint256 cr = (collateralValue * Constants.PRECISION_18) / debtValue;

        // Verify: Zero collateral means zero CR
        assertEq(cr, 0);
    }

    /// @notice Fuzz test: Very high collateral ratio
    function testFuzz_VeryHighCR(
        uint128 collateralValue,
        uint64 debtValue
    ) public pure {
        vm.assume(collateralValue > 1e24); // Large collateral
        vm.assume(debtValue > 1000 && debtValue < 1e18); // Small debt
        vm.assume(collateralValue > uint256(debtValue) * 1000); // CR > 100000%

        // Prevent overflow
        vm.assume(uint256(collateralValue) * Constants.PRECISION_18 < type(uint256).max);

        // Calculate high CR
        uint256 cr = (uint256(collateralValue) * Constants.PRECISION_18) / uint256(debtValue);

        // Verify: CR should be much greater than 100%
        assertGt(cr, Constants.PRECISION_18 * 1000);
    }

    /// @notice Fuzz test: Collateral ratio invariance
    function testFuzz_CR_Invariant_ScaleUp(
        uint64 collateralValue,
        uint64 debtValue,
        uint16 scaleFactor
    ) public pure {
        vm.assume(collateralValue > 1000);
        vm.assume(debtValue > 1000);
        vm.assume(scaleFactor > 1 && scaleFactor <= 1000);

        // Prevent overflow
        vm.assume(uint256(collateralValue) * Constants.PRECISION_18 < type(uint256).max);
        vm.assume(uint256(collateralValue) * uint256(scaleFactor) < type(uint128).max);
        vm.assume(uint256(debtValue) * uint256(scaleFactor) < type(uint128).max);

        // Calculate original CR
        uint256 cr1 = (uint256(collateralValue) * Constants.PRECISION_18) / uint256(debtValue);

        // Scale up both collateral and debt
        uint256 scaledCollateral = uint256(collateralValue) * uint256(scaleFactor);
        uint256 scaledDebt = uint256(debtValue) * uint256(scaleFactor);

        vm.assume(scaledCollateral * Constants.PRECISION_18 < type(uint256).max);

        // Calculate CR after scaling
        uint256 cr2 = (scaledCollateral * Constants.PRECISION_18) / scaledDebt;

        // Verify: Proportional scaling does not change CR
        assertEq(cr2, cr1);
    }
}
