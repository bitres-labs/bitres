// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

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
/// @dev Based on Uniswap's ExampleOracleSimple - reads cumulative prices directly from pair
contract UniswapV2TWAPOracle is IUniswapV2TWAPOracle {
    // TWAP observation period (30 minutes for flash loan protection)
    uint256 public constant PERIOD = 30 minutes;

    struct Observation {
        uint32 timestamp;
        uint256 price0Cumulative;
        uint256 price1Cumulative;
    }

    // pair address => [older observation, newer observation]
    mapping(address => Observation[2]) public pairObservations;

    // Events
    event ObservationUpdated(address indexed pair, uint256 price0Cumulative, uint256 price1Cumulative, uint32 timestamp);

    /// @notice Get current cumulative prices from pair (handles time elapsed since last trade)
    /// @dev Based on UniswapV2OracleLibrary.currentCumulativePrices
    function _currentCumulativePrices(address pair) internal view returns (
        uint256 price0Cumulative,
        uint256 price1Cumulative,
        uint32 blockTimestamp
    ) {
        blockTimestamp = uint32(block.timestamp);
        price0Cumulative = IUniswapV2Pair(pair).price0CumulativeLast();
        price1Cumulative = IUniswapV2Pair(pair).price1CumulativeLast();

        // Get reserves and last update time
        (uint112 reserve0, uint112 reserve1, uint32 timestampLast) = IUniswapV2Pair(pair).getReserves();

        // If time has elapsed since last pair update, add the pending cumulative price
        if (timestampLast != blockTimestamp && reserve0 != 0 && reserve1 != 0) {
            uint32 timeElapsed;
            unchecked {
                timeElapsed = blockTimestamp - timestampLast;
            }
            // Add pending price accumulation (Q112 format)
            // IMPORTANT: Cast to uint256 before bit shift to avoid overflow
            unchecked {
                price0Cumulative += (uint256(reserve1) << 112) / reserve0 * timeElapsed;
                price1Cumulative += (uint256(reserve0) << 112) / reserve1 * timeElapsed;
            }
        }
    }

    /// @notice Updates TWAP observation for a trading pair
    /// @dev Should be called periodically (at least every PERIOD) to maintain valid observations
    /// @param pair Uniswap V2 Pair contract address
    function update(address pair) external {
        (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
            _currentCumulativePrices(pair);

        // Shift observations: [1] -> [0], new -> [1]
        pairObservations[pair][0] = pairObservations[pair][1];
        pairObservations[pair][1] = Observation({
            timestamp: blockTimestamp,
            price0Cumulative: price0Cumulative,
            price1Cumulative: price1Cumulative
        });

        emit ObservationUpdated(pair, price0Cumulative, price1Cumulative, blockTimestamp);
    }

    /// @notice Gets TWAP price in Q112 format (token1/token0)
    /// @param pair Uniswap V2 Pair contract address
    /// @return price TWAP price in Q112 format
    function getTWAP(address pair) public view returns (uint256) {
        Observation memory older = pairObservations[pair][0];
        Observation memory newer = pairObservations[pair][1];

        require(newer.timestamp > 0, "No observations");
        require(older.timestamp > 0, "Need two observations");

        uint32 timeElapsed;
        unchecked {
            timeElapsed = newer.timestamp - older.timestamp;
        }
        require(timeElapsed >= PERIOD, "Observation period too short");

        // Calculate TWAP: (cumulative_new - cumulative_old) / time_elapsed
        uint256 priceCumulativeDelta;
        unchecked {
            priceCumulativeDelta = newer.price0Cumulative - older.price0Cumulative;
        }
        return priceCumulativeDelta / timeElapsed;
    }

    /// @notice Gets TWAP price normalized to 18 decimals
    /// @param pair Uniswap V2 Pair contract address
    /// @param token0Decimals Decimals of token0
    /// @param token1Decimals Decimals of token1
    /// @return price Price of token0 in token1, normalized to 18 decimals
    function getTWAPPrice(
        address pair,
        uint8 token0Decimals,
        uint8 token1Decimals
    ) external view returns (uint256) {
        uint256 twapQ112 = getTWAP(pair);

        // Convert from Q112 to 18 decimals
        // twapQ112 is in Q112 format: (reserve1_raw / reserve0_raw) * 2^112
        // This represents "raw units of token1 per raw unit of token0"
        //
        // To get price in 18 decimals (whole token1 per whole token0):
        // price = (twapQ112 / 2^112) * 10^(token0Decimals - token1Decimals) * 10^18
        //
        // IMPORTANT: Multiply BEFORE shifting to preserve precision for small prices
        // e.g., BTD(18)/USDC(6): twapQ112 < 2^112, so shift first would give 0
        //
        // For WBTC(8)/USDC(6): price = (twapQ112 * 100 * 1e18) >> 112
        // For BTD(18)/USDC(6): price = (twapQ112 * 1e12 * 1e18) >> 112

        uint256 price;

        if (token0Decimals >= token1Decimals) {
            // token0 has more decimals - multiply to scale up
            // e.g., BTD(18)/USDC(6): multiply by 1e12
            uint256 decimalAdjust = 10 ** (token0Decimals - token1Decimals);
            // Multiply first, then shift to preserve precision
            price = (twapQ112 * decimalAdjust * 1e18) >> 112;
        } else {
            // token1 has more decimals - divide to scale down
            // e.g., USDC(6)/ETH(18): divide by 1e12
            uint256 decimalAdjust = 10 ** (token1Decimals - token0Decimals);
            // Multiply by 1e18 first, then shift, then divide
            price = ((twapQ112 * 1e18) >> 112) / decimalAdjust;
        }

        return price;
    }

    /// @notice Checks if TWAP is ready for querying
    /// @param pair Uniswap V2 Pair contract address
    /// @return ready True if TWAP can be safely queried
    function isTWAPReady(address pair) external view returns (bool) {
        Observation memory older = pairObservations[pair][0];
        Observation memory newer = pairObservations[pair][1];

        if (newer.timestamp == 0 || older.timestamp == 0) return false;

        uint32 timeElapsed;
        unchecked {
            timeElapsed = newer.timestamp - older.timestamp;
        }
        return timeElapsed >= PERIOD;
    }

    /// @notice Gets observation info for diagnostics
    /// @param pair Uniswap V2 Pair contract address
    function getObservationInfo(address pair) external view returns (
        uint32 olderTimestamp,
        uint32 newerTimestamp,
        uint32 timeElapsed
    ) {
        Observation memory older = pairObservations[pair][0];
        Observation memory newer = pairObservations[pair][1];

        olderTimestamp = older.timestamp;
        newerTimestamp = newer.timestamp;
        unchecked {
            timeElapsed = newer.timestamp - older.timestamp;
        }
    }

    /// @notice Checks if a pair needs TWAP update (>= PERIOD since last update)
    /// @param pair Uniswap V2 Pair contract address
    /// @return True if update is needed
    function needsUpdate(address pair) public view returns (bool) {
        Observation memory newer = pairObservations[pair][1];
        // Needs update if: no observation yet, or >= PERIOD since last
        return newer.timestamp == 0 || block.timestamp >= newer.timestamp + PERIOD;
    }

    /// @notice Updates TWAP only if needed (>= PERIOD since last update)
    /// @dev Saves gas by skipping update if recently updated
    /// @param pair Uniswap V2 Pair contract address
    /// @return updated True if update was performed
    function updateIfNeeded(address pair) external returns (bool updated) {
        if (needsUpdate(pair)) {
            (uint256 price0Cumulative, uint256 price1Cumulative, uint32 blockTimestamp) =
                _currentCumulativePrices(pair);

            pairObservations[pair][0] = pairObservations[pair][1];
            pairObservations[pair][1] = Observation({
                timestamp: blockTimestamp,
                price0Cumulative: price0Cumulative,
                price1Cumulative: price1Cumulative
            });

            emit ObservationUpdated(pair, price0Cumulative, price1Cumulative, blockTimestamp);
            return true;
        }
        return false;
    }
}
