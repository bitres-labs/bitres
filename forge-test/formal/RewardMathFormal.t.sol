// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/RewardMath.sol";
import "../../contracts/libraries/Constants.sol";

/**
 * @title RewardMath Formal Verification Tests
 * @notice Formal verification tests using Halmos symbolic execution
 * @dev Tests prefixed with "check_" are symbolic tests for Halmos
 */
contract RewardMathFormalTest is Test {

    // ============ emissionFor Properties ============

    /// @notice Verify emissionFor is zero when time is zero
    function check_emissionFor_zeroTime(
        uint128 rewardPerSec,
        uint128 allocPoint,
        uint128 totalAllocPoint
    ) public pure {
        vm.assume(totalAllocPoint > 0);
        vm.assume(allocPoint <= totalAllocPoint);

        uint256 emission = RewardMath.emissionFor(0, rewardPerSec, allocPoint, totalAllocPoint);
        assert(emission == 0);
    }

    /// @notice Verify emissionFor is zero when reward rate is zero
    function check_emissionFor_zeroRewardRate(
        uint64 timeElapsed,
        uint128 allocPoint,
        uint128 totalAllocPoint
    ) public pure {
        vm.assume(totalAllocPoint > 0);
        vm.assume(allocPoint <= totalAllocPoint);

        uint256 emission = RewardMath.emissionFor(timeElapsed, 0, allocPoint, totalAllocPoint);
        assert(emission == 0);
    }

    /// @notice Verify emissionFor is zero when total alloc is zero
    function check_emissionFor_zeroTotalAlloc(
        uint64 timeElapsed,
        uint128 rewardPerSec,
        uint128 allocPoint
    ) public pure {
        uint256 emission = RewardMath.emissionFor(timeElapsed, rewardPerSec, allocPoint, 0);
        assert(emission == 0);
    }

    /// @notice Verify emissionFor is monotonic in time
    function check_emissionFor_monotonicTime(
        uint64 time1,
        uint64 time2,
        uint64 rewardPerSec,
        uint64 allocPoint,
        uint64 totalAllocPoint
    ) public pure {
        vm.assume(totalAllocPoint > 0);
        vm.assume(allocPoint <= totalAllocPoint);
        vm.assume(time1 <= time2);

        uint256 emission1 = RewardMath.emissionFor(time1, rewardPerSec, allocPoint, totalAllocPoint);
        uint256 emission2 = RewardMath.emissionFor(time2, rewardPerSec, allocPoint, totalAllocPoint);

        assert(emission1 <= emission2);
    }

    /// @notice Verify emissionFor is monotonic in alloc point
    function check_emissionFor_monotonicAllocPoint(
        uint64 timeElapsed,
        uint64 rewardPerSec,
        uint64 allocPoint1,
        uint64 allocPoint2,
        uint64 totalAllocPoint
    ) public pure {
        vm.assume(totalAllocPoint > 0);
        vm.assume(allocPoint1 <= allocPoint2);
        vm.assume(allocPoint2 <= totalAllocPoint);

        uint256 emission1 = RewardMath.emissionFor(timeElapsed, rewardPerSec, allocPoint1, totalAllocPoint);
        uint256 emission2 = RewardMath.emissionFor(timeElapsed, rewardPerSec, allocPoint2, totalAllocPoint);

        assert(emission1 <= emission2);
    }

    /// @notice Verify emissionFor never exceeds max possible (rewardPerSec * time)
    function check_emissionFor_bounded(
        uint64 timeElapsed,
        uint64 rewardPerSec,
        uint64 allocPoint,
        uint64 totalAllocPoint
    ) public pure {
        vm.assume(totalAllocPoint > 0);
        vm.assume(allocPoint <= totalAllocPoint);

        uint256 emission = RewardMath.emissionFor(timeElapsed, rewardPerSec, allocPoint, totalAllocPoint);
        uint256 maxPossible = uint256(rewardPerSec) * uint256(timeElapsed);

        assert(emission <= maxPossible);
    }

    // ============ clampToMax Properties ============

    /// @notice Verify clampToMax returns zero when already at max
    function check_clampToMax_atMax(uint128 maxSupply, uint128 reward) public pure {
        uint256 clamped = RewardMath.clampToMax(maxSupply, reward, maxSupply);
        assert(clamped == 0);
    }

    /// @notice Verify clampToMax returns zero when over max
    function check_clampToMax_overMax(
        uint128 minted,
        uint128 reward,
        uint128 maxSupply
    ) public pure {
        vm.assume(minted > maxSupply);

        uint256 clamped = RewardMath.clampToMax(minted, reward, maxSupply);
        assert(clamped == 0);
    }

    /// @notice Verify clampToMax returns full reward when room available
    function check_clampToMax_fullReward(
        uint128 minted,
        uint128 reward,
        uint128 maxSupply
    ) public pure {
        vm.assume(maxSupply > minted);
        vm.assume(uint256(minted) + uint256(reward) <= uint256(maxSupply));

        uint256 clamped = RewardMath.clampToMax(minted, reward, maxSupply);
        assert(clamped == reward);
    }

    /// @notice Verify clampToMax never exceeds remaining supply
    function check_clampToMax_bounded(
        uint128 minted,
        uint128 reward,
        uint128 maxSupply
    ) public pure {
        uint256 clamped = RewardMath.clampToMax(minted, reward, maxSupply);

        if (minted < maxSupply) {
            assert(clamped <= maxSupply - minted);
        } else {
            assert(clamped == 0);
        }
    }

    /// @notice Verify clampToMax + minted never exceeds maxSupply
    /// @dev Only valid when minted <= maxSupply (precondition for the sum bound property)
    function check_clampToMax_sumBounded(
        uint128 minted,
        uint128 reward,
        uint128 maxSupply
    ) public pure {
        vm.assume(minted <= maxSupply);  // Precondition: minted is within valid range
        uint256 clamped = RewardMath.clampToMax(minted, reward, maxSupply);
        assert(minted + clamped <= maxSupply);
    }

    // ============ accRewardPerShare Properties ============

    /// @notice Verify accRewardPerShare never decreases
    function check_accRewardPerShare_monotonic(
        uint128 current,
        uint128 poolReward,
        uint128 totalStaked
    ) public pure {
        vm.assume(totalStaked > 0);

        uint256 newAcc = RewardMath.accRewardPerShare(current, poolReward, totalStaked);
        assert(newAcc >= current);
    }

    /// @notice Verify accRewardPerShare unchanged when reward is zero
    function check_accRewardPerShare_zeroReward(
        uint128 current,
        uint128 totalStaked
    ) public pure {
        uint256 newAcc = RewardMath.accRewardPerShare(current, 0, totalStaked);
        assert(newAcc == current);
    }

    /// @notice Verify accRewardPerShare unchanged when totalStaked is zero
    function check_accRewardPerShare_zeroStaked(
        uint128 current,
        uint128 poolReward
    ) public pure {
        uint256 newAcc = RewardMath.accRewardPerShare(current, poolReward, 0);
        assert(newAcc == current);
    }

    // ============ pending Properties ============

    /// @notice Verify pending is zero when amount is zero
    function check_pending_zeroAmount(uint128 accPerShare, uint128 rewardDebt) public pure {
        uint256 pendingReward = RewardMath.pending(0, accPerShare, rewardDebt);
        assert(pendingReward == 0);
    }

    /// @notice Verify pending is zero when accPerShare is zero
    function check_pending_zeroAccPerShare(uint128 amount, uint128 rewardDebt) public pure {
        uint256 pendingReward = RewardMath.pending(amount, 0, rewardDebt);
        assert(pendingReward == 0);
    }

    /// @notice Verify pending is bounded by accumulated value
    function check_pending_bounded(
        uint64 amount,
        uint64 accPerShare,
        uint128 rewardDebt
    ) public pure {
        uint256 pendingReward = RewardMath.pending(amount, accPerShare, rewardDebt);
        uint256 accumulated = (uint256(amount) * uint256(accPerShare)) / 1e12;

        // Pending should be either 0 or accumulated - rewardDebt
        if (accumulated > rewardDebt) {
            assert(pendingReward == accumulated - rewardDebt);
        } else {
            assert(pendingReward == 0);
        }
    }

    // ============ rewardDebtValue Properties ============

    /// @notice Verify rewardDebtValue is zero when amount is zero
    function check_rewardDebtValue_zeroAmount(uint128 accPerShare) public pure {
        uint256 debt = RewardMath.rewardDebtValue(0, accPerShare);
        assert(debt == 0);
    }

    /// @notice Verify rewardDebtValue is zero when accPerShare is zero
    function check_rewardDebtValue_zeroAccPerShare(uint128 amount) public pure {
        uint256 debt = RewardMath.rewardDebtValue(amount, 0);
        assert(debt == 0);
    }

    /// @notice Verify rewardDebtValue is monotonic in amount
    function check_rewardDebtValue_monotonicAmount(
        uint64 amount1,
        uint64 amount2,
        uint64 accPerShare
    ) public pure {
        vm.assume(amount1 <= amount2);

        uint256 debt1 = RewardMath.rewardDebtValue(amount1, accPerShare);
        uint256 debt2 = RewardMath.rewardDebtValue(amount2, accPerShare);

        assert(debt1 <= debt2);
    }

    /// @notice Verify rewardDebtValue is monotonic in accPerShare
    function check_rewardDebtValue_monotonicAccPerShare(
        uint64 amount,
        uint64 accPerShare1,
        uint64 accPerShare2
    ) public pure {
        vm.assume(accPerShare1 <= accPerShare2);

        uint256 debt1 = RewardMath.rewardDebtValue(amount, accPerShare1);
        uint256 debt2 = RewardMath.rewardDebtValue(amount, accPerShare2);

        assert(debt1 <= debt2);
    }
}
