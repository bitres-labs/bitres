// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {ERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title MockUSDT - USDT token for testing
 * @notice Mock USDT with mint functionality for test environment
 */
contract MockUSDT is ERC20, ERC20Permit {
    constructor(address recipient) ERC20("Mock USDT", "USDT") ERC20Permit("Mock USDT") {
        _mint(recipient, 1000000000 * 10 ** decimals());
    }

    // Override the default 18 decimals and set it to 6
    function decimals() public pure override returns (uint8) {
        return 6;
    }

}
