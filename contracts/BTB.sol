// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title BTB - Bitcoin Bond Token
 * @notice Bond token for the Bitres system, issued as compensation to BTD redeemers when collateral ratio is insufficient
 * @dev Supports EIP-2612 Permit for gasless approvals
 *      When system collateral ratio recovers above 100%, BTB holders can redeem 1:1 for BTD
 *      Uses AccessControl for minting permissions, allowing multiple contracts (Minter, InterestPool) to mint
 *      After deployment, grant MINTER_ROLE to required contracts, then admin should renounce DEFAULT_ADMIN_ROLE
 */
contract BTB is ERC20, ERC20Burnable, AccessControl, ERC20Permit {
    /// @notice Minter role identifier
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @notice Constructor
     * @param defaultAdmin Initial admin address (typically deployer, used to assign roles then renounce)
     */
    constructor(
        address defaultAdmin
    )
        ERC20("Bitcoin Bond", "BTB")
        ERC20Permit("Bitcoin Bond")
    {
        require(defaultAdmin != address(0), "BTB: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    /**
     * @notice Mint BTB (only MINTER_ROLE can call)
     * @dev Can be called by Minter contract or InterestPool contract
     * @param to Recipient address
     * @param amount Mint amount (18 decimals)
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
}
