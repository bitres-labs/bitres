// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IIdealUSDManager - Standard interface for IdealUSDManager contract
 * @notice Defines the core functionality interface for the IdealUSDManager contract
 */
interface IIdealUSDManager {
    /**
     * @notice Get the current Ideal USD value (IUSD)
     * @return The current IUSD value (18 decimal precision)
     */
    function getCurrentIUSD() external view returns (uint256);

    /**
     * @notice Get the timestamp of the last update
     * @return The update timestamp
     */
    function lastUpdateTime() external view returns (uint256);
}
