// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0 and Community Contracts commit 2d607bd
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockUSDC is ERC20, ERC20Permit {
    constructor(address recipient) ERC20("Mock USDC", "USDC") ERC20Permit("Mock USDC") {
        _mint(recipient, 1000000000 * 10 ** decimals());
    }

    // Override the default 18 decimals and set it to 6
    function decimals() public pure override returns (uint8) {
        return 6;
    }

}
