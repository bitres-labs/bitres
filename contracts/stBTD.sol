// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title stBTD - BTD Staking Receipt (Pure ERC4626 Implementation)
 * @notice Standard ERC4626 vault, holding BTD as underlying asset
 * @dev Contains no business logic, serves only as share token
 *      - Users deposit BTD, receive stBTD shares
 *      - stBTD can be transferred, traded, used in DeFi composables
 *      - Redeeming stBTD returns BTD
 *      - Interest logic is managed by external contracts (e.g., InterestPool)
 *      - Supports EIP-2612 permit for gasless approvals via depositWithPermit
 *
 * Architecture Design Principles:
 *      - Single responsibility: only manages BTD share accounting
 *      - No external dependencies: does not depend on any business contracts
 *      - Composability: can be used by any contract or user
 */
contract stBTD is ERC4626, ERC20Permit {
    /**
     * @notice Constructor
     * @param btd BTD token address
     */
    constructor(IERC20 btd)
        ERC20("Staked Bitcoin Dollar", "stBTD")
        ERC20Permit("Staked Bitcoin Dollar")
        ERC4626(btd)
    {}

    /**
     * @notice Gets token decimals (18 digits)
     * @dev Overrides decimals function from ERC20 and ERC4626
     * @return Decimal places
     */
    function decimals() public view override(ERC20, ERC4626) returns (uint8) {
        return super.decimals();
    }

    /**
     * @notice Deposit BTD with permit (gasless approval)
     * @dev Uses EIP-2612 permit to approve and deposit in one transaction
     * @param assets Amount of BTD to deposit
     * @param receiver Address to receive stBTD shares
     * @param deadline Permit deadline timestamp
     * @param v Signature v component
     * @param r Signature r component
     * @param s Signature s component
     * @return shares Amount of stBTD shares minted
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
     * @notice Mint stBTD shares with permit (gasless approval)
     * @dev Uses EIP-2612 permit to approve and mint in one transaction
     * @param shares Amount of stBTD shares to mint
     * @param receiver Address to receive stBTD shares
     * @param deadline Permit deadline timestamp
     * @param v Signature v component
     * @param r Signature r component
     * @param s Signature s component
     * @return assets Amount of BTD deposited
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
}
