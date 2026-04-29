// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

contract MockCbBTC is ERC20, ERC20Permit {
    constructor(address recipient) ERC20("Mock Coinbase Wrapped BTC", "cbBTC") ERC20Permit("Mock Coinbase Wrapped BTC") {
        _mint(recipient, 21_000_000 * 10 ** decimals());
    }

    function decimals() public pure override returns (uint8) {
        return 8;
    }
}
