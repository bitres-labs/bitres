// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title BRS - Bitres Governance and Equity Token
 * @notice Governance token for the Bitres system, total supply 2.1 billion, minted at deployment
 * @dev Supports EIP-2612 Permit for gasless approvals
 *      Fixed total supply of 2,100,000,000 BRS, cannot be minted or burned after deployment
 *      Use cases:
 *      1. Governance voting: Holders can participate in on-chain governance proposals
 *      2. Revenue sharing: Part of protocol fees distributed to BRS holders
 *      3. System backstop: Used to compensate redeemers when collateral ratio is insufficient
 */
contract BRS is ERC20, ERC20Permit {
    /** @notice Constructor, mints all 2.1 billion BRS to the specified recipient */
    constructor(
        address recipient  // Address to receive all BRS (typically multisig or distribution contract)
    )
        ERC20("Bitres", "BRS")
        ERC20Permit("Bitres")
    {
        _mint(recipient, 2100000000 * 10 ** decimals());
    }
}
