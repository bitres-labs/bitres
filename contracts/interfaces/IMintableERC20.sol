// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IMintableERC20 - Mintable ERC20 interface
 * @notice Defines the standard interface for ERC20 tokens with mint and burn functionality
 * @dev Applicable to system tokens such as BTD, BTB, BRS
 */
interface IMintableERC20 is IERC20 {
    /**
     * @notice Mint tokens
     * @param to Recipient address
     * @param amount Amount to mint
     */
    function mint(address to, uint256 amount) external;

    /**
     * @notice Burn tokens from a specified account
     * @param account Account to burn from
     * @param amount Amount to burn
     */
    function burnFrom(address account, uint256 amount) external;
}
