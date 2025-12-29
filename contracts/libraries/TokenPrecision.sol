// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./Constants.sol";

/**
 * @title TokenPrecision - Static Token Precision Conversion Library
 * @notice Provides static precision lookup and conversion for whitelisted tokens
 * @dev All conversions use compile-time constants, zero runtime overhead
 *
 * Design principles:
 * 1. Whitelist only - reverts for unknown tokens
 * 2. Static constants - no decimals() calls
 * 3. Gas optimal - constant inlining
 *
 * Supported tokens:
 * - WBTC: 8 decimals (scale factor 1e10)
 * - USDC: 6 decimals (scale factor 1e12)
 * - USDT: 6 decimals (scale factor 1e12)
 * - All others (BTD, BTB, BRS, stBTD, stBTB, WETH): 18 decimals (no conversion)
 */
library TokenPrecision {
    // ============ Errors ============

    /// @notice Thrown when an unsupported token is passed
    error UnsupportedToken(address token);

    // ============ Decimals Lookup ============

    /**
     * @notice Get token decimals (static lookup)
     * @dev Only supports whitelisted tokens from ConfigCore
     * @param token Token address
     * @param wbtc WBTC address from ConfigCore
     * @param usdc USDC address from ConfigCore
     * @param usdt USDT address from ConfigCore
     * @return Token decimals (8, 6, or 18)
     */
    function getDecimals(
        address token,
        address wbtc,
        address usdc,
        address usdt
    ) internal pure returns (uint8) {
        if (token == wbtc) return 8;
        if (token == usdc) return 6;
        if (token == usdt) return 6;
        // All other whitelisted tokens are 18 decimals
        // (BTD, BTB, BRS, stBTD, stBTB, WETH, LP tokens)
        return 18;
    }

    // ============ To Normalized (18 decimals) ============

    /**
     * @notice Convert token amount to normalized 18-decimal amount
     * @dev Uses static scale factors based on token address
     * @param token Token address
     * @param amount Token amount in native decimals
     * @param wbtc WBTC address from ConfigCore
     * @param usdc USDC address from ConfigCore
     * @param usdt USDT address from ConfigCore
     * @return Normalized amount (18 decimals)
     */
    function toNormalized(
        address token,
        uint256 amount,
        address wbtc,
        address usdc,
        address usdt
    ) internal pure returns (uint256) {
        if (token == wbtc) {
            return amount * Constants.SCALE_WBTC_TO_NORM;
        }
        if (token == usdc) {
            return amount * Constants.SCALE_USDC_TO_NORM;
        }
        if (token == usdt) {
            return amount * Constants.SCALE_USDT_TO_NORM;
        }
        // 18-decimal tokens: no conversion needed
        return amount;
    }

    /**
     * @notice Convert WBTC amount to normalized (simplified version)
     * @dev Use when token type is known at compile time
     * @param amount WBTC amount (8 decimals)
     * @return Normalized amount (18 decimals)
     */
    function wbtcToNormalized(uint256 amount) internal pure returns (uint256) {
        return amount * Constants.SCALE_WBTC_TO_NORM;
    }

    /**
     * @notice Convert USDC amount to normalized (simplified version)
     * @dev Use when token type is known at compile time
     * @param amount USDC amount (6 decimals)
     * @return Normalized amount (18 decimals)
     */
    function usdcToNormalized(uint256 amount) internal pure returns (uint256) {
        return amount * Constants.SCALE_USDC_TO_NORM;
    }

    /**
     * @notice Convert USDT amount to normalized (simplified version)
     * @dev Use when token type is known at compile time
     * @param amount USDT amount (6 decimals)
     * @return Normalized amount (18 decimals)
     */
    function usdtToNormalized(uint256 amount) internal pure returns (uint256) {
        return amount * Constants.SCALE_USDT_TO_NORM;
    }

    // ============ From Normalized (to native decimals) ============

    /**
     * @notice Convert normalized amount back to token's native decimals
     * @dev Uses static scale factors for division
     * @param token Token address
     * @param normalizedAmount Amount in 18 decimals
     * @param wbtc WBTC address from ConfigCore
     * @param usdc USDC address from ConfigCore
     * @param usdt USDT address from ConfigCore
     * @return Amount in token's native decimals
     */
    function fromNormalized(
        address token,
        uint256 normalizedAmount,
        address wbtc,
        address usdc,
        address usdt
    ) internal pure returns (uint256) {
        if (token == wbtc) {
            return normalizedAmount / Constants.SCALE_WBTC_TO_NORM;
        }
        if (token == usdc) {
            return normalizedAmount / Constants.SCALE_USDC_TO_NORM;
        }
        if (token == usdt) {
            return normalizedAmount / Constants.SCALE_USDT_TO_NORM;
        }
        // 18-decimal tokens: no conversion needed
        return normalizedAmount;
    }

    /**
     * @notice Convert normalized amount to WBTC (simplified version)
     * @dev Use when token type is known at compile time
     * @param normalizedAmount Amount in 18 decimals
     * @return WBTC amount (8 decimals)
     */
    function normalizedToWbtc(uint256 normalizedAmount) internal pure returns (uint256) {
        return normalizedAmount / Constants.SCALE_WBTC_TO_NORM;
    }

    /**
     * @notice Convert normalized amount to USDC (simplified version)
     * @dev Use when token type is known at compile time
     * @param normalizedAmount Amount in 18 decimals
     * @return USDC amount (6 decimals)
     */
    function normalizedToUsdc(uint256 normalizedAmount) internal pure returns (uint256) {
        return normalizedAmount / Constants.SCALE_USDC_TO_NORM;
    }

    /**
     * @notice Convert normalized amount to USDT (simplified version)
     * @dev Use when token type is known at compile time
     * @param normalizedAmount Amount in 18 decimals
     * @return USDT amount (6 decimals)
     */
    function normalizedToUsdt(uint256 normalizedAmount) internal pure returns (uint256) {
        return normalizedAmount / Constants.SCALE_USDT_TO_NORM;
    }

    // ============ Scale Factor Lookup ============

    /**
     * @notice Get scale factor for token -> normalized conversion
     * @dev Returns 1 for 18-decimal tokens
     * @param token Token address
     * @param wbtc WBTC address from ConfigCore
     * @param usdc USDC address from ConfigCore
     * @param usdt USDT address from ConfigCore
     * @return Scale factor (multiply to normalize, divide to denormalize)
     */
    function getScaleToNorm(
        address token,
        address wbtc,
        address usdc,
        address usdt
    ) internal pure returns (uint256) {
        if (token == wbtc) return Constants.SCALE_WBTC_TO_NORM;
        if (token == usdc) return Constants.SCALE_USDC_TO_NORM;
        if (token == usdt) return Constants.SCALE_USDT_TO_NORM;
        return 1; // 18-decimal tokens
    }
}
