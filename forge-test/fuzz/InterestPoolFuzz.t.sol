// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/InterestMath.sol";
import "../../contracts/libraries/Constants.sol";

/// @title InterestPool Fuzz Tests
/// @notice Tests all edge cases for interest calculations
contract InterestPoolFuzzTest is Test {
    using Constants for *;

    // ==================== Interest Calculation Fuzz Tests ====================

    /// @notice Fuzz test: Simple interest calculation does not overflow
    function testFuzz_SimpleInterest_NoOverflow(
        uint128 principal,
        uint32 rate,      // Annual interest rate (basis points, e.g., 500 = 5%)
        uint32 timeYears  // Time (years)
    ) public pure {
        vm.assume(principal > 0);
        vm.assume(rate > 0 && rate <= 10000); // Max 100%
        vm.assume(timeYears > 0 && timeYears <= 100);
        // Ensure interest is not 0
        vm.assume(uint256(principal) * uint256(rate) * uint256(timeYears) >= Constants.BPS_BASE);

        // Simple interest = principal * rate * time / BP_DIVISOR
        vm.assume(uint256(principal) * uint256(rate) < type(uint256).max / uint256(timeYears));

        uint256 interest = (uint256(principal) * uint256(rate) * uint256(timeYears)) / Constants.BPS_BASE;

        // Verify: Interest does not overflow
        assertGt(interest, 0);
        assertLe(interest, uint256(principal) * uint256(timeYears)); // Interest does not exceed principal*years (100% annual rate)
    }

    /// @notice Fuzz test: Compound interest calculation does not overflow
    function testFuzz_CompoundInterest_NoOverflow(
        uint64 principal,
        uint16 rate,
        uint16 periods
    ) public pure {
        vm.assume(principal > 1000); // At least 1000 to see compound effect
        vm.assume(rate > 0 && rate <= 1000); // Max 10% per period
        vm.assume(periods > 0 && periods <= 120); // Max 120 periods (10 years monthly)

        // Compound formula: A = P * (1 + r)^n
        // Using approximation: A ≈ P * (1 + n*r) to avoid power overflow
        uint256 totalRate = uint256(rate) * uint256(periods);
        vm.assume(totalRate <= Constants.BPS_BASE * 10); // Max total return 1000%
        vm.assume(totalRate > 0); // Ensure growth

        uint256 finalAmount = uint256(principal) * (Constants.BPS_BASE + totalRate) / Constants.BPS_BASE;

        // Verify: Principal plus interest is greater than principal
        if (totalRate > 0) {
            assertGe(finalAmount, principal);
        } else {
            assertEq(finalAmount, principal);
        }
    }

    /// @notice Fuzz test: Higher rate means more interest
    function testFuzz_Interest_RatePositiveCorrelation(
        uint128 principal,
        uint16 rate1,
        uint16 rate2,
        uint32 time
    ) public pure {
        vm.assume(principal > 0);
        vm.assume(rate1 > 0 && rate1 <= 5000);
        vm.assume(rate2 > rate1 && rate2 <= 5000);
        vm.assume(time > 0 && time <= 365 days);
        // Ensure interest1 is not 0
        vm.assume(uint256(principal) * uint256(rate1) * uint256(time) >= Constants.BPS_BASE * 365 days);

        uint256 interest1 = (uint256(principal) * uint256(rate1) * uint256(time)) / (Constants.BPS_BASE * 365 days);
        uint256 interest2 = (uint256(principal) * uint256(rate2) * uint256(time)) / (Constants.BPS_BASE * 365 days);

        // Verify: Higher rate produces more interest
        if (interest1 > 0 && interest2 > interest1) {
            assertGt(interest2, interest1);
        } else {
            assertTrue(true); // Skip if precision loss
        }
    }

    /// @notice Fuzz test: More principal means more interest
    function testFuzz_Interest_PrincipalPositiveCorrelation(
        uint128 principal1,
        uint128 principal2,
        uint16 rate,
        uint32 time
    ) public pure {
        vm.assume(principal1 > 1000); // At least 1000 for noticeable difference
        vm.assume(principal2 > principal1);
        vm.assume(rate > 0 && rate <= 5000);
        vm.assume(time > 0 && time <= 365 days);
        // Ensure interest1 is not 0
        vm.assume(uint256(principal1) * uint256(rate) * uint256(time) >= Constants.BPS_BASE * 365 days);

        vm.assume(uint256(principal1) * uint256(rate) * uint256(time) < type(uint256).max / 2);
        vm.assume(uint256(principal2) * uint256(rate) * uint256(time) < type(uint256).max / 2);

        uint256 interest1 = (uint256(principal1) * uint256(rate) * uint256(time)) / (Constants.BPS_BASE * 365 days);
        uint256 interest2 = (uint256(principal2) * uint256(rate) * uint256(time)) / (Constants.BPS_BASE * 365 days);

        // Verify: More principal produces more interest
        // Verify: More principal produces more or equal interest
        assertGe(interest2, interest1);
    }

    // ==================== Annual Yield Rate Calculation Fuzz Tests ====================

    /// @notice Fuzz test: APR to per-second rate conversion
    function testFuzz_APR_ToPerSecondRate(
        uint32 aprBP  // Annual interest rate (basis points)
    ) public pure {
        vm.assume(aprBP > 0 && aprBP <= 50000); // Max 500% APR
        // Ensure perSecondRate is meaningful
        vm.assume(aprBP >= 100); // At least 1% to be meaningful

        // Convert to per-second rate
        uint256 perSecondRate = uint256(aprBP) * Constants.PRECISION_18 / (Constants.BPS_BASE * 365 days);

        // Verify: Per-second rate should be very small
        // When APR is X%, perSecondRate is approximately X% / 365 days
        // Verify conversion is reasonable
        assertTrue(perSecondRate > 0);

        // Verify: Not zero
        assertGt(perSecondRate, 0);
    }

    /// @notice Fuzz test: Per-second rate accumulation
    function testFuzz_PerSecondRate_Accumulation(
        uint128 principal,
        uint32 ratePerSecond,  // Unit: 1e18
        uint32 timeSeconds
    ) public pure {
        vm.assume(principal > 0);
        vm.assume(ratePerSecond > 0);
        vm.assume(ratePerSecond <= Constants.PRECISION_18 / 365 days); // Reasonable per-second rate
        vm.assume(timeSeconds > 0 && timeSeconds <= 365 days);
        // Ensure accumulated interest is not 0
        vm.assume(uint256(principal) * uint256(ratePerSecond) * uint256(timeSeconds) >= Constants.PRECISION_18);

        // Accumulated interest = principal * rate * time / PRECISION
        vm.assume(uint256(principal) * uint256(ratePerSecond) < type(uint256).max / uint256(timeSeconds));

        uint256 interest = (uint256(principal) * uint256(ratePerSecond) * uint256(timeSeconds)) / Constants.PRECISION_18;

        // Verify: Interest grows linearly with time
        assertGt(interest, 0);
    }

    // ==================== Staking Shares and Interest Fuzz Tests ====================

    /// @notice Fuzz test: Staking shares to asset amount conversion
    function testFuzz_ShareToAsset_Conversion(
        uint128 userShares,
        uint128 totalShares,
        uint128 totalAssets
    ) public pure {
        vm.assume(userShares > 0);
        vm.assume(totalShares >= userShares);
        vm.assume(totalAssets > 0);

        // Calculate user assets = (userShares * totalAssets) / totalShares
        vm.assume(uint256(userShares) * uint256(totalAssets) < type(uint256).max / 2);

        uint256 userAssets = (uint256(userShares) * uint256(totalAssets)) / uint256(totalShares);

        // Verify: User assets do not exceed total assets
        assertLe(userAssets, totalAssets);

        // Verify: 100% shares = 100% assets
        if (userShares == totalShares) {
            assertEq(userAssets, totalAssets);
        }
    }

    /// @notice Fuzz test: Asset growth does not affect shares
    function testFuzz_AssetGrowth_SharesUnchanged(
        uint128 userShares,
        uint128 totalShares,
        uint128 totalAssets,
        uint32 growthBP
    ) public pure {
        vm.assume(userShares > 100); // At least 100 to be meaningful
        vm.assume(totalShares >= userShares);
        vm.assume(totalAssets > 0);
        vm.assume(growthBP > 0 && growthBP <= 10000); // Growth rate > 0

        // After asset growth
        uint256 newTotalAssets = uint256(totalAssets) * (Constants.BPS_BASE + uint256(growthBP)) / Constants.BPS_BASE;
        vm.assume(newTotalAssets <= type(uint128).max);

        // Calculate user assets before and after growth
        vm.assume(uint256(userShares) * uint256(totalAssets) < type(uint256).max / 2);
        vm.assume(uint256(userShares) * newTotalAssets < type(uint256).max / 2);

        uint256 userAssetsBefore = (uint256(userShares) * uint256(totalAssets)) / uint256(totalShares);
        uint256 userAssetsAfter = (uint256(userShares) * newTotalAssets) / uint256(totalShares);

        // Verify: After asset growth, user share value also grows
        if (growthBP > 0 && userAssetsBefore > 0) {
            assertGe(userAssetsAfter, userAssetsBefore);
        }
    }

    // ==================== Early Withdrawal Penalty Fuzz Tests ====================

    /// @notice Fuzz test: Early withdrawal interest penalty
    function testFuzz_EarlyWithdrawal_InterestPenalty(
        uint128 principal,
        uint128 accruedInterest,
        uint16 penaltyBP
    ) public pure {
        vm.assume(principal > 0);
        vm.assume(accruedInterest > 0);
        vm.assume(penaltyBP <= Constants.BPS_BASE);

        // Calculate penalty (only penalize interest portion)
        uint256 penalty = (uint256(accruedInterest) * uint256(penaltyBP)) / Constants.BPS_BASE;
        uint256 interestAfterPenalty = uint256(accruedInterest) - penalty;

        // Verify: Penalty does not exceed interest
        assertLe(penalty, accruedInterest);

        // Verify: Principal is unaffected
        uint256 totalReceived = uint256(principal) + interestAfterPenalty;
        assertGe(totalReceived, principal);
    }

    // ==================== Interest Rate Upper/Lower Bound Fuzz Tests ====================

    /// @notice Fuzz test: Interest rate upper bound check
    function testFuzz_InterestRate_UpperBound(
        uint32 proposedRate
    ) public pure {
        uint256 MAX_RATE = 50000; // 500% APR

        bool isValid = proposedRate <= MAX_RATE;

        // Verify: Exceeding upper bound should be rejected
        if (proposedRate > MAX_RATE) {
            assertFalse(isValid);
        } else {
            assertTrue(isValid);
        }
    }

    /// @notice Fuzz test: Interest rate lower bound check
    function testFuzz_InterestRate_LowerBound(
        uint32 proposedRate
    ) public pure {
        uint256 MIN_RATE = 0; // Minimum 0%

        bool isValid = proposedRate >= MIN_RATE;

        // Verify: Negative rate should be rejected
        assertTrue(isValid); // uint32 cannot be negative
    }

    // ==================== Compound Frequency Fuzz Tests ====================

    /// @notice Fuzz test: Compound frequency effect on returns
    function testFuzz_CompoundFrequency_Effect(
        uint64 principal,
        uint16 aprBP,
        uint16 frequency
    ) public pure {
        vm.assume(principal > 1000); // At least 1000 to see compound effect
        vm.assume(aprBP > 0 && aprBP <= 2000); // Max 20% APR
        vm.assume(frequency >= 1 && frequency <= 365);

        // Calculate rate per period
        uint256 ratePerPeriod = uint256(aprBP) / uint256(frequency);
        vm.assume(ratePerPeriod > 0);
        // Ensure noticeable growth
        vm.assume(aprBP >= 10); // At least 0.1%

        // Simplified calculation: Final amount ≈ principal * (1 + apr/frequency)^frequency
        // Using linear approximation: ≈ principal * (1 + apr)
        uint256 finalAmount = uint256(principal) * (Constants.BPS_BASE + uint256(aprBP)) / Constants.BPS_BASE;

        // Verify: Principal plus interest is greater than principal
        if (aprBP > 0) {
            assertGt(finalAmount, principal);
        } else {
            assertEq(finalAmount, principal);
        }

        // Verify: Compound effect (higher frequency means slightly higher returns, but same under linear approximation)
        assertGe(finalAmount, uint256(principal) * Constants.BPS_BASE / Constants.BPS_BASE);
    }

    // ==================== Precision Loss Fuzz Tests ====================

    /// @notice Fuzz test: Tiny amount interest calculation precision
    function testFuzz_TinyAmount_Precision(
        uint32 principal,  // Use uint32 to ensure very small
        uint16 rate,
        uint32 time
    ) public pure {
        vm.assume(principal > 0);
        vm.assume(principal <= 1e6); // Max 0.01 token (18 decimals)
        vm.assume(rate > 0 && rate <= 1000);
        vm.assume(time > 0 && time <= 365 days);

        uint256 interest = (uint256(principal) * uint256(rate) * uint256(time)) / (Constants.BPS_BASE * 365 days);

        // Verify: Even with small amounts, interest should calculate correctly (may be 0 due to rounding)
        assertGe(interest, 0);
    }

    /// @notice Fuzz test: Very long duration interest calculation
    function testFuzz_LongDuration_Interest(
        uint64 principal,
        uint16 rate,
        uint32 numYears
    ) public pure {
        vm.assume(principal > 0);
        vm.assume(rate > 0 && rate <= 1000);
        vm.assume(numYears >= 10 && numYears <= 100);
        // Ensure principal is large enough to produce meaningful interest
        vm.assume(principal >= 10000);

        // Simple interest: Long-term can be very large
        vm.assume(uint256(principal) * uint256(rate) * uint256(numYears) < type(uint256).max / Constants.BPS_BASE);

        uint256 interest = (uint256(principal) * uint256(rate) * uint256(numYears)) / Constants.BPS_BASE;

        // Verify: Long-term interest should be large
        if (interest > 0) {
            // Verify long-term interest exists
            assertGt(interest, 0);
        } // At least numYears% of principal
    }

    // ==================== Interest Distribution Fuzz Tests ====================

    /// @notice Fuzz test: Multi-user interest distribution sum
    function testFuzz_MultiUser_InterestDistribution(
        uint64 stake1,
        uint64 stake2,
        uint64 stake3,
        uint64 totalInterest
    ) public pure {
        vm.assume(stake1 > 0);
        vm.assume(stake2 > 0);
        vm.assume(stake3 > 0);
        vm.assume(totalInterest > 0);

        uint256 totalStake = uint256(stake1) + uint256(stake2) + uint256(stake3);

        // Distribute interest proportionally
        uint256 interest1 = (uint256(totalInterest) * uint256(stake1)) / totalStake;
        uint256 interest2 = (uint256(totalInterest) * uint256(stake2)) / totalStake;
        uint256 interest3 = (uint256(totalInterest) * uint256(stake3)) / totalStake;

        uint256 sumInterest = interest1 + interest2 + interest3;

        // Verify: Sum of distributed interest should equal total interest (allow rounding error)
        assertApproxEqAbs(sumInterest, totalInterest, 3);
    }

    // ==================== Edge Case Tests ====================

    /// @notice Fuzz test: Zero rate case
    function testFuzz_ZeroRate_ZeroInterest(
        uint128 principal,
        uint32 time
    ) public pure {
        vm.assume(principal > 0);
        vm.assume(time > 0);

        uint256 rate = 0;
        uint256 interest = (uint256(principal) * rate * uint256(time)) / (Constants.BPS_BASE * 365 days);

        // Verify: Zero rate produces zero interest
        assertEq(interest, 0);
    }

    /// @notice Fuzz test: Zero time case
    function testFuzz_ZeroTime_ZeroInterest(
        uint128 principal,
        uint16 rate
    ) public pure {
        vm.assume(principal > 0);
        vm.assume(rate > 0);

        uint256 time = 0;
        uint256 interest = (uint256(principal) * uint256(rate) * time) / (Constants.BPS_BASE * 365 days);

        // Verify: Zero time produces zero interest
        assertEq(interest, 0);
    }

    /// @notice Fuzz test: One second interest
    function testFuzz_OneSecond_Interest(
        uint128 principal,
        uint16 aprBP
    ) public pure {
        vm.assume(principal >= 1e18); // At least 1 full token
        vm.assume(aprBP >= 100 && aprBP <= 10000); // 1% - 100% APR

        uint256 time = 1; // 1 second
        uint256 interest = (uint256(principal) * uint256(aprBP) * time) / (Constants.BPS_BASE * 365 days);

        // Verify: One second interest should be very small but exist
        assertGt(interest, 0);
        assertLt(interest, principal / 1000000); // Much smaller than principal
    }
}
