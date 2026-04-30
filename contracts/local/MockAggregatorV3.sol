// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Mock Chainlink AggregatorV3Interface
contract MockAggregatorV3 {
    int256 private _answer;
    uint8 private _decimals = 8; // Default Chainlink commonly uses 8 decimals
    uint80 private _roundId = 1;
    uint256 private _startedAt = block.timestamp;
    uint256 private _updatedAt = block.timestamp;
    uint80 private _answeredInRound = 1;
    bool private _customRoundData;

    constructor(int256 initialAnswer) {
        _answer = initialAnswer;
    }

    function setDecimals(uint8 newDecimals) external {
        _decimals = newDecimals;
    }

    function setAnswer(int256 newAnswer) external {
        _answer = newAnswer;
    }

    function setRoundData(
        uint80 newRoundId,
        uint256 newStartedAt,
        uint256 newUpdatedAt,
        uint80 newAnsweredInRound
    ) external {
        _roundId = newRoundId;
        _startedAt = newStartedAt;
        _updatedAt = newUpdatedAt;
        _answeredInRound = newAnsweredInRound;
        _customRoundData = true;
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
        if (!_customRoundData) {
            return (_roundId, _answer, block.timestamp, block.timestamp, _answeredInRound);
        }
        return (_roundId, _answer, _startedAt, _updatedAt, _answeredInRound);
    }
}
