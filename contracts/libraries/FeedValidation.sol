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
    /**
     * @notice Read and validate Chainlink oracle price data
     * @dev Execution flow:
     *      1. Verify oracle address is non-zero
     *      2. Read oracle precision (decimals)
     *      3. Call latestRoundData to get latest price
     *      4. Verify price is positive
     *      5. Normalize price to 18 decimals
     *
     *      Security checks:
     *      - Oracle address must be non-zero
     *      - Returned price must be greater than 0 (prevents negative or zero prices)
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
        (, int256 answer, , , ) = feed.latestRoundData();
        require(answer > 0, "Invalid feed price");
        return OracleMath.normalizeAmount(uint256(answer), decimals);
    }
}
