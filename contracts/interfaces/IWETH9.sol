// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title IWETH9 - Wrapped Ether Interface
/// @notice Interface for the canonical WETH9 contract
interface IWETH9 is IERC20 {
    /// @notice Deposit ETH and receive WETH
    function deposit() external payable;

    /// @notice Withdraw WETH and receive ETH
    /// @param wad Amount of WETH to withdraw
    function withdraw(uint256 wad) external;
}
