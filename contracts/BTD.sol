// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
 * @title BTD - Bitcoin Dollar Stablecoin
 * @notice Core stablecoin of the Bitres system, pegged to Ideal USD (IUSD), minted with WBTC collateral
 * @dev Supports EIP-2612 Permit for gasless approvals
 *      Uses AccessControl for minting permissions, allowing multiple contracts (Minter, InterestPool) to mint
 *      After deployment, grant MINTER_ROLE to required contracts, then admin should renounce DEFAULT_ADMIN_ROLE
 */
contract BTD is ERC20, ERC20Burnable, AccessControl, ERC20Permit {
    /// @notice Minter role identifier
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /**
     * @notice Constructor
     * @param defaultAdmin Initial admin address (typically deployer, used to assign roles then renounce)
     */
    constructor(
        address defaultAdmin
    )
        ERC20("Bitcoin Dollar", "BTD")
        ERC20Permit("Bitcoin Dollar")
    {
        require(defaultAdmin != address(0), "BTD: zero admin");
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    /**
     * @notice Mint BTD (only MINTER_ROLE can call)
     * @dev Can be called by Minter contract or InterestPool contract
     * @param to Recipient address
     * @param amount Mint amount (18 decimals)
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }
}
