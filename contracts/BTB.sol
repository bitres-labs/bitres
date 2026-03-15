// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title BTB - Bitcoin Bond Token
 * @notice Bond token for the Bitres system, issued as compensation to BTD redeemers when collateral ratio is insufficient
 * @dev UUPS upgradeable. Uses AccessControl for minting permissions.
 *      When system collateral ratio recovers above 100%, BTB holders can redeem 1:1 for BTD.
 *      Admin should NOT renounce DEFAULT_ADMIN_ROLE to preserve upgradeability.
 */
contract BTB is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, AccessControlUpgradeable, ERC20PermitUpgradeable, UUPSUpgradeable {
    /// @notice Minter role identifier
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize BTB
     * @param defaultAdmin Initial admin address (used to assign roles and authorize upgrades)
     */
    function initialize(address defaultAdmin) public initializer {
        require(defaultAdmin != address(0), "BTB: zero admin");

        __ERC20_init("Bitcoin Bond", "BTB");
        __ERC20Burnable_init();
        __AccessControl_init();
        __ERC20Permit_init("Bitcoin Bond");
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    /**
     * @notice Mint BTB (only MINTER_ROLE can call)
     * @param to Recipient address
     * @param amount Mint amount (18 decimals)
     */
    function mint(address to, uint256 amount) public onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address) internal override onlyRole(DEFAULT_ADMIN_ROLE) {}

    // ============ Storage Gap ============

    uint256[50] private __gap;
}
