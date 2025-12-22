// SPDX-License-Identifier: MIT
pragma solidity >=0.5.0;

/**
 * @title IUniswapV2Factory - Uniswap V2 factory contract interface
 * @notice Standard interface for creating and managing Uniswap V2 trading pairs
 */
interface IUniswapV2Factory {
    /**
     * @notice Emitted when a new pair is created
     * @param token0 First token address
     * @param token1 Second token address
     * @param pair Newly created pair address
     */
    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    /**
     * @notice Get fee recipient address
     * @return Fee recipient address
     */
    function feeTo() external view returns (address);

    /**
     * @notice Get fee setter address
     * @return Fee setter address
     */
    function feeToSetter() external view returns (address);

    /**
     * @notice Get pair address for two tokens
     * @param tokenA Token A address
     * @param tokenB Token B address
     * @return pair Pair address, returns zero address if not exists
     */
    function getPair(address tokenA, address tokenB) external view returns (address pair);

    /**
     * @notice Get pair address by index
     * @param index Pair index
     * @return pair Pair address
     */
    function allPairs(uint index) external view returns (address pair);

    /**
     * @notice Get total number of pairs
     * @return Total number of pairs
     */
    function allPairsLength() external view returns (uint);

    /**
     * @notice Create a new trading pair
     * @param tokenA Token A address
     * @param tokenB Token B address
     * @return pair Newly created pair address
     */
    function createPair(address tokenA, address tokenB) external returns (address pair);

    /**
     * @notice Set fee recipient address
     * @param _feeTo New fee recipient address
     */
    function setFeeTo(address _feeTo) external;

    /**
     * @notice Set fee setter address
     * @param _feeToSetter New fee setter address
     */
    function setFeeToSetter(address _feeToSetter) external;
}
