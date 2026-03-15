// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC4626Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC4626Upgradeable.sol";
import {ERC20Upgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import {ERC20PermitUpgradeable} from "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title stBTB - BTB Staking Receipt (Pure ERC4626 Implementation)
 * @notice UUPS upgradeable standard ERC4626 vault, holding BTB as underlying asset
 * @dev Contains no business logic, serves only as share token
 *      - Users deposit BTB, receive stBTB shares
 *      - stBTB can be transferred, traded, used in DeFi composables
 *      - Redeeming stBTB returns BTB
 *      - Interest logic is managed by external contracts (e.g., InterestPool)
 *      - Supports EIP-2612 permit for gasless approvals via depositWithPermit
 */
contract stBTB is Initializable, ERC4626Upgradeable, ERC20PermitUpgradeable, Ownable2StepUpgradeable, UUPSUpgradeable {

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize stBTB vault
     * @param btb BTB token address
     * @param initialOwner Owner address for upgrade authorization
     */
    function initialize(IERC20 btb, address initialOwner) public initializer {
        require(address(btb) != address(0), "stBTB: zero asset");
        require(initialOwner != address(0), "stBTB: zero owner");

        __ERC20_init("Staked Bitcoin Bond", "stBTB");
        __ERC4626_init(btb);
        __ERC20Permit_init("Staked Bitcoin Bond");
        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @notice Gets token decimals (18 digits)
     * @dev Overrides decimals function from ERC20Upgradeable and ERC4626Upgradeable
     * @return Decimal places
     */
    function decimals() public view override(ERC20Upgradeable, ERC4626Upgradeable) returns (uint8) {
        return super.decimals();
    }

    /**
     * @notice Deposit BTB with permit (gasless approval)
     * @dev Uses EIP-2612 permit to approve and deposit in one transaction
     * @param assets Amount of BTB to deposit
     * @param receiver Address to receive stBTB shares
     * @param deadline Permit deadline timestamp
     * @param v Signature v component
     * @param r Signature r component
     * @param s Signature s component
     * @return shares Amount of stBTB shares minted
     */
    function depositWithPermit(
        uint256 assets,
        address receiver,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 shares) {
        // Use permit to set allowance
        IERC20Permit(asset()).permit(msg.sender, address(this), assets, deadline, v, r, s);
        // Deposit assets
        return deposit(assets, receiver);
    }

    /**
     * @notice Mint stBTB shares with permit (gasless approval)
     * @dev Uses EIP-2612 permit to approve and mint in one transaction
     * @param shares Amount of stBTB shares to mint
     * @param receiver Address to receive stBTB shares
     * @param deadline Permit deadline timestamp
     * @param v Signature v component
     * @param r Signature r component
     * @param s Signature s component
     * @return assets Amount of BTB deposited
     */
    function mintWithPermit(
        uint256 shares,
        address receiver,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 assets) {
        // Calculate required assets
        assets = previewMint(shares);
        // Use permit to set allowance
        IERC20Permit(asset()).permit(msg.sender, address(this), assets, deadline, v, r, s);
        // Mint shares
        return mint(shares, receiver);
    }

    // ============ Storage Gap ============

    uint256[50] private __gap;
}
