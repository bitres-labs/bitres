// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/// @notice Simplified Pyth mock for local testing getPriceUnsafe
contract MockPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    mapping(bytes32 => Price) private prices;

    function setPrice(bytes32 id, int64 price, int32 expo) external {
        prices[id] = Price({
            price: price,
            conf: 0,
            expo: expo,
            publishTime: block.timestamp
        });
    }

    function getPriceUnsafe(bytes32 id) external view returns (Price memory) {
        Price memory p = prices[id];
        require(p.price != 0, "Price not set");
        // Always return current block.timestamp to prevent staleness in local testing
        p.publishTime = block.timestamp;
        return p;
    }
}
