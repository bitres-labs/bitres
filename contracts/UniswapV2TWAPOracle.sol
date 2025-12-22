// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./interfaces/IUniswapV2TWAPOracle.sol";

interface IUniswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint256);
    function price1CumulativeLast() external view returns (uint256);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

/// @title UniswapV2TWAPOracle
/// @notice Time-Weighted Average Price (TWAP) oracle for Uniswap V2
/// @dev Uses cumulative price differences to defend against flash loans, requires periodic updates to maintain observations
contract UniswapV2TWAPOracle is IUniswapV2TWAPOracle {
    using Math for uint256;

    // TWAP observation period (recommended: 10-30 minutes for security)
    uint256 public constant PERIOD = 30 minutes;

    struct Observation {
        uint32 timestamp;  // Note: uint32 will overflow in February 2106, contract upgrade needed by then
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    // pair address => observations
    mapping(address => Observation[2]) public pairObservations;

    // Events
    event ObservationUpdated(address indexed pair, uint256 price0Cumulative, uint256 price1Cumulative, uint32 timestamp);

    /// @notice Updates TWAP observation for a trading pair
    /// @dev Should be called at least every 30 minutes to maintain valid observation window
    ///      Cumulative price overflow is safely handled by Uniswap's Q112 format (expected behavior)
    /// @param pair Uniswap V2 Pair contract address
    function update(address pair) external {
        IUniswapV2Pair uniswapPair = IUniswapV2Pair(pair);

        (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast) = uniswapPair.getReserves();
        uint256 price0Cumulative = uniswapPair.price0CumulativeLast();
        uint256 price1Cumulative = uniswapPair.price1CumulativeLast();

        // Handle Uniswap's cumulative price update logic
        uint32 timeElapsed = blockTimestampLast - pairObservations[pair][1].timestamp;

        if (timeElapsed > 0 && reserve0 != 0 && reserve1 != 0) {
            // Overflow is desired and handled correctly
            unchecked {
                price0Cumulative += uint256((uint224(reserve1) << 112) / reserve0) * timeElapsed;
                price1Cumulative += uint256((uint224(reserve0) << 112) / reserve1) * timeElapsed;
            }
        }

        // Shift observations: [1] -> [0], new -> [1]
        pairObservations[pair][0] = pairObservations[pair][1];
        pairObservations[pair][1] = Observation({
            timestamp: uint32(block.timestamp),
            price0Cumulative: price0Cumulative,
            price1Cumulative: price1Cumulative
        });

        emit ObservationUpdated(pair, price0Cumulative, price1Cumulative, uint32(block.timestamp));
    }

    /// @notice Gets TWAP price in Q112 precision
    /// @dev Calculates time-weighted average price of token0 relative to token1
    ///      Requires observation time interval >= 30 minutes to ensure TWAP validity
    /// @param pair Uniswap V2 Pair contract address
    /// @return price TWAP price (Q112 format, right shift 112 bits to convert to floating point)
    function getTWAP(address pair) public view returns (uint256) {
        Observation memory older = pairObservations[pair][0];
        Observation memory newer = pairObservations[pair][1];

        require(newer.timestamp > 0, "No observations");

        uint32 timeElapsed = newer.timestamp - older.timestamp;
        require(timeElapsed >= PERIOD, "Observation period too short");

        // Calculate TWAP using cumulative prices
        // overflow is desired and handled correctly
        unchecked {
            uint256 priceCumulativeDelta = newer.price0Cumulative - older.price0Cumulative;
            return priceCumulativeDelta / timeElapsed;
        }
    }

    /// @notice Gets TWAP price in standard 18 decimal precision
    /// @dev Converts Q112 format TWAP to standard 1e18 precision
    ///      Automatically handles different token decimal differences
    /// @param pair Uniswap V2 Pair contract address
    /// @param token0Decimals Decimal places of token0 (e.g., USDC is 6)
    /// @param token1Decimals Decimal places of token1 (e.g., WETH is 18)
    /// @return price Price of token0 relative to token1, precision 1e18
    function getTWAPPrice(
        address pair,
        uint8 token0Decimals,
        uint8 token1Decimals
    ) external view returns (uint256) {
        uint256 twapQ112 = getTWAP(pair);

        // Convert Q112 format to 18 decimals
        // price = (twap / 2^112) * (10^token1Decimals / 10^token0Decimals) * 10^18
        uint256 price;

        if (token1Decimals >= token0Decimals) {
            uint256 decimalAdjust = 10 ** (token1Decimals - token0Decimals);
            price = (twapQ112 * decimalAdjust * 1e18) >> 112;
        } else {
            uint256 decimalAdjust = 10 ** (token0Decimals - token1Decimals);
            price = (twapQ112 * 1e18) / decimalAdjust >> 112;
        }

        return price;
    }

    /// @notice Checks if TWAP is ready for querying
    /// @dev Verifies if there is sufficient observation window (>= 30 minutes) to safely query TWAP
    /// @param pair Uniswap V2 Pair contract address
    /// @return ready true means TWAP can be safely queried, false means more observation data needed
    function isTWAPReady(address pair) external view returns (bool) {
        Observation memory older = pairObservations[pair][0];
        Observation memory newer = pairObservations[pair][1];

        if (newer.timestamp == 0) return false;

        uint32 timeElapsed = newer.timestamp - older.timestamp;
        return timeElapsed >= PERIOD;
    }

    /// @notice Gets observation info details
    /// @dev Returns observation window information for the trading pair, used for diagnostics and verification
    /// @param pair Uniswap V2 Pair contract address
    /// @return olderTimestamp Timestamp of older observation point
    /// @return newerTimestamp Timestamp of newer observation point
    /// @return timeElapsed Observation window duration (seconds)
    function getObservationInfo(address pair) external view returns (
        uint32 olderTimestamp,
        uint32 newerTimestamp,
        uint32 timeElapsed
    ) {
        Observation memory older = pairObservations[pair][0];
        Observation memory newer = pairObservations[pair][1];

        olderTimestamp = older.timestamp;
        newerTimestamp = newer.timestamp;
        timeElapsed = newer.timestamp - older.timestamp;
    }
}
