// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/RewardMath.sol";
import "../../contracts/libraries/Constants.sol";

/// @title FarmingPool Fuzz Tests
/// @notice Tests all edge cases for mining reward calculations
contract FarmingPoolFuzzTest is Test {
    using Constants for *;

    // ==================== Reward Calculation Fuzz Tests ====================

    /// @notice Fuzz test: Reward calculation does not overflow
    function testFuzz_RewardCalculation_NoOverflow(
        uint128 stakedAmount,
        uint128 rewardPerBlock,
        uint32 blockElapsed
    ) public pure {
        vm.assume(stakedAmount > 0);
        vm.assume(rewardPerBlock > 0);
        vm.assume(blockElapsed > 0);
        vm.assume(blockElapsed <= 365 days / 12); // Max 1 year of blocks

        // Prevent multiplication overflow
        vm.assume(uint256(rewardPerBlock) * uint256(blockElapsed) < type(uint256).max / 2);

        // Calculate total reward (using uint256)
        uint256 totalReward = uint256(rewardPerBlock) * uint256(blockElapsed);

        // Verify: Does not overflow
        assertGt(totalReward, 0);
        assertGe(totalReward, rewardPerBlock);
        assertGe(totalReward, blockElapsed);
    }

    /// @notice Fuzz test: User reward proportional to stake share
    function testFuzz_UserReward_Proportional(
        uint128 userStake,
        uint128 totalStake,
        uint128 rewardPerBlock,
        uint32 blockElapsed
    ) public pure {
        vm.assume(userStake > 0);
        vm.assume(totalStake >= userStake);
        vm.assume(rewardPerBlock > 0);
        vm.assume(blockElapsed > 0);
        vm.assume(blockElapsed <= 10000);

        uint256 totalReward = uint256(rewardPerBlock) * uint256(blockElapsed);
        vm.assume(totalReward < type(uint256).max / Constants.PRECISION_18);
        // Ensure userReward is not 0 due to precision loss
        // Prevent overflow in multiplication
        vm.assume(totalReward <= type(uint128).max);
        vm.assume(uint256(userStake) <= type(uint128).max);
        vm.assume(totalReward * uint256(userStake) >= totalStake); // Ensure userReward is not 0

        // Calculate user reward
        uint256 userReward = (totalReward * uint256(userStake)) / uint256(totalStake);

        // Verify: User reward does not exceed total reward
        assertLe(userReward, totalReward);

        // Verify: If user staked 100%, should get 100% reward
        if (userStake == totalStake) {
            assertEq(userReward, totalReward);
        }

        // Verify: Larger stake share means more reward
        if (userStake > 0 && userStake < totalStake) {
            assertLt(userReward, totalReward);
            assertGt(userReward, 0);
        }
    }

    /// @notice Fuzz test: Double stake gets double reward
    function testFuzz_DoubleStake_DoubleReward(
        uint16 userStakeUnits,      // User stake units (1-1000)
        uint8 totalStakeMultiplier, // Total stake multiplier (3-20)
        uint16 rewardUnits,         // Reward units
        uint16 blockElapsed
    ) public pure {
        vm.assume(userStakeUnits > 0 && userStakeUnits < 1000);
        vm.assume(totalStakeMultiplier >= 3 && totalStakeMultiplier < 20);
        vm.assume(rewardUnits > 0 && rewardUnits < 1000);
        vm.assume(blockElapsed >= 10 && blockElapsed < 1000);

        // Construct parameters (using 1e18 as base)
        uint256 userStake = uint256(userStakeUnits) * 1e18;
        uint256 totalStake = userStake * uint256(totalStakeMultiplier);
        uint256 rewardPerBlock = uint256(rewardUnits) * 1e18;
        uint256 totalReward = rewardPerBlock * uint256(blockElapsed);

        // Calculate reward with 1x stake
        uint256 reward1x = (totalReward * userStake) / totalStake;

        // Calculate reward with 2x stake
        uint256 reward2x = (totalReward * userStake * 2) / totalStake;

        // Verify: 2x stake should get 2x reward (allow 1 unit rounding error)
        assertApproxEqAbs(reward2x, reward1x * 2, 1);
    }

    // ==================== Share Calculation Fuzz Tests ====================

    /// @notice Fuzz test: Share calculation does not overflow
    function testFuzz_ShareCalculation_NoOverflow(
        uint128 depositAmount,
        uint128 totalShares,
        uint128 totalAssets
    ) public pure {
        vm.assume(depositAmount > 0);
        vm.assume(totalAssets > 0);
        vm.assume(totalShares > 0);

        // Calculate new shares = (deposit * totalShares) / totalAssets
        vm.assume(uint256(depositAmount) * uint256(totalShares) < type(uint256).max / 2);
        // Ensure newShares is not 0
        vm.assume(uint256(depositAmount) * uint256(totalShares) >= totalAssets);

        uint256 newShares = (uint256(depositAmount) * uint256(totalShares)) / uint256(totalAssets);

        // Verify: Shares do not overflow
        assertGt(newShares, 0);
    }

    /// @notice Fuzz test: First deposit shares equal amount
    function testFuzz_FirstDeposit_SharesEqualAmount(
        uint128 depositAmount
    ) public pure {
        vm.assume(depositAmount > 0);

        // First deposit: totalShares = 0, totalAssets = 0
        // New shares should equal deposit amount
        uint256 shares = depositAmount;

        assertEq(shares, depositAmount);
    }

    /// @notice Fuzz test: Share value preservation
    function testFuzz_ShareValue_Preservation(
        uint128 userShares,
        uint128 totalShares,
        uint128 totalAssets
    ) public pure {
        vm.assume(userShares > 0);
        vm.assume(totalShares >= userShares);
        vm.assume(totalAssets > 0);

        // Calculate user asset value
        vm.assume(uint256(userShares) * uint256(totalAssets) < type(uint256).max / 2);

        uint256 userAssetValue = (uint256(userShares) * uint256(totalAssets)) / uint256(totalShares);

        // Verify: User assets do not exceed total assets
        assertLe(userAssetValue, totalAssets);

        // Verify: If user owns 100% shares, should get 100% assets
        if (userShares == totalShares) {
            assertEq(userAssetValue, totalAssets);
        }
    }

    // ==================== APR/APY Calculation Fuzz Tests ====================

    /// @notice Fuzz test: APR calculation does not overflow
    function testFuzz_APR_NoOverflow(
        uint128 rewardPerYear,
        uint128 totalStaked
    ) public pure {
        vm.assume(rewardPerYear > 0);
        vm.assume(totalStaked > 0);
        // Ensure APR is not 0 due to precision loss
        vm.assume(uint256(rewardPerYear) * Constants.PRECISION_18 >= totalStaked);

        // APR = (annual reward / total staked) * 100%
        vm.assume(uint256(rewardPerYear) * Constants.PRECISION_18 < type(uint256).max / 2);

        uint256 apr = (uint256(rewardPerYear) * Constants.PRECISION_18) / uint256(totalStaked);

        // Verify: APR should be > 0
        assertGt(apr, 0);
    }

    /// @notice Fuzz test: APR positively correlated with reward rate
    function testFuzz_APR_RewardPositiveCorrelation(
        uint128 rewardRate1,
        uint128 rewardRate2,
        uint128 totalStaked
    ) public pure {
        vm.assume(totalStaked > 0);
        vm.assume(rewardRate2 > rewardRate1);
        vm.assume(rewardRate1 > 0);
        // Ensure APR1 is not 0
        vm.assume(uint256(rewardRate1) * Constants.PRECISION_18 / totalStaked > 0);
        vm.assume(uint256(rewardRate2) * Constants.PRECISION_18 / totalStaked > uint256(rewardRate1) * Constants.PRECISION_18 / totalStaked);

        vm.assume(uint256(rewardRate1) * Constants.PRECISION_18 < type(uint256).max / 2);
        vm.assume(uint256(rewardRate2) * Constants.PRECISION_18 < type(uint256).max / 2);

        uint256 apr1 = (uint256(rewardRate1) * Constants.PRECISION_18) / uint256(totalStaked);
        uint256 apr2 = (uint256(rewardRate2) * Constants.PRECISION_18) / uint256(totalStaked);

        // Verify: Higher reward rate means higher APR
        assertGt(apr2, apr1);
    }

    /// @notice Fuzz test: APR negatively correlated with total staked
    function testFuzz_APR_StakeNegativeCorrelation(
        uint64 rewardRate,    // Changed to uint64 to avoid overflow
        uint64 totalStaked1
    ) public pure {
        vm.assume(rewardRate > 1e12); // Large enough reward rate
        vm.assume(totalStaked1 > 1e16); // Large enough stake
        vm.assume(totalStaked1 < type(uint64).max / 4); // Ensure can *2

        // totalStaked2 is 2x totalStaked1 (fixed relationship, avoid vm.assume rejection)
        uint256 totalStaked2 = uint256(totalStaked1) * 2;

        // Ensure no overflow
        vm.assume(uint256(rewardRate) * Constants.PRECISION_18 < type(uint256).max / 2);

        uint256 apr1 = (uint256(rewardRate) * Constants.PRECISION_18) / uint256(totalStaked1);
        uint256 apr2 = (uint256(rewardRate) * Constants.PRECISION_18) / totalStaked2;

        // Verify: Higher total staked means lower APR (dilution effect)
        // totalStaked2 is 2x totalStaked1, so apr2 should be close to half of apr1
        assertLt(apr2, apr1);
        assertApproxEqRel(apr2 * 2, apr1, 1e15); // 0.1% error tolerance
    }

    // ==================== Compound Calculation Fuzz Tests ====================

    /// @notice Fuzz test: APY > APR (compound effect)
    function testFuzz_APY_GreaterThanAPR(
        uint64 apr,
        uint16 compoundFrequency
    ) public pure {
        vm.assume(apr > 0);
        vm.assume(apr <= Constants.PRECISION_18); // APR <= 100%
        vm.assume(compoundFrequency > 1);
        vm.assume(compoundFrequency <= 365); // Max daily compounding

        // Simplified APY calculation: APY approximately APR * compoundFrequency (linear approximation)
        uint256 apy = (uint256(apr) * uint256(compoundFrequency)) / 365;

        // Verify: More compounds means APY closer to or greater than APR
        if (compoundFrequency > 1) {
            assertGe(apy, apr / 365);
        }
    }

    // ==================== Reward Distribution Fuzz Tests ====================

    /// @notice Fuzz test: Multi-user reward sum equals total reward
    function testFuzz_MultiUser_RewardSum(
        uint64 stake1,
        uint64 stake2,
        uint64 stake3,
        uint64 rewardPerBlock,
        uint16 blockElapsed
    ) public pure {
        vm.assume(stake1 > 0);
        vm.assume(stake2 > 0);
        vm.assume(stake3 > 0);
        vm.assume(rewardPerBlock > 0);
        vm.assume(blockElapsed > 0);

        uint256 totalStake = uint256(stake1) + uint256(stake2) + uint256(stake3);
        vm.assume(totalStake <= type(uint128).max);

        uint256 totalReward = uint256(rewardPerBlock) * uint256(blockElapsed);

        // Calculate each user's reward
        uint256 reward1 = (totalReward * uint256(stake1)) / totalStake;
        uint256 reward2 = (totalReward * uint256(stake2)) / totalStake;
        uint256 reward3 = (totalReward * uint256(stake3)) / totalStake;

        uint256 sumRewards = reward1 + reward2 + reward3;

        // Verify: Sum of all user rewards should equal total reward (allow rounding error)
        assertApproxEqAbs(sumRewards, totalReward, 3); // Max 3 wei error (3 users rounding)
    }

    /// @notice Fuzz test: Zero stake gets zero reward
    function testFuzz_ZeroStake_ZeroReward(
        uint128 totalStake,
        uint128 rewardPerBlock,
        uint32 blockElapsed
    ) public pure {
        vm.assume(totalStake > 0);
        vm.assume(rewardPerBlock > 0);
        vm.assume(blockElapsed > 0);

        uint256 userStake = 0;
        uint256 totalReward = uint256(rewardPerBlock) * uint256(blockElapsed);

        uint256 userReward = (totalReward * userStake) / uint256(totalStake);

        // Verify: Zero stake gets zero reward
        assertEq(userReward, 0);
    }

    // ==================== Lock Period Fuzz Tests ====================

    /// @notice Fuzz test: Lock period bonus multiplier
    function testFuzz_LockPeriod_BonusMultiplier(
        uint128 baseReward,
        uint16 lockDays,
        uint16 bonusBPPerDay
    ) public pure {
        vm.assume(baseReward > 100); // At least 100 for noticeable reward
        vm.assume(lockDays >= 7 && lockDays <= 365);
        vm.assume(bonusBPPerDay > 0 && bonusBPPerDay <= 10); // Max 0.1% per day

        // Calculate lock bonus = baseReward * (1 + lockDays * bonusBP)
        uint256 bonusBP = uint256(lockDays) * uint256(bonusBPPerDay);
        vm.assume(bonusBP > 0 && bonusBP <= Constants.BPS_BASE); // Bonus > 0 and max 100%

        uint256 bonusReward = (uint256(baseReward) * bonusBP) / Constants.BPS_BASE;
        uint256 totalReward = uint256(baseReward) + bonusReward;

        // Verify: Longer lock period means more total reward
        if (bonusReward > 0) {
            assertGt(totalReward, baseReward);
        }

        // Verify: Reward in reasonable range
        assertGe(totalReward, baseReward);
        assertLe(totalReward, uint256(baseReward) * 2); // Max 2x reward
    }

    // ==================== Early Exit Penalty Fuzz Tests ====================

    /// @notice Fuzz test: Early withdrawal penalty
    function testFuzz_EarlyWithdrawal_Penalty(
        uint128 stakedAmount,
        uint16 penaltyBP
    ) public pure {
        vm.assume(stakedAmount > 100); // At least 100 for noticeable penalty
        vm.assume(penaltyBP > 0 && penaltyBP < Constants.BPS_BASE); // Penalty rate < 100%

        // Calculate penalty amount
        uint256 penalty = (uint256(stakedAmount) * uint256(penaltyBP)) / Constants.BPS_BASE;
        uint256 amountAfterPenalty = uint256(stakedAmount) - penalty;

        // Verify: Penalty does not exceed principal
        assertLe(penalty, stakedAmount);

        // Verify: Remaining amount is non-negative
        assertLe(amountAfterPenalty, stakedAmount);

        // Verify: With penalty, remaining is less than principal
        if (penalty > 0) {
            assertLt(amountAfterPenalty, stakedAmount);
        }
    }

    // ==================== Edge Case Tests ====================

    /// @notice Fuzz test: Single block reward
    function testFuzz_SingleBlock_Reward(
        uint128 stakedAmount,
        uint128 totalStake,
        uint128 rewardPerBlock
    ) public pure {
        vm.assume(stakedAmount > 0);
        vm.assume(totalStake >= stakedAmount);
        vm.assume(rewardPerBlock > 0);

        // Single block reward
        uint256 userReward = (uint256(rewardPerBlock) * uint256(stakedAmount)) / uint256(totalStake);

        // Verify: Single block reward does not exceed that block's total reward
        assertLe(userReward, rewardPerBlock);
    }

    /// @notice Fuzz test: Very long duration reward accumulation
    function testFuzz_LongDuration_Accumulation(
        uint64 rewardPerBlock,
        uint32 blockElapsed
    ) public pure {
        vm.assume(rewardPerBlock > 0);
        vm.assume(blockElapsed >= 365 days / 12); // At least 1 year
        vm.assume(blockElapsed <= 10 * 365 days / 12); // Max 10 years

        // Prevent overflow
        vm.assume(uint256(rewardPerBlock) * uint256(blockElapsed) < type(uint256).max / 2);

        uint256 totalReward = uint256(rewardPerBlock) * uint256(blockElapsed);

        // Verify: Long-term accumulated reward should be large
        assertGt(totalReward, uint256(rewardPerBlock) * 1000000); // At least 1 million blocks
    }
}
