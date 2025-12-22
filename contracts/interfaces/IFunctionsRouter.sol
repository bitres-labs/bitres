// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IFunctionsRouter - Chainlink Functions router interface
 * @notice Standard interface for managing Chainlink Functions subscriptions and consumers
 */
interface IFunctionsRouter {
    /**
     * @notice Add consumer to specified subscription
     * @param subscriptionId Chainlink Functions subscription ID
     * @param consumer Consumer contract address
     */
    function addConsumer(uint64 subscriptionId, address consumer) external;

    /**
     * @notice Remove consumer from specified subscription
     * @param subscriptionId Chainlink Functions subscription ID
     * @param consumer Consumer contract address
     */
    function removeConsumer(uint64 subscriptionId, address consumer) external;

    /**
     * @notice Check if address is a consumer of specified subscription
     * @param subscriptionId Chainlink Functions subscription ID
     * @param consumer Address to check
     * @return true if consumer, false otherwise
     */
    function getConsumer(uint64 subscriptionId, address consumer) external view returns (bool);
}
