// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/**
 * @title IUniswapV2Callee - Uniswap V2 callback interface
 * @notice Standard interface for receiving Uniswap V2 flash loan callbacks
 */
interface IUniswapV2Callee {
    /**
     * @notice Uniswap V2 flash loan callback function
     * @param sender Address that initiated the swap
     * @param amount0 Amount of token0 borrowed
     * @param amount1 Amount of token1 borrowed
     * @param data Custom data passed to swap
     */
    function uniswapV2Call(address sender, uint amount0, uint amount1, bytes calldata data) external;
}
