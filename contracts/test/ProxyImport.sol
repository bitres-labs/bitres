// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// Re-export ERC1967Proxy so Hardhat generates artifacts for it
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

// Empty contract to force ERC1967Proxy compilation with accessible ABI
contract ProxyHelper {
    // This function is never called - it just forces ERC1967Proxy to be compiled
    function deploy(address impl, bytes memory data) external returns (ERC1967Proxy) {
        return new ERC1967Proxy(impl, data);
    }
}
