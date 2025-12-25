// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/InterestMath.sol";
import "../../contracts/libraries/Constants.sol";

/**
 * @title InterestMath Formal Verification Tests
 * @notice Formal verification tests using Halmos symbolic execution
 * @dev Tests prefixed with "check_" are symbolic tests for Halmos
 */
contract InterestMathFormalTest is Test {

    // ============ pendingReward Properties ============

    /// @notice Verify pendingReward is zero when amount is zero
    function check_pendingReward_zeroAmount(
        uint128 accInterestPerShare,
        uint128 rewardDebt
    ) public pure {
        uint256 pending = InterestMath.pendingReward(0, accInterestPerShare, rewardDebt);
        assert(pending == 0);
    }

    /// @notice Verify pendingReward is zero when accInterestPerShare is zero
    function check_pendingReward_zeroAccInterest(
        uint128 amount,
        uint128 rewardDebt
    ) public pure {
        uint256 pending = InterestMath.pendingReward(amount, 0, rewardDebt);
        assert(pending == 0);
    }

    /// @notice Verify pendingReward is bounded
    function check_pendingReward_bounded(
        uint64 amount,
        uint64 accInterestPerShare,
        uint128 rewardDebt
    ) public pure {
        uint256 pending = InterestMath.pendingReward(amount, accInterestPerShare, rewardDebt);
        uint256 accumulated = (uint256(amount) * uint256(accInterestPerShare)) / Constants.PRECISION_18;

        if (accumulated > rewardDebt) {
            assert(pending == accumulated - rewardDebt);
        } else {
            assert(pending == 0);
        }
    }

    // ============ interestPerShareDelta Properties ============

    /// @notice Verify interestPerShareDelta is zero when rate is zero
    function check_interestPerShareDelta_zeroRate(uint64 timeElapsed) public pure {
        uint256 delta = InterestMath.interestPerShareDelta(0, timeElapsed);
        assert(delta == 0);
    }

    /// @notice Verify interestPerShareDelta is zero when time is zero
    function check_interestPerShareDelta_zeroTime(uint16 annualRateBps) public pure {
        uint256 delta = InterestMath.interestPerShareDelta(annualRateBps, 0);
        assert(delta == 0);
    }

    /// @notice Verify interestPerShareDelta is monotonic in time
    function check_interestPerShareDelta_monotonicTime(
        uint16 annualRateBps,
        uint32 time1,
        uint32 time2
    ) public pure {
        vm.assume(time1 <= time2);

        uint256 delta1 = InterestMath.interestPerShareDelta(annualRateBps, time1);
        uint256 delta2 = InterestMath.interestPerShareDelta(annualRateBps, time2);

        assert(delta1 <= delta2);
    }

    /// @notice Verify interestPerShareDelta is monotonic in rate
    function check_interestPerShareDelta_monotonicRate(
        uint16 rate1,
        uint16 rate2,
        uint32 timeElapsed
    ) public pure {
        vm.assume(rate1 <= rate2);

        uint256 delta1 = InterestMath.interestPerShareDelta(rate1, timeElapsed);
        uint256 delta2 = InterestMath.interestPerShareDelta(rate2, timeElapsed);

        assert(delta1 <= delta2);
    }

    // ============ rewardDebtValue Properties ============

    /// @notice Verify rewardDebtValue is zero when amount is zero
    function check_rewardDebtValue_zeroAmount(uint128 accInterestPerShare) public pure {
        uint256 debt = InterestMath.rewardDebtValue(0, accInterestPerShare);
        assert(debt == 0);
    }

    /// @notice Verify rewardDebtValue is zero when accInterestPerShare is zero
    function check_rewardDebtValue_zeroAccInterest(uint128 amount) public pure {
        uint256 debt = InterestMath.rewardDebtValue(amount, 0);
        assert(debt == 0);
    }

    /// @notice Verify rewardDebtValue is monotonic in amount
    function check_rewardDebtValue_monotonicAmount(
        uint64 amount1,
        uint64 amount2,
        uint64 accInterestPerShare
    ) public pure {
        vm.assume(amount1 <= amount2);

        uint256 debt1 = InterestMath.rewardDebtValue(amount1, accInterestPerShare);
        uint256 debt2 = InterestMath.rewardDebtValue(amount2, accInterestPerShare);

        assert(debt1 <= debt2);
    }

    // ============ feeAmount Properties ============

    /// @notice Verify feeAmount is zero when amount is zero
    function check_feeAmount_zeroAmount(uint16 feeBps) public pure {
        uint256 fee = InterestMath.feeAmount(0, feeBps);
        assert(fee == 0);
    }

    /// @notice Verify feeAmount is zero when feeBps is zero
    function check_feeAmount_zeroFee(uint128 amount) public pure {
        uint256 fee = InterestMath.feeAmount(amount, 0);
        assert(fee == 0);
    }

    /// @notice Verify feeAmount never exceeds amount
    function check_feeAmount_bounded(uint128 amount, uint16 feeBps) public pure {
        vm.assume(feeBps <= 10000); // Fee <= 100%

        uint256 fee = InterestMath.feeAmount(amount, feeBps);
        assert(fee <= amount);
    }

    /// @notice Verify feeAmount equals amount when feeBps is 10000 (100%)
    function check_feeAmount_fullFee(uint128 amount) public pure {
        uint256 fee = InterestMath.feeAmount(amount, 10000);
        assert(fee == amount);
    }

    /// @notice Verify feeAmount is monotonic in amount
    function check_feeAmount_monotonicAmount(
        uint64 amount1,
        uint64 amount2,
        uint16 feeBps
    ) public pure {
        vm.assume(amount1 <= amount2);

        uint256 fee1 = InterestMath.feeAmount(amount1, feeBps);
        uint256 fee2 = InterestMath.feeAmount(amount2, feeBps);

        assert(fee1 <= fee2);
    }

    /// @notice Verify feeAmount is monotonic in feeBps
    function check_feeAmount_monotonicFee(
        uint128 amount,
        uint16 feeBps1,
        uint16 feeBps2
    ) public pure {
        vm.assume(feeBps1 <= feeBps2);

        uint256 fee1 = InterestMath.feeAmount(amount, feeBps1);
        uint256 fee2 = InterestMath.feeAmount(amount, feeBps2);

        assert(fee1 <= fee2);
    }

    // ============ splitWithdrawal Properties ============

    /// @notice Verify splitWithdrawal sums to amount
    function check_splitWithdrawal_sumEqualsAmount(
        uint64 amount,
        uint64 pendingInterest,
        uint64 totalAvailable
    ) public pure {
        vm.assume(totalAvailable > 0);
        vm.assume(amount <= totalAvailable);
        vm.assume(pendingInterest <= totalAvailable);

        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            amount,
            pendingInterest,
            totalAvailable
        );

        assert(interestShare + principalShare == amount);
    }

    /// @notice Verify splitWithdrawal returns zero shares when amount is zero
    function check_splitWithdrawal_zeroAmount(
        uint64 pendingInterest,
        uint64 totalAvailable
    ) public pure {
        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            0,
            pendingInterest,
            totalAvailable
        );

        assert(interestShare == 0);
        assert(principalShare == 0);
    }

    /// @notice Verify splitWithdrawal returns all principal when no pending interest
    function check_splitWithdrawal_noPendingInterest(
        uint64 amount,
        uint64 totalAvailable
    ) public pure {
        vm.assume(totalAvailable > 0);
        vm.assume(amount <= totalAvailable);

        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            amount,
            0,
            totalAvailable
        );

        assert(interestShare == 0);
        assert(principalShare == amount);
    }

    /// @notice Verify interestShare never exceeds amount
    function check_splitWithdrawal_interestShareBounded(
        uint64 amount,
        uint64 pendingInterest,
        uint64 totalAvailable
    ) public pure {
        vm.assume(totalAvailable > 0);
        vm.assume(amount <= totalAvailable);

        (uint256 interestShare,) = InterestMath.splitWithdrawal(
            amount,
            pendingInterest,
            totalAvailable
        );

        assert(interestShare <= amount);
    }

    /// @notice Verify interestShare never exceeds pendingInterest
    function check_splitWithdrawal_interestShareBoundedByPending(
        uint64 amount,
        uint64 pendingInterest,
        uint64 totalAvailable
    ) public pure {
        vm.assume(totalAvailable > 0);
        vm.assume(amount <= totalAvailable);
        vm.assume(pendingInterest <= totalAvailable);

        (uint256 interestShare,) = InterestMath.splitWithdrawal(
            amount,
            pendingInterest,
            totalAvailable
        );

        assert(interestShare <= pendingInterest);
    }

    // ============ totalAssetsWithAccrued Properties ============

    /// @notice Verify totalAssetsWithAccrued returns principal when rate is zero
    function check_totalAssetsWithAccrued_zeroRate(
        uint64 principal,
        uint64 lastAccrual,
        uint64 currentTimestamp
    ) public pure {
        vm.assume(currentTimestamp >= lastAccrual);

        uint256 total = InterestMath.totalAssetsWithAccrued(
            principal,
            0, // zero rate
            lastAccrual,
            currentTimestamp
        );

        assert(total == principal);
    }

    /// @notice Verify totalAssetsWithAccrued returns zero when principal is zero
    function check_totalAssetsWithAccrued_zeroPrincipal(
        uint16 annualRateBps,
        uint64 lastAccrual,
        uint64 currentTimestamp
    ) public pure {
        uint256 total = InterestMath.totalAssetsWithAccrued(
            0,
            annualRateBps,
            lastAccrual,
            currentTimestamp
        );

        assert(total == 0);
    }

    /// @notice Verify totalAssetsWithAccrued returns principal when no time elapsed
    function check_totalAssetsWithAccrued_noTimeElapsed(
        uint64 principal,
        uint16 annualRateBps,
        uint64 timestamp
    ) public pure {
        uint256 total = InterestMath.totalAssetsWithAccrued(
            principal,
            annualRateBps,
            timestamp,
            timestamp
        );

        assert(total == principal);
    }

    /// @notice Verify totalAssetsWithAccrued is >= principal
    function check_totalAssetsWithAccrued_geqPrincipal(
        uint64 principal,
        uint16 annualRateBps,
        uint32 lastAccrual,
        uint32 currentTimestamp
    ) public pure {
        vm.assume(currentTimestamp >= lastAccrual);

        uint256 total = InterestMath.totalAssetsWithAccrued(
            principal,
            annualRateBps,
            lastAccrual,
            currentTimestamp
        );

        assert(total >= principal);
    }

    // ============ priceChangeBps Properties ============

    /// @notice Verify priceChangeBps is zero when prices are equal
    function check_priceChangeBps_equalPrices(uint128 price) public pure {
        int256 change = InterestMath.priceChangeBps(price, price);
        assert(change == 0);
    }

    /// @notice Verify priceChangeBps is zero when previous price is zero
    function check_priceChangeBps_zeroPreviousPrice(uint128 currentPrice) public pure {
        int256 change = InterestMath.priceChangeBps(0, currentPrice);
        assert(change == 0);
    }

    /// @notice Verify priceChangeBps is positive when price increases
    function check_priceChangeBps_positiveOnIncrease(
        uint64 previousPrice,
        uint64 currentPrice
    ) public pure {
        vm.assume(previousPrice > 0);
        vm.assume(currentPrice > previousPrice);

        int256 change = InterestMath.priceChangeBps(previousPrice, currentPrice);
        assert(change > 0);
    }

    /// @notice Verify priceChangeBps is negative when price decreases
    function check_priceChangeBps_negativeOnDecrease(
        uint64 previousPrice,
        uint64 currentPrice
    ) public pure {
        vm.assume(previousPrice > 0);
        vm.assume(currentPrice < previousPrice);

        int256 change = InterestMath.priceChangeBps(previousPrice, currentPrice);
        assert(change < 0);
    }
}
