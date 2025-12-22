// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IFunctionsRouter} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/interfaces/IFunctionsRouter.sol";
import {IFunctionsClient} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/interfaces/IFunctionsClient.sol";
import {FunctionsResponse} from "@chainlink/contracts/src/v0.8/functions/v1_0_0/libraries/FunctionsResponse.sol";

/// @notice Minimal mock router for unit testing Functions clients.
contract MockFunctionsRouter is IFunctionsRouter {
    uint256 private _requestCounter;

    uint64 public lastSubscriptionId;
    bytes public lastData;
    uint16 public lastDataVersion;
    uint32 public lastCallbackGasLimit;
    bytes32 public lastDonId;

    mapping(bytes32 => address) public requestSenders;

    function getAllowListId() external pure override returns (bytes32) {
        return bytes32(0);
    }

    function setAllowListId(bytes32) external override {}

    function getAdminFee() external pure override returns (uint72) {
        return 0;
    }

    function sendRequest(
        uint64 subscriptionId,
        bytes calldata data,
        uint16 dataVersion,
        uint32 callbackGasLimit,
        bytes32 donId
    ) external override returns (bytes32 requestId) {
        _requestCounter++;
        requestId = bytes32(_requestCounter);
        lastSubscriptionId = subscriptionId;
        lastData = data;
        lastDataVersion = dataVersion;
        lastCallbackGasLimit = callbackGasLimit;
        lastDonId = donId;
        requestSenders[requestId] = msg.sender;
    }

    function sendRequestToProposed(
        uint64,
        bytes calldata,
        uint16,
        uint32,
        bytes32
    ) external pure override returns (bytes32) {
        return bytes32(0);
    }

    function fulfill(
        bytes memory,
        bytes memory,
        uint96,
        uint96,
        address,
        FunctionsResponse.Commitment memory
    ) external pure override returns (FunctionsResponse.FulfillResult, uint96) {
        return (FunctionsResponse.FulfillResult.FULFILLED, 0);
    }

    function isValidCallbackGasLimit(uint64, uint32) external pure override {}

    function getContractById(bytes32) external pure override returns (address) {
        return address(0);
    }

    function getProposedContractById(bytes32) external pure override returns (address) {
        return address(0);
    }

    function getProposedContractSet()
        external
        pure
        override
        returns (bytes32[] memory ids, address[] memory addresses)
    {
        ids = new bytes32[](0);
        addresses = new address[](0);
    }

    function proposeContractsUpdate(bytes32[] memory, address[] memory) external pure override {}

    function updateContracts() external pure override {}

    function pause() external pure override {}

    function unpause() external pure override {}

    /// @notice Helper to simulate router fulfillment in tests.
    function fulfillRequest(
        address client,
        bytes32 requestId,
        bytes memory response,
        bytes memory err
    ) external {
        IFunctionsClient(client).handleOracleFulfillment(requestId, response, err);
    }
}
