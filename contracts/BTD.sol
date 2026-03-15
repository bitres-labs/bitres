// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20BurnableUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {AccessControlUpgradeable} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";

/**
 * @title BTD - Bitcoin Dollar Stablecoin
 * @notice Core stablecoin of the Bitres system, pegged to Ideal USD (IUSD), minted with WBTC collateral
 * @dev UUPS upgradeable. Uses AccessControl for minting permissions.
 *      After deployment, grant MINTER_ROLE to required contracts.
 *      Admin should NOT renounce DEFAULT_ADMIN_ROLE to preserve upgradeability.
 */
contract BTD is Initializable, ERC20Upgradeable, ERC20BurnableUpgradeable, AccessControlUpgradeable, ERC20PermitUpgradeable, UUPSUpgradeable {
    /// @notice Minter role identifier
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize BTD
     * @param defaultAdmin Initial admin address (used to assign roles and authorize upgrades)
     */
    function initialize(address defaultAdmin) public initializer {
        require(defaultAdmin != address(0), "BTD: zero admin");

        __ERC20_init("Bitcoin Dollar", "BTD");
        __ERC20Burnable_init();
        __AccessControl_init();
        __ERC20Permit_init("Bitcoin Dollar");
        __UUPSUpgradeable_init();

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
    }

    /**
     * @notice Mint BTD (only MINTER_ROLE can call)
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
