// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title ICDYFeed - Chainlink DeFi Yield (CDY) Oracle Interface
 * @notice Interface for reading CDY rate from Chainlink oracle
 * @dev CDY provides a reference DeFi yield rate, used as anchor for BTD/BTB interest rates
 *      See: https://cdy.chain.link/
 *
 * The CDY rate represents a benchmark yield rate in the DeFi ecosystem.
 * It is used to anchor BTD deposit rates and BTB bond rates per whitepaper Section 7.1.3.
 */
interface ICDYFeed {
    /**
     * @notice Get the latest CDY rate
     * @dev Returns the current CDY rate in basis points (100 = 1%)
     *      This is typically the annualized yield rate
     * @return rateBps CDY rate in basis points
     * @return updatedAt Timestamp of last update
     */
    function getLatestRate() external view returns (uint256 rateBps, uint256 updatedAt);

    /**
     * @notice Get the CDY rate with staleness check
     * @dev Reverts if rate is stale (older than maxAge seconds)
     * @param maxAge Maximum acceptable age in seconds
     * @return rateBps CDY rate in basis points
     */
    function getRate(uint256 maxAge) external view returns (uint256 rateBps);

    /**
     * @notice Check if the CDY feed is healthy
     * @dev Returns true if the feed is operational and data is fresh
     * @param maxAge Maximum acceptable age in seconds
     * @return healthy True if feed is healthy
     */
    function isHealthy(uint256 maxAge) external view returns (bool healthy);
}
