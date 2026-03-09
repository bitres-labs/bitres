// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.5.0
pragma solidity ^0.8.27;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit, Nonces} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import {ERC20Votes} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Votes.sol";

/**
 * @title BRS - Bitres Governance and Equity Token
 * @notice Governance token for the Bitres system, total supply 2.1 billion, minted at deployment
 * @dev Supports EIP-2612 Permit for gasless approvals and ERC20Votes for on-chain governance
 *      Fixed total supply of 2,100,000,000 BRS, cannot be minted or burned after deployment
 *      Use cases:
 *      1. Governance voting: Holders can participate in on-chain governance proposals
 *      2. Revenue sharing: Part of protocol fees distributed to BRS holders
 *      3. System backstop: Used to compensate redeemers when collateral ratio is insufficient
 */
contract BRS is ERC20, ERC20Permit, ERC20Votes {
    /** @notice Constructor, mints all 2.1 billion BRS to the specified recipient */
    constructor(
        address recipient  // Address to receive all BRS (typically multisig or distribution contract)
    )
        ERC20("Bitres", "BRS")
        ERC20Permit("Bitres")
    {
        _mint(recipient, 2100000000 * 10 ** decimals());
    }

    // Required overrides for ERC20Votes + ERC20 compatibility

    function _update(address from, address to, uint256 value)
        internal
        override(ERC20, ERC20Votes)
    {
        super._update(from, to, value);
    }

    function nonces(address owner)
        public
        view
        override(ERC20Permit, Nonces)
        returns (uint256)
    {
        return super.nonces(owner);
    }
}
