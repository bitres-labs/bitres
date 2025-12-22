// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockWBTC is ERC20, ERC20Permit {
    constructor(address recipient) ERC20("Mock Wrapped BTC", "WBTC") ERC20Permit("Mock Wrapped BTC") {
        // Total supply: 21 million WBTC with 8 decimals
        _mint(recipient, 21000000 * 10 ** decimals());
    }

    // Override the default 18 decimals and set it to 8
    function decimals() public pure override returns (uint8) {
        return 8;
    }
}
