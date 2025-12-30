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

    /**
     * @notice Tries to update IUSD if enough time has passed (lazy update)
     * @dev Can be called by anyone, designed for Minter to call during user operations
     * @return updated True if IUSD was actually updated
     */
    function tryUpdateIUSD() external returns (bool updated);
}
