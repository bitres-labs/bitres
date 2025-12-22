// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./Constants.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title InterestMath - Interest Accumulation and Reward Distribution Calculation Library
 * @notice Pure function library encapsulating all interest accumulation and reward distribution calculations
 * @dev Provides mathematical calculation support for interest pools, staking rewards, and similar scenarios
 */
library InterestMath {


    /**
     * @notice Calculate pending rewards to be claimed
     * @dev Formula: Pending Rewards = (Staked Amount × Accumulated Interest Per Share) / 1e18 - Reward Debt
     *      Uses debt mechanism to prevent duplicate claims
     * @param amount Staked amount (18 decimals)
     * @param accInterestPerShare Accumulated interest per share (18 decimals)
     * @param rewardDebt Reward debt (18 decimals)
     * @return Pending reward amount (18 decimals)
     */
    function pendingReward(uint256 amount, uint256 accInterestPerShare, uint256 rewardDebt) internal pure returns (uint256) {
        if (amount == 0 || accInterestPerShare == 0) {
            return 0;
        }
        uint256 accumulated = Math.mulDiv(amount, accInterestPerShare, Constants.PRECISION_18);
        return accumulated > rewardDebt ? accumulated - rewardDebt : 0;
    }

    /**
     * @notice Calculate interest per share delta over a time period
     * @dev Formula: delta = (Annual Rate × Time) / (10000 × 365 days)
     *      - Annual rate is expressed in basis points (1% = 100 bps)
     *      - Time is in seconds
     *      - Returns delta value with 18 decimals
     * @param annualRateBps Annual rate (basis points, 100 = 1%)
     * @param timeElapsed Elapsed time (seconds)
     * @return Interest per share delta (18 decimals)
     */
    function interestPerShareDelta(uint256 annualRateBps, uint256 timeElapsed) internal pure returns (uint256) {
        if (annualRateBps == 0 || timeElapsed == 0) {
            return 0;
        }
        uint256 scaled = Math.mulDiv(annualRateBps, Constants.PRECISION_18, 1);
        scaled = Math.mulDiv(scaled, timeElapsed, 1);
        uint256 denominator = Constants.BPS_BASE * Constants.SECONDS_PER_YEAR;
        return Math.mulDiv(scaled, 1, denominator);
    }

    /**
     * @notice Calculate reward debt value
     * @dev Formula: Debt = (Staked Amount × Accumulated Interest Per Share) / 1e18
     *      Used to record initial debt when staking, preventing claims of historical rewards
     * @param amount Staked amount (18 decimals)
     * @param accInterestPerShare Accumulated interest per share (18 decimals)
     * @return Reward debt value (18 decimals)
     */
    function rewardDebtValue(uint256 amount, uint256 accInterestPerShare) internal pure returns (uint256) {
        if (amount == 0 || accInterestPerShare == 0) {
            return 0;
        }
        return Math.mulDiv(amount, accInterestPerShare, Constants.PRECISION_18);
    }

    /**
     * @notice Calculate fee amount
     * @dev Formula: Fee = (Amount × Fee Basis Points) / 10000
     *      - Fee rate is expressed in basis points (100 bps = 1%)
     * @param amount Original amount (any precision)
     * @param feeBps Fee basis points (100 = 1%)
     * @return Fee amount (same precision as input)
     */
    function feeAmount(uint256 amount, uint256 feeBps) internal pure returns (uint256) {
        if (amount == 0 || feeBps == 0) {
            return 0;
        }
        return Math.mulDiv(amount, feeBps, Constants.BPS_BASE);
    }

    /**
     * @notice Split withdrawal amount into interest and principal proportionally
     * @dev Formula:
     *      Interest Portion = (Withdrawal Amount × Pending Interest) / Total Available
     *      Principal Portion = Withdrawal Amount - Interest Portion
     *      Interest is used first, shortfall is covered by principal
     * @param amount Withdrawal amount (18 decimals)
     * @param pendingInterest Pending interest (18 decimals)
     * @param totalAvailable Total available amount (18 decimals)
     * @return interestShare Interest portion (18 decimals)
     * @return principalShare Principal portion (18 decimals)
     */
    function splitWithdrawal(uint256 amount, uint256 pendingInterest, uint256 totalAvailable) internal pure returns (uint256 interestShare, uint256 principalShare) {
        if (amount == 0) {
            return (0, 0);
        }
        if (totalAvailable == 0 || pendingInterest == 0) {
            return (0, amount);
        }
        interestShare = Math.mulDiv(amount, pendingInterest, totalAvailable);
        if (interestShare > amount) {
            interestShare = amount;
        }
        principalShare = amount - interestShare;
    }

    /**
     * @notice Calculate total assets including accrued interest
     * @dev Formula: Total Assets = Principal + (Principal × Interest Delta)
     *      Interest Delta = (Annual Rate × Elapsed Time) / (10000 × 365 days)
     *      Used for real-time queries of total assets including unsettled interest
     * @param principal Principal amount (18 decimals)
     * @param annualRateBps Annual rate (basis points)
     * @param lastAccrual Last settlement time (Unix timestamp)
     * @param currentTimestamp Current time (Unix timestamp)
     * @return Total assets (18 decimals)
     */
    function totalAssetsWithAccrued(
        uint256 principal,
        uint256 annualRateBps,
        uint256 lastAccrual,
        uint256 currentTimestamp
    ) internal pure returns (uint256) {
        if (principal == 0) {
            return 0;
        }
        if (currentTimestamp <= lastAccrual || annualRateBps == 0) {
            return principal;
        }
        uint256 elapsed = currentTimestamp - lastAccrual;
        uint256 delta = interestPerShareDelta(annualRateBps, elapsed);
        if (delta == 0) {
            return principal;
        }
        uint256 interest = Math.mulDiv(principal, delta, Constants.PRECISION_18);
        return principal + interest;
    }

    /**
     * @notice Calculate price change percentage (basis points)
     * @dev Formula: Change Rate = ((Current Price - Previous Price) / Previous Price) × 10000
     *      - Returns positive value for price increase
     *      - Returns negative value for price decrease
     *      - Returns 0 for unchanged price
     * @param previousPrice Previous price (18 decimals)
     * @param currentPrice Current price (18 decimals)
     * @return Price change rate (basis points, 100 = 1%)
     */
    function priceChangeBps(uint256 previousPrice, uint256 currentPrice) internal pure returns (int256) {
        if (previousPrice == 0 || currentPrice == previousPrice) {
            return 0;
        }
        if (currentPrice > previousPrice) {
            uint256 delta = Math.mulDiv(currentPrice - previousPrice, Constants.BPS_BASE, previousPrice);
            return int256(delta);
        }
        uint256 negDelta = Math.mulDiv(previousPrice - currentPrice, Constants.BPS_BASE, previousPrice);
        return -int256(negDelta);
    }
}
