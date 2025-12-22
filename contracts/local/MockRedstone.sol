// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Simplified Redstone DataService mock
contract MockRedstone {
    mapping(bytes32 => uint256) public values;

    function setValue(bytes32 dataFeedId, uint256 price) external {
        values[dataFeedId] = price;
    }

    function getValueForDataFeedId(bytes32 dataFeedId) external view returns (uint256) {
        uint256 val = values[dataFeedId];
        require(val != 0, "Value not set");
        return val;
    }
}
