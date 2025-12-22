// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./Constants.sol";

/**
 * @title OracleMath - Oracle Price Calculation Helper Library
 * @notice Provides price deviation checks, precision conversion, spot price calculation, and other functions
 * @dev Encapsulates commonly used oracle data processing logic to ensure price data consistency and security
 */
library OracleMath {


    /**
     * @notice Check if deviation between two prices is within allowed range
     * @dev Formula: |priceA - priceB| / priceA × 10000 <= maxBps
     *      - Uses absolute difference to avoid sign issues
     *      - Uses priceA as the base for percentage calculation
     *      - Optimization: Uses multiplication to avoid division, reducing precision loss
     *
     *      Example:
     *      - priceA = 100, priceB = 103, maxBps = 500 (5%)
     *      - diff = 3, diff × 10000 = 30000
     *      - priceA × maxBps = 100 × 500 = 50000
     *      - 30000 <= 50000, returns true (3% deviation is within 5% range)
     *
     * @param priceA Price A (18 decimals)
     * @param priceB Price B (18 decimals)
     * @param maxBps Maximum allowed deviation (basis points, 500 = 5%)
     * @return Whether deviation is within range
     */
    function deviationWithin(uint256 priceA, uint256 priceB, uint256 maxBps) internal pure returns (bool) {
        if (priceA == 0 || priceB == 0) {
            return false;
        }
        uint256 diff = priceA > priceB ? priceA - priceB : priceB - priceA;
        return diff * Constants.BPS_BASE <= priceA * maxBps;
    }

    /**
     * @notice Calculate the inverse of a price
     * @dev Formula: Inverse Price = 1e36 / Original Price
     *      - Uses 1e36 to maintain 18 decimals: (1e18 × 1e18) / price = 1e18
     *      - Use case: Token A/B price -> Token B/A price
     *
     *      Example:
     *      - ETH/USD = 2000e18 -> USD/ETH = 1e36 / 2000e18 = 0.0005e18
     *
     * @param price Original price (18 decimals)
     * @return Inverse price (18 decimals)
     */
    function inversePrice(uint256 price) internal pure returns (uint256) {
        require(price > 0, "Oracle: zero price");
        return Math.mulDiv(1e36, 1, price);
    }

    /**
     * @notice Normalize any precision amount to 18 decimals
     * @dev Conversion rules:
     *      - decimals = 18: Unchanged
     *      - decimals < 18: Multiply by 10^(18-decimals)
     *      - decimals > 18: Divide by 10^(decimals-18)
     *
     *      Common conversions:
     *      - USDC (6 decimals) -> Normalized: × 1e12
     *      - WBTC (8 decimals) -> Normalized: × 1e10
     *      - DAI (18 decimals) -> Normalized: Unchanged
     *
     * @param amount Original amount
     * @param decimals Original decimals
     * @return Normalized amount (18 decimals)
     */
    function normalizeAmount(uint256 amount, uint8 decimals) internal pure returns (uint256) {
        if (decimals == 18) return amount;
        if (decimals > 18) {
            return amount / (10 ** (decimals - 18));
        }
        return amount * (10 ** (18 - decimals));
    }

    /**
     * @notice Calculate spot price from liquidity pool reserves
     * @dev Formula: Price = (Quote Token Reserve × 1e18) / Base Token Reserve
     *      - Automatically handles precision conversion, normalizing both tokens to 18 decimals
     *      - Returns "how much quote token per unit of base token"
     *
     *      Example (USDC/WBTC pool):
     *      - reserveBase (WBTC) = 10 × 1e8 = 1000000000 (8 decimals)
     *      - reserveQuote (USDC) = 650000 × 1e6 = 650000000000 (6 decimals)
     *      - baseNorm = 10 × 1e18 (normalized)
     *      - quoteNorm = 650000 × 1e18 (normalized)
     *      - Price = 650000 × 1e18 / 10 = 65000e18 (each BTC is worth 65000 USDC)
     *
     * @param reserveBase Base token reserve
     * @param reserveQuote Quote token reserve
     * @param baseDecimals Base token decimals
     * @param quoteDecimals Quote token decimals
     * @return Spot price (18 decimals, quote/base)
     */
    function spotPrice(
        uint256 reserveBase,
        uint256 reserveQuote,
        uint8 baseDecimals,
        uint8 quoteDecimals
    ) internal pure returns (uint256) {
        require(reserveBase > 0, "Oracle: zero reserve");
        uint256 baseNorm = normalizeAmount(reserveBase, baseDecimals);
        uint256 quoteNorm = normalizeAmount(reserveQuote, quoteDecimals);
        return Math.mulDiv(quoteNorm, 1e18, baseNorm);
    }
}
