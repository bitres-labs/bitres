// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title MockWETH
 * @notice Mock Wrapped Ether for local testing with deposit/withdraw functionality
 * @dev Implements the core WETH interface: deposit ETH to get WETH, withdraw WETH to get ETH
 */
contract MockWETH is ERC20 {
    // Events
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    constructor(address recipient) ERC20("Mock Wrapped Ether", "WETH") {
        // Initial supply: 120 million WETH for testing
        _mint(recipient, 120000000 * 10 ** decimals());
    }

    // WETH uses standard 18 decimals
    function decimals() public pure override returns (uint8) {
        return 18;
    }

    /**
     * @notice Deposit ETH and receive WETH
     * @dev Payable function that mints WETH equal to msg.value
     */
    function deposit() public payable {
        _mint(msg.sender, msg.value);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice Withdraw WETH and receive ETH
     * @dev Burns WETH and sends ETH to caller
     * @param wad Amount of WETH to withdraw
     */
    function withdraw(uint256 wad) public {
        require(balanceOf(msg.sender) >= wad, "Insufficient WETH balance");
        _burn(msg.sender, wad);
        payable(msg.sender).transfer(wad);
        emit Withdrawal(msg.sender, wad);
    }

    /**
     * @notice Receive ETH and automatically deposit
     * @dev Allows sending ETH directly to contract
     */
    receive() external payable {
        deposit();
    }

    /**
     * @notice Fallback function
     * @dev Calls deposit when ETH is sent
     */
    fallback() external payable {
        deposit();
    }
}
