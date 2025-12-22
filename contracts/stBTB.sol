// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC4626} from "@openzeppelin/contracts/token/ERC20/extensions/ERC4626.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title stBTB - BTB Staking Receipt (Pure ERC4626 Implementation)
 * @notice Standard ERC4626 vault, holding BTB as underlying asset
 * @dev Contains no business logic, serves only as share token
 *      - Users deposit BTB, receive stBTB shares
 *      - stBTB can be transferred, traded, used in DeFi composables
 *      - Redeeming stBTB returns BTB
 *      - Interest logic is managed by external contracts (e.g., InterestPool)
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
}
