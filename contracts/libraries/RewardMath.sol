// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/math/Math.sol";
/**
 * @title RewardMath - Farm Reward Distribution Calculation Library
 * @notice Pure function library for FarmingPool and similar reward distribution modules
 * @dev Provides time-based and weight-based reward calculations using 1e12 precision for accumulated rewards per share
 */
library RewardMath {


    /// @notice Precision for accumulated rewards per share (1e12)
    /// @dev Uses 12 decimals to avoid confusion with token's 18 decimals, reducing precision loss in division
    uint256 internal constant ACC_PRECISION = 1e12;

    /**
     * @notice Calculate rewards a specific pool should receive over a time period
     * @dev Formula: Pool Reward = (Reward Per Second × Pool Weight / Total Weight) × Time
     *      - Uses weight allocation mechanism, similar to Sushi/Curve's MasterChef
     *      - Time is in seconds
     * @param timeElapsed Elapsed time (seconds)
     * @param rewardPerSec Total reward per second (18 decimals)
     * @param allocPoint Pool's weight allocation points
     * @param totalAllocPoint Total weight points of all pools
     * @return Reward the pool should receive (18 decimals)
     */
    function emissionFor(
        uint256 timeElapsed,
        uint256 rewardPerSec,
        uint256 allocPoint,
        uint256 totalAllocPoint
    ) internal pure returns (uint256) {
        if (timeElapsed == 0 || rewardPerSec == 0 || totalAllocPoint == 0) {
            return 0;
        }
        uint256 poolRate = Math.mulDiv(rewardPerSec, allocPoint, totalAllocPoint);
        return poolRate * timeElapsed;
    }

    /**
     * @notice Limit reward to not exceed maximum supply
     * @dev Formula: Actual Reward = min(Planned Reward, Max Supply - Already Minted)
     *      Prevents over-issuance, ensuring total token supply doesn't exceed cap
     * @param minted Already minted amount (18 decimals)
     * @param reward Planned reward amount (18 decimals)
     * @param maxSupply Maximum supply (18 decimals)
     * @return Actual distributable reward (18 decimals)
     */
    function clampToMax(uint256 minted, uint256 reward, uint256 maxSupply) internal pure returns (uint256) {
        if (reward == 0 || minted >= maxSupply) {
            return 0;
        }
        uint256 remaining = maxSupply - minted;
        return reward > remaining ? remaining : reward;
    }

    /**
     * @notice Update accumulated rewards per share
     * @dev Formula: New Accumulated = Current Accumulated + (Pool Reward × 1e12) / Total Staked
     *      - Uses 1e12 precision to improve calculation accuracy for small rewards
     *      - Does not update when total staked is 0
     * @param current Current accumulated rewards per share (1e12 precision)
     * @param poolReward Pool reward for this period (18 decimals)
     * @param totalStaked Total staked amount (18 decimals)
     * @return Updated accumulated rewards per share (1e12 precision)
     */
    function accRewardPerShare(
        uint256 current,
        uint256 poolReward,
        uint256 totalStaked
    ) internal pure returns (uint256) {
        if (poolReward == 0 || totalStaked == 0) {
            return current;
        }
        return current + Math.mulDiv(poolReward, ACC_PRECISION, totalStaked);
    }

    /**
     * @notice Calculate user's pending rewards to be claimed
     * @dev Formula: Pending = (Staked Amount × Accumulated Per Share / 1e12) - Reward Debt
     *      - Uses debt mechanism to prevent duplicate claims
     *      - Returns safely claimable reward amount
     * @param amount Staked amount (18 decimals)
     * @param accPerShare Accumulated rewards per share (1e12 precision)
     * @param rewardDebt Reward debt (18 decimals)
     * @return Pending rewards (18 decimals)
     */
    function pending(uint256 amount, uint256 accPerShare, uint256 rewardDebt) internal pure returns (uint256) {
        uint256 accumulated = Math.mulDiv(amount, accPerShare, ACC_PRECISION);
        return accumulated > rewardDebt ? accumulated - rewardDebt : 0;
    }

    /**
     * @notice Calculate reward debt value
     * @dev Formula: Debt = (Staked Amount × Accumulated Per Share) / 1e12
     *      - Used to record initial debt when staking
     *      - Prevents claiming rewards from before staking
     * @param amount Staked amount (18 decimals)
     * @param accPerShare Accumulated rewards per share (1e12 precision)
     * @return Reward debt value (18 decimals)
     */
    function rewardDebtValue(uint256 amount, uint256 accPerShare) internal pure returns (uint256) {
        if (amount == 0 || accPerShare == 0) {
            return 0;
        }
        return Math.mulDiv(amount, accPerShare, ACC_PRECISION);
    }
}
