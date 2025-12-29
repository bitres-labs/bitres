// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ICDYFeed} from "../interfaces/ICDYFeed.sol";

/**
 * @title MockCDYFeed
 * @notice Mock implementation of Chainlink DeFi Yield (CDY) oracle for testing
 * @dev Allows setting arbitrary CDY rates for testing interest rate calculations
 */
contract MockCDYFeed is ICDYFeed {
    uint256 private _rateBps;
    uint256 private _updatedAt;

    event RateUpdated(uint256 oldRate, uint256 newRate);

    /**
     * @notice Constructor
     * @param initialRateBps Initial CDY rate in basis points (e.g., 500 = 5%)
     */
    constructor(uint256 initialRateBps) {
        _rateBps = initialRateBps;
        _updatedAt = block.timestamp;
    }

    /**
     * @notice Sets the CDY rate (for testing)
     * @param rateBps New rate in basis points
     */
    function setRate(uint256 rateBps) external {
        uint256 oldRate = _rateBps;
        _rateBps = rateBps;
        _updatedAt = block.timestamp;
        emit RateUpdated(oldRate, rateBps);
    }

    /**
     * @notice Sets the last update timestamp (for testing staleness)
     * @param timestamp New timestamp
     */
    function setUpdatedAt(uint256 timestamp) external {
        _updatedAt = timestamp;
    }

    /**
     * @inheritdoc ICDYFeed
     */
    function getLatestRate() external view override returns (uint256 rateBps, uint256 updatedAt) {
        return (_rateBps, _updatedAt);
    }

    /**
     * @inheritdoc ICDYFeed
     */
    function getRate(uint256 maxAge) external view override returns (uint256 rateBps) {
        require(block.timestamp - _updatedAt <= maxAge, "MockCDYFeed: stale data");
        return _rateBps;
    }

    /**
     * @inheritdoc ICDYFeed
     */
    function isHealthy(uint256 maxAge) external view override returns (bool healthy) {
        return block.timestamp - _updatedAt <= maxAge;
    }
}
