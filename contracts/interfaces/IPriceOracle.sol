// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IPriceOracle - Standard interface for price oracle
 * @notice Provides a unified price query interface for the entire BRS system
 * @dev All prices are returned with 18 decimal precision (1e18 = $1)
 */
interface IPriceOracle {
    // ============ Events ============

    event TWAPOracleUpdated(address indexed oldOracle, address indexed newOracle);
    event TWAPModeChanged(bool enabled);
    event PriceQueried(address indexed token, uint256 price, uint256 timestamp);

    // ============ Core Price Query Interface ============

    /**
     * @notice Get WBTC/USD price (multi-oracle verification)
     * @dev Aggregates Chainlink (WBTC/BTC & BTC/USD), Pyth, Redstone as reference,
     *      Uniswap TWAP/spot as final price, requires deviation <1% from reference median
     * @return price WBTC price, 18 decimal precision (e.g., $50,000 = 50000e18)
     */
    function getWBTCPrice() external view returns (uint256 price);

    /**
     * @notice Get BTD/USD actual market price
     * @dev Queries BTD's actual market price from Uniswap BTD/USDC pool
     *      Note: This is BTD's actual trading price, which may deviate from IUSD target price
     * @return price BTD price, 18 decimal precision
     */
    function getBTDPrice() external view returns (uint256 price);

    /**
     * @notice Get BTB/USD price
     * @dev Calculated via chain: BTB/BTD x BTD/USDC = BTB/USD
     * @return price BTB price, 18 decimal precision
     */
    function getBTBPrice() external view returns (uint256 price);

    /**
     * @notice Get BRS/USD price
     * @dev Calculated via chain: BRS/BTD x BTD/USDC = BRS/USD
     * @return price BRS price, 18 decimal precision
     */
    function getBRSPrice() external view returns (uint256 price);

    /**
     * @notice Get IUSD price (Ideal USD)
     * @dev Queries current IUSD value from IdealUSDManager contract
     * @return price IUSD price, 18 decimal precision
     */
    function getIUSDPrice() external view returns (uint256 price);

    /**
     * @notice Get USD price by token address (generic price query)
     * @dev Supports WBTC, BTD, BTB, BRS, USDC, USDT
     * @param token Token address
     * @return price Token's USD price, 18 decimal precision
     */
    function getPrice(address token) external view returns (uint256 price);

    /**
     * @notice Get generic token pair price
     * @dev Automatically uses TWAP (if enabled) or spot price
     * @param pool Uniswap V2 pair address
     * @param base Base token address
     * @param quote Quote token address
     * @return price Price (quote/base), 18 decimal precision
     */
    function getPrice(address pool, address base, address quote)
        external view returns (uint256 price);

    // ============ TWAP Management Interface ============

    /**
     * @notice Set TWAP Oracle address
     * @param _twapOracle UniswapV2TWAPOracle contract address
     */
    function setTWAPOracle(address _twapOracle) external;

    /**
     * @notice Enable or disable TWAP mode
     * @dev TWAP mode should be enabled in production, can be disabled in test environment
     * @param _useTWAP true=use TWAP (secure), false=use spot price (testing only)
     */
    function setUseTWAP(bool _useTWAP) external;

    /**
     * @notice Check if TWAP is enabled
     * @return enabled true=TWAP is enabled
     */
    function isTWAPEnabled() external view returns (bool enabled);

    /**
     * @notice Get TWAP Oracle address
     * @return oracle TWAP Oracle contract address
     */
    function getTWAPOracle() external view returns (address oracle);

    // ============ Chainlink Related ============

    /**
     * @notice Get Chainlink BTC/USD price
     * @dev Used only as validator, not as primary price source
     * @return price BTC/USD price, 18 decimal precision
     */
    function getChainlinkBTCUSD() external view returns (uint256 price);
}
