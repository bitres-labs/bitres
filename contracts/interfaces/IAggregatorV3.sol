// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IAggregatorV3 - Chainlink price aggregator V3 interface
 * @notice Standard interface for Chainlink price oracle, used for querying on-chain price data
 */
interface IAggregatorV3 {
    /**
     * @notice Get decimals for price data
     * @return Decimal places for price precision (e.g., 8 means price needs to be divided by 1e8)
     */
    function decimals() external view returns (uint8);

    /**
     * @notice Get latest round price data
     * @return roundId Price round ID
     * @return answer Price answer (needs precision adjustment based on decimals())
     * @return startedAt This round start timestamp
     * @return updatedAt This round update timestamp
     * @return answeredInRound This round answer round ID
     */
    function latestRoundData() external view returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound);
}
