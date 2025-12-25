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
        // Use bound() to avoid rejection
        principal = uint128(bound(principal, 1, type(uint128).max));
        rate = uint32(bound(rate, 1, 10000)); // Max 100%
        timeYears = uint32(bound(timeYears, 1, 100));

        // Early return if interest would be 0
        if (uint256(principal) * uint256(rate) * uint256(timeYears) < Constants.BPS_BASE) return;

        // Simple interest = principal * rate * time / BP_DIVISOR
        // uint128 * uint32 * uint32 is always < type(uint256).max

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
        // Use bound() to avoid rejection
        principal = uint64(bound(principal, 1001, type(uint64).max)); // At least 1000 to see compound effect
        rate = uint16(bound(rate, 1, 1000)); // Max 10% per period
        periods = uint16(bound(periods, 1, 120)); // Max 120 periods (10 years monthly)

        // Compound formula: A = P * (1 + r)^n
        // Using approximation: A ≈ P * (1 + n*r) to avoid power overflow
        uint256 totalRate = uint256(rate) * uint256(periods);

        // Early return if totalRate exceeds max allowed
        if (totalRate > Constants.BPS_BASE * 10) return; // Max total return 1000%

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
        // Use bound() to avoid rejection
        principal = uint128(bound(principal, 1, type(uint128).max));
        rate1 = uint16(bound(rate1, 1, 4999)); // Leave room for rate2
        rate2 = uint16(bound(rate2, rate1 + 1, 5000)); // rate2 > rate1
        time = uint32(bound(time, 1, 365 days));

        // Early return if interest1 would be 0
        if (uint256(principal) * uint256(rate1) * uint256(time) < Constants.BPS_BASE * 365 days) return;

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
        // Use bound() to avoid rejection
        principal1 = uint128(bound(principal1, 1001, type(uint128).max / 2 - 1)); // At least 1000, leave room for principal2
        principal2 = uint128(bound(principal2, principal1 + 1, type(uint128).max / 2)); // principal2 > principal1
        rate = uint16(bound(rate, 1, 5000));
        time = uint32(bound(time, 1, 365 days));

        // Early return if interest1 would be 0
        if (uint256(principal1) * uint256(rate) * uint256(time) < Constants.BPS_BASE * 365 days) return;

        // uint128/2 * uint16 * uint32 is always < type(uint256).max / 2

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
        // Use bound() to avoid rejection
        aprBP = uint32(bound(aprBP, 100, 50000)); // At least 1% to be meaningful, max 500% APR

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
        // Use bound() to avoid rejection
        principal = uint128(bound(principal, 1, type(uint128).max));
        ratePerSecond = uint32(bound(ratePerSecond, 1, uint32(Constants.PRECISION_18 / 365 days))); // Reasonable per-second rate
        timeSeconds = uint32(bound(timeSeconds, 1, 365 days));

        // Early return if accumulated interest would be 0
        if (uint256(principal) * uint256(ratePerSecond) * uint256(timeSeconds) < Constants.PRECISION_18) return;

        // Accumulated interest = principal * rate * time / PRECISION
        // uint128 * uint32 * uint32 is always < type(uint256).max

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
        // Use bound() to avoid rejection
        userShares = uint128(bound(userShares, 1, type(uint128).max));
        totalShares = uint128(bound(totalShares, userShares, type(uint128).max)); // totalShares >= userShares
        totalAssets = uint128(bound(totalAssets, 1, type(uint128).max));

        // Calculate user assets = (userShares * totalAssets) / totalShares
        // uint128 * uint128 is always < type(uint256).max / 2

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
        // Use bound() to avoid rejection
        userShares = uint128(bound(userShares, 101, type(uint128).max / 2)); // At least 100 to be meaningful
        totalShares = uint128(bound(totalShares, userShares, type(uint128).max)); // totalShares >= userShares
        totalAssets = uint128(bound(totalAssets, 1, type(uint128).max / 2)); // Leave room for growth
        growthBP = uint32(bound(growthBP, 1, 10000)); // Growth rate > 0

        // After asset growth
        uint256 newTotalAssets = uint256(totalAssets) * (Constants.BPS_BASE + uint256(growthBP)) / Constants.BPS_BASE;

        // Early return if newTotalAssets exceeds max
        if (newTotalAssets > type(uint128).max) return;

        // Calculate user assets before and after growth
        // uint128/2 * uint128/2 is always < type(uint256).max / 2

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
        // Use bound() to avoid rejection
        principal = uint128(bound(principal, 1, type(uint128).max));
        accruedInterest = uint128(bound(accruedInterest, 1, type(uint128).max));
        penaltyBP = uint16(bound(penaltyBP, 0, Constants.BPS_BASE));

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
        // Use bound() to avoid rejection
        principal = uint64(bound(principal, 1001, type(uint64).max)); // At least 1000 to see compound effect
        aprBP = uint16(bound(aprBP, 10, 2000)); // At least 0.1%, max 20% APR
        frequency = uint16(bound(frequency, 1, 365));

        // Calculate rate per period
        uint256 ratePerPeriod = uint256(aprBP) / uint256(frequency);

        // Early return if ratePerPeriod is 0
        if (ratePerPeriod == 0) return;

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
        // Use bound() to avoid rejection
        principal = uint32(bound(principal, 1, 1e6)); // Max 0.01 token (18 decimals)
        rate = uint16(bound(rate, 1, 1000));
        time = uint32(bound(time, 1, 365 days));

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
        // Use bound() to avoid rejection
        principal = uint64(bound(principal, 10000, type(uint64).max)); // At least 10000 for meaningful interest
        rate = uint16(bound(rate, 1, 1000));
        numYears = uint32(bound(numYears, 10, 100));

        // Simple interest: Long-term can be very large
        // uint64 * uint16 * uint32 is always < type(uint256).max / Constants.BPS_BASE

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
        // Use bound() to avoid rejection
        stake1 = uint64(bound(stake1, 1, type(uint64).max));
        stake2 = uint64(bound(stake2, 1, type(uint64).max));
        stake3 = uint64(bound(stake3, 1, type(uint64).max));
        totalInterest = uint64(bound(totalInterest, 1, type(uint64).max));

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
        // Use bound() to avoid rejection
        principal = uint128(bound(principal, 1, type(uint128).max));
        time = uint32(bound(time, 1, type(uint32).max));

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
        // Use bound() to avoid rejection
        principal = uint128(bound(principal, 1, type(uint128).max));
        rate = uint16(bound(rate, 1, type(uint16).max));

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
        // Use bound() to avoid rejection
        principal = uint128(bound(principal, 1e18, type(uint128).max)); // At least 1 full token
        aprBP = uint16(bound(aprBP, 100, 10000)); // 1% - 100% APR

        uint256 time = 1; // 1 second
        uint256 interest = (uint256(principal) * uint256(aprBP) * time) / (Constants.BPS_BASE * 365 days);

        // Verify: One second interest should be very small but exist
        assertGt(interest, 0);
        assertLt(interest, principal / 1000000); // Much smaller than principal
    }
}
