// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title ITreasury - Standard interface for Treasury contract
 * @notice Defines the core functionality interface for the Treasury contract
 */
interface ITreasury {
    // --- Asset Management ---
    /**
     * @notice Deposit WBTC from caller (Minter) to treasury
     * @dev Minter must first receive WBTC from user and approve to Treasury before calling
     * @param amt WBTC amount
     */
    function depositWBTC(uint256 amt) external;

    /**
     * @notice Withdraw WBTC from treasury to caller (Minter)
     * @dev Minter is responsible for transferring WBTC to end user
     * @param amt WBTC amount
     */
    function withdrawWBTC(uint256 amt) external;

    /**
     * @notice Compensate user with BRS tokens from treasury
     * @param to Recipient address
     * @param amt BRS amount
     */
    function compensate(address to, uint256 amt) external;

    /**
     * @notice Buyback BRS using BTD from Uniswap
     * @param btdAmount BTD amount
     * @param minBRSOut Minimum BRS output amount (slippage protection)
     */
    function buybackBRS(uint256 btdAmount, uint256 minBRSOut) external;

    // --- Configuration Management ---
    /**
     * @notice Update Uniswap Router address
     * @param newRouter New Router address
     */
    function setRouter(address newRouter) external;

    // --- Query Functions ---
    function getBalances()
        external
        view
        returns (uint256 wbtcBalance, uint256 brsBalance, uint256 btdBalance);

    function configCore() external view returns (address);
    function router() external view returns (address);

    // --- Events ---
    event WBTCDeposited(address indexed from, uint256 amount);
    event WBTCWithdrawn(address indexed to, uint256 amount);
    event BRSCompensated(address indexed to, uint256 amount);
    event BRSBuyback(uint256 btdAmount, uint256 brsReceived);
}
