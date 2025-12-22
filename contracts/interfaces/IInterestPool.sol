// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IInterestPool - Standard interface for interest pool
 * @notice Defines the core functionality interface for the InterestPool contract
 * @dev Users can directly stake BTD/BTB to the interest pool without going through vault
 */
interface IInterestPool {
    // ============ BTD Operations ============

    /**
     * @notice Stake BTD to the interest pool
     * @param amount BTD amount
     */
    function stakeBTD(uint256 amount) external;

    /**
     * @notice Unstake BTD
     * @param amount BTD amount
     */
    function unstakeBTD(uint256 amount) external;

    // ============ BTB Operations ============

    /**
     * @notice Stake BTB to the interest pool
     * @param amount BTB amount
     */
    function stakeBTB(uint256 amount) external;

    /**
     * @notice Unstake BTB
     * @param amount BTB amount
     */
    function unstakeBTB(uint256 amount) external;

    // ============ Interest Rate Management ============

    /**
     * @notice Update BTD annual rate (read on-chain from FFR Oracle)
     * @dev No parameters needed, reads latest rate directly from FFR Oracle
     */
    function updateBTDAnnualRate() external;

    /**
     * @notice Update BTB annual rate (automatically adjusts based on BTB price)
     */
    function updateBTBAnnualRate() external;

    // ============ Events ============

    event Staked(address indexed user, address indexed token, uint256 amount);
    event Withdrawn(address indexed user, address indexed token, uint256 amount);
    event InterestClaimed(address indexed user, address indexed token, uint256 amount);
    event BTDAnnualRateUpdated(uint256 oldRateBps, uint256 newRateBps);
    event BTBAnnualRateUpdated(uint256 oldRateBps, uint256 newRateBps, uint256 price, int256 dailyChangeBps);
}
