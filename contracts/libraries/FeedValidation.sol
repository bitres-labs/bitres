// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IAggregatorV3.sol";
import "./OracleMath.sol";

/**
 * @title FeedValidation - Oracle Data Validation Library
 * @notice Encapsulates Chainlink oracle data reading and validation logic
 * @dev Provides standardized price data reading interface with automatic precision conversion
 */
library FeedValidation {
    /// @notice Maximum staleness for Chainlink price data (1 hour)
    /// @dev Chainlink BTC/USD updates every ~1 hour, so 1 hour + buffer is reasonable
    uint256 internal constant MAX_STALENESS = 3600;

    /// @notice Maximum staleness for PCE data (35 days)
    /// @dev Chainlink PCE Feed has 35-day heartbeat (monthly macroeconomic data)
    uint256 internal constant MAX_PCE_STALENESS = 35 days;

    /**
     * @notice Read and validate Chainlink oracle price data
     * @dev Execution flow:
     *      1. Verify oracle address is non-zero
     *      2. Read oracle precision (decimals)
     *      3. Call latestRoundData to get latest price
     *      4. Validate roundId, updatedAt, and answeredInRound
     *      5. Verify price is positive and not stale
     *      6. Normalize price to 18 decimals
     *
     *      Security checks:
     *      - Oracle address must be non-zero
     *      - Returned price must be greater than 0 (prevents negative or zero prices)
     *      - updatedAt must be non-zero (data was actually updated)
     *      - answeredInRound must be >= roundId (prevents stale round data)
     *      - Price must not be older than MAX_STALENESS seconds
     *
     *      Precision conversion:
     *      - BTC/USD: 8 decimals -> 18 decimals
     *      - ETH/USD: 18 decimals -> 18 decimals (unchanged)
     *      - Others: Automatically converted based on decimals
     *
     * @param feedAddress Chainlink oracle contract address
     * @return Normalized price (18 decimals)
     */
    function readAggregator(address feedAddress) internal view returns (uint256) {
        require(feedAddress != address(0), "Feed not set");
        IAggregatorV3 feed = IAggregatorV3(feedAddress);
        uint8 decimals = feed.decimals();

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        // Validate price is positive
        require(answer > 0, "Invalid feed price");

        // Validate round data is complete
        require(updatedAt > 0, "Incomplete round data");

        // Validate we're not using stale round data
        require(answeredInRound >= roundId, "Stale round data");

        // Validate price freshness
        require(block.timestamp - updatedAt <= MAX_STALENESS, "Price data too old");

        return OracleMath.normalizeAmount(uint256(answer), decimals);
    }

    /**
     * @notice Read and validate Chainlink PCE oracle data
     * @dev Similar to readAggregator but uses MAX_PCE_STALENESS (35 days) for freshness check
     *      PCE (Personal Consumption Expenditures) is monthly macroeconomic data
     *      Chainlink PCE Feed has 35-day heartbeat, so 1-hour staleness is inappropriate
     *
     *      Security checks (same as readAggregator):
     *      - Oracle address must be non-zero
     *      - Returned price must be greater than 0
     *      - updatedAt must be non-zero
     *      - answeredInRound must be >= roundId
     *      - Data must not be older than MAX_PCE_STALENESS (35 days)
     *
     * @param feedAddress Chainlink PCE oracle contract address
     * @return Normalized PCE value (18 decimals)
     */
    function readPCEAggregator(address feedAddress) internal view returns (uint256) {
        require(feedAddress != address(0), "PCE Feed not set");
        IAggregatorV3 feed = IAggregatorV3(feedAddress);
        uint8 decimals = feed.decimals();

        (
            uint80 roundId,
            int256 answer,
            ,
            uint256 updatedAt,
            uint80 answeredInRound
        ) = feed.latestRoundData();

        // Validate price is positive
        require(answer > 0, "Invalid PCE value");

        // Validate round data is complete
        require(updatedAt > 0, "Incomplete PCE round data");

        // Validate we're not using stale round data
        require(answeredInRound >= roundId, "Stale PCE round data");

        // Validate PCE freshness (35 days for monthly data)
        require(block.timestamp - updatedAt <= MAX_PCE_STALENESS, "PCE data too old");

        return OracleMath.normalizeAmount(uint256(answer), decimals);
    }
}
