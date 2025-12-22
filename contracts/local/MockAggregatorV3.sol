// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Mock Chainlink AggregatorV3Interface
contract MockAggregatorV3 {
    int256 private _answer;
    uint8 private _decimals = 8; // Default Chainlink commonly uses 8 decimals

    constructor(int256 initialAnswer) {
        _answer = initialAnswer;
    }

    function setDecimals(uint8 newDecimals) external {
        _decimals = newDecimals;
    }

    function setAnswer(int256 newAnswer) external {
        _answer = newAnswer;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        )
    {
        return (0, _answer, 0, block.timestamp, 0);
    }
}
