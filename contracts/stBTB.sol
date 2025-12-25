// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";

/**
 * @title stBTB - BTB Staking Receipt (Pure ERC4626 Implementation)
 * @notice Standard ERC4626 vault, holding BTB as underlying asset
 * @dev Contains no business logic, serves only as share token
 *      - Users deposit BTB, receive stBTB shares
 *      - stBTB can be transferred, traded, used in DeFi composables
 *      - Redeeming stBTB returns BTB
 *      - Interest logic is managed by external contracts (e.g., InterestPool)
 *      - Supports EIP-2612 permit for gasless approvals via depositWithPermit
 *
 * Architecture Design Principles:
 *      - Single responsibility: only manages BTB share accounting
 *      - No external dependencies: does not depend on any business contracts
 *      - Composability: can be used by any contract or user
 */
contract stBTB is ERC4626, ERC20Permit {
    /**
     * @notice Constructor
     * @param btb BTB token address
     */
    constructor(IERC20 btb)
        ERC20("Staked Bitcoin Bond", "stBTB")
        ERC20Permit("Staked Bitcoin Bond")
        ERC4626(btb)
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
}
