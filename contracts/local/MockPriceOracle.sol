// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../interfaces/IPriceOracle.sol";

/**
 * @title MockPriceOracle - Price oracle for testing
 * @notice Allows manual price setting for test environment
 */
contract MockPriceOracle is IPriceOracle {
    // Price storage (18 decimal precision)
    uint256 public wbtcPrice;
    uint256 public btdPrice;
    uint256 public btbPrice;
    uint256 public brsPrice;
    uint256 public iusdPrice;

    address public twapOracle;
    bool public useTWAP;

    // Default prices
    constructor() {
        wbtcPrice = 50000e18;  // $50,000
        btdPrice = 1e18;       // $1.00
        btbPrice = 1e18;       // $1.00
        brsPrice = 1e18;       // $1.00
        iusdPrice = 1e18;      // $1.00
        useTWAP = false;       // TWAP disabled by default in test environment
    }

    // ============ Admin Functions ============

    function setWBTCPrice(uint256 _price) external {
        wbtcPrice = _price;
    }

    function setBTDPrice(uint256 _price) external {
        btdPrice = _price;
    }

    function setBTBPrice(uint256 _price) external {
        btbPrice = _price;
    }

    function setBRSPrice(uint256 _price) external {
        brsPrice = _price;
    }

    function setIUSDPrice(uint256 _price) external {
        iusdPrice = _price;
    }

    function setAllPrices(
        uint256 _wbtc,
        uint256 _btd,
        uint256 _btb,
        uint256 _brs,
        uint256 _iusd
    ) external {
        wbtcPrice = _wbtc;
        btdPrice = _btd;
        btbPrice = _btb;
        brsPrice = _brs;
        iusdPrice = _iusd;
    }

    // ============ IPriceOracle Implementation ============

    function getWBTCPrice() external view override returns (uint256) {
        return wbtcPrice;
    }

    function getBTDPrice() external view override returns (uint256) {
        return btdPrice;
    }

    function getBTBPrice() external view override returns (uint256) {
        return btbPrice;
    }

    function getBRSPrice() external view override returns (uint256) {
        return brsPrice;
    }

    function getIUSDPrice() external view override returns (uint256) {
        return iusdPrice;
    }

    function getPrice(address token) external view override returns (uint256) {
        // Simple mock implementation: all tokens return $1 (except WBTC)
        // In actual tests, specific prices can be set via setXXXPrice()
        return 1e18; // Default $1
    }

    function getPrice(address, address, address) external pure override returns (uint256) {
        return 1e18; // Default $1
    }

    function setTWAPOracle(address _twapOracle) external override {
        twapOracle = _twapOracle;
        emit TWAPOracleUpdated(address(0), _twapOracle);
    }

    function setUseTWAP(bool _useTWAP) external override {
        useTWAP = _useTWAP;
        emit TWAPModeChanged(_useTWAP);
    }

    function isTWAPEnabled() external view override returns (bool) {
        return useTWAP;
    }

    function getTWAPOracle() external view override returns (address) {
        return twapOracle;
    }

    function getChainlinkBTCUSD() external view override returns (uint256) {
        return wbtcPrice; // Mock returns the same price
    }

    // ============ TWAP Update Functions (no-op in mock) ============

    function updateTWAPForWBTC() external override {
        // No-op in mock - prices are set manually
    }

    function updateTWAPForBTD() external override {
        // No-op in mock - prices are set manually
    }

    function updateTWAPForBTB() external override {
        // No-op in mock - prices are set manually
    }

    function updateTWAPForBRS() external override {
        // No-op in mock - prices are set manually
    }

    function updateTWAPAll() external override {
        // No-op in mock - prices are set manually
    }
}
