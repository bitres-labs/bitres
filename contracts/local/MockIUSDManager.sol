// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IIdealUSDManager.sol";

contract MockIUSDManager is IIdealUSDManager {
    uint256 private price;
    uint256 private _lastUpdate;

    constructor(uint256 initialPrice) {
        price = initialPrice;
        _lastUpdate = block.timestamp;
    }

    function getCurrentIUSD() external view override returns (uint256) {
        return price;
    }

    function setPrice(uint256 newPrice) external {
        price = newPrice;
        _lastUpdate = block.timestamp;
    }

    function lastUpdateTime() external view override returns (uint256) {
        return _lastUpdate;
    }
}
