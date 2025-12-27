// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IUniswapV2TWAPOracle
 * @notice Uniswap V2 Time-Weighted Average Price (TWAP) oracle interface
 * @dev Defines the standard interface for TWAP Oracle, used to prevent flash loan price manipulation
 */
interface IUniswapV2TWAPOracle {

    /**
     * @notice Get the TWAP price for a trading pair
     * @param pair Uniswap V2 pair address
     * @param token0Decimals Decimals of token0
     * @param token1Decimals Decimals of token1
     * @return TWAP price (18 decimal precision)
     * @dev Returns the TWAP price of token1 denominated in token0
     */
    function getTWAPPrice(address pair, uint8 token0Decimals, uint8 token1Decimals)
        external view returns (uint256);

    /**
     * @notice Check if TWAP is ready
     * @param pair Uniswap V2 pair address
     * @return true if TWAP has been initialized and is ready to use
     * @dev Should check this function before calling getTWAPPrice
     */
    function isTWAPReady(address pair) external view returns (bool);

    /**
     * @notice Update the cumulative price for a trading pair
     * @param pair Uniswap V2 pair address
     * @dev Should be called periodically to maintain accurate TWAP data
     */
    function update(address pair) external;

    /**
     * @notice Check if a pair needs TWAP update
     * @param pair Uniswap V2 pair address
     * @return true if >= PERIOD has passed since last update
     */
    function needsUpdate(address pair) external view returns (bool);

    /**
     * @notice Update TWAP only if needed (>= PERIOD since last update)
     * @param pair Uniswap V2 pair address
     * @return updated True if update was performed
     * @dev Saves gas by skipping if recently updated
     */
    function updateIfNeeded(address pair) external returns (bool updated);
}
