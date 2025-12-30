// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./Constants.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title SigmoidRate - Sigmoid-based Interest Rate Calculation Library
 * @notice Implements interest rate calculations using Sigmoid functions per whitepaper Section 7.1.3
 * @dev Pure function library for BTD and BTB rate calculations
 *
 * Key formulas:
 * - Base Rate: rbase(CR) = rdefault × (1 + ΔCR), clamped to [rmin, rmax]
 * - Final Rate: r(P) = rmax × S(-α × (P - 1) + β)
 *   where β = ln(rbase / (rmax - rbase))
 *
 * Base Rate Adjustment (ΔCR):
 * - CR > 100%: ΔCR < 0, rate decreases toward 2%
 * - CR = 100%: ΔCR = 0, rate = 5% (default)
 * - CR < 100%: ΔCR > 0, rate increases toward max
 *
 * BTD: rmax = 10%, range [2%, 10%], ΔCR multiplier = 1
 * BTB: rmax = 20%, range [2%, 20%], ΔCR multiplier = 3 (higher risk compensation)
 *
 * All values use 18 decimal precision unless otherwise noted.
 * Rates are returned in basis points (1% = 100 bps).
 */
library SigmoidRate {
    // ============ Rate Limits ============

    /// @notice BTD maximum rate (10% = 1000 bps)
    uint256 internal constant BTD_R_MAX_BPS = 1000;

    /// @notice BTB maximum rate (20% = 2000 bps)
    uint256 internal constant BTB_R_MAX_BPS = 2000;

    /// @notice Minimum rate for both tokens (2% = 200 bps)
    uint256 internal constant R_MIN_BPS = 200;

    // ============ Sigmoid Parameters ============

    /// @notice BTD Sigmoid steepness parameter (α = 25, scaled by 1e18)
    /// @dev Price range 0.8-1.2
    uint256 internal constant ALPHA_BTD = 25 * Constants.PRECISION_18;

    /// @notice BTB Sigmoid steepness parameter (α = 10, scaled by 1e18)
    /// @dev Price range 0.5-1.5
    uint256 internal constant ALPHA_BTB = 10 * Constants.PRECISION_18;

    // ============ CR Parameters ============

    /// @notice CR threshold (100% = 1e18)
    uint256 internal constant CR_THRESHOLD = Constants.PRECISION_18;

    /// @notice CR upper bound for rate reduction (150% = 1.5e18)
    uint256 internal constant CR_UPPER = 15e17;

    /// @notice Minimum CR (20% = 0.2e18)
    uint256 internal constant CR_MIN = 2e17;

    /// @notice ΔCR denominator for CR < 100% (0.8 = 8e17)
    uint256 internal constant DELTA_CR_DENOM_DOWN = 8e17;

    /// @notice ΔCR denominator for CR > 100% (0.5 = 5e17)
    uint256 internal constant DELTA_CR_DENOM_UP = 5e17;

    /// @notice Maximum ΔCR for rate reduction (-0.6, so rate = 5% × 0.4 = 2%)
    int256 internal constant DELTA_CR_MIN = -6e17;

    /// @notice BTB ΔCR multiplier (3x for higher risk compensation)
    uint256 internal constant BTB_DELTA_CR_MULTIPLIER = 3;

    /// @notice Fixed-point 1.0 (1e18)
    uint256 internal constant ONE = Constants.PRECISION_18;

    // ============ Lookup Table for e^x ============

    uint256 internal constant EXP_NEG_10 = 45399929762484;
    uint256 internal constant EXP_NEG_5 = 6737946999085467;
    uint256 internal constant EXP_NEG_4 = 18315638888734180;
    uint256 internal constant EXP_NEG_3 = 49787068367863943;
    uint256 internal constant EXP_NEG_2 = 135335283236612692;
    uint256 internal constant EXP_NEG_1 = 367879441171442322;
    uint256 internal constant EXP_0 = 1000000000000000000;
    uint256 internal constant EXP_1 = 2718281828459045235;
    uint256 internal constant EXP_2 = 7389056098930650227;
    uint256 internal constant EXP_3 = 20085536923187667741;
    uint256 internal constant EXP_4 = 54598150033144239078;
    uint256 internal constant EXP_5 = 148413159102576603421;
    uint256 internal constant EXP_10 = 22026465794806716516957;

    // ============ BTD Rate Calculation ============

    /**
     * @notice Calculate BTD deposit rate using Sigmoid function
     * @dev Formula: rBTD(P) = rmax × S(-α × (P - 1) + β)
     *      where β = ln(rbase / (rmax - rbase))
     *      Base rate range: 2%-10%, α = 25
     * @param price BTD/IUSD price ratio (18 decimals, 1e18 = 1.0)
     * @param cr System collateral ratio (18 decimals, 1e18 = 100%)
     * @param defaultRateBps Default base rate in bps (governance parameter, typically 500)
     * @return rateBps BTD deposit rate in basis points
     */
    function calculateBTDRate(
        uint256 price,
        uint256 cr,
        uint256 defaultRateBps
    ) internal pure returns (uint256 rateBps) {
        // Calculate base rate based on CR
        uint256 baseRateBps = _calculateBTDBaseRate(cr, defaultRateBps);

        // Clamp base rate to valid range
        if (baseRateBps < R_MIN_BPS) baseRateBps = R_MIN_BPS;
        if (baseRateBps > BTD_R_MAX_BPS) baseRateBps = BTD_R_MAX_BPS;

        // If base rate is at max, return max
        if (baseRateBps >= BTD_R_MAX_BPS) {
            return BTD_R_MAX_BPS;
        }

        // Calculate β = ln(rbase / (rmax - rbase))
        int256 beta = _calculateBeta(baseRateBps, BTD_R_MAX_BPS);

        // Calculate x = -α × (P - 1) + β
        int256 priceDeviation = int256(price) - int256(ONE);
        int256 alphaTerm = -int256(Math.mulDiv(ALPHA_BTD, _abs(priceDeviation), ONE));
        if (priceDeviation > 0) {
            alphaTerm = -alphaTerm;
        }

        int256 x = alphaTerm + beta;

        // Calculate Sigmoid: S(x) = e^x / (1 + e^x)
        uint256 sigmoidValue = _sigmoid(x);

        // Rate = rmax × S(x)
        rateBps = Math.mulDiv(BTD_R_MAX_BPS, sigmoidValue, ONE);

        // Clamp to valid range
        if (rateBps < R_MIN_BPS) rateBps = R_MIN_BPS;
        if (rateBps > BTD_R_MAX_BPS) rateBps = BTD_R_MAX_BPS;
    }

    /**
     * @notice Calculate BTD base rate based on collateral ratio
     * @dev Formula: rbase = rdefault × (1 + ΔCR)
     *      CR > 100%: ΔCR = -0.6 × (CR - 1) / 0.5, capped at -0.6
     *      CR = 100%: ΔCR = 0
     *      CR < 100%: ΔCR = (1 - CR) / 0.8, capped at 1.0
     * @param cr Collateral ratio (18 decimals)
     * @param defaultRateBps Default rate in bps
     * @return Base rate in basis points
     */
    function _calculateBTDBaseRate(uint256 cr, uint256 defaultRateBps) internal pure returns (uint256) {
        int256 deltaCR = _calculateBTDDeltaCR(cr);

        // rbase = rdefault × (1 + ΔCR)
        int256 multiplier = int256(ONE) + deltaCR;
        if (multiplier <= 0) multiplier = 1; // Prevent zero/negative

        return Math.mulDiv(defaultRateBps, uint256(multiplier), ONE);
    }

    /**
     * @notice Calculate BTD ΔCR based on collateral ratio
     * @param cr Collateral ratio (18 decimals)
     * @return ΔCR (18 decimals, can be negative)
     */
    function _calculateBTDDeltaCR(uint256 cr) internal pure returns (int256) {
        if (cr >= CR_UPPER) {
            // CR >= 150%: ΔCR = -0.6 (minimum, rate = 2%)
            return DELTA_CR_MIN;
        } else if (cr > CR_THRESHOLD) {
            // 100% < CR < 150%: linear decrease
            // ΔCR = -0.6 × (CR - 1) / 0.5
            uint256 excess = cr - CR_THRESHOLD;
            int256 delta = -int256(Math.mulDiv(6e17, excess, DELTA_CR_DENOM_UP));
            return delta < DELTA_CR_MIN ? DELTA_CR_MIN : delta;
        } else if (cr >= CR_MIN) {
            // 20% <= CR < 100%: ΔCR = (1 - CR) / 0.8
            uint256 deficit = CR_THRESHOLD - cr;
            uint256 delta = Math.mulDiv(deficit, ONE, DELTA_CR_DENOM_DOWN);
            return int256(delta > ONE ? ONE : delta); // Cap at 1.0
        } else {
            // CR < 20%: ΔCR = 1.0 (maximum, rate = 10%)
            return int256(ONE);
        }
    }

    // ============ BTB Rate Calculation ============

    /**
     * @notice Calculate BTB bond rate using Sigmoid function with CR adjustment
     * @dev Formula: rBTB(P) = rmax × S(-α × (P - 1) + β)
     *      Base rate has 3x ΔCR multiplier for higher risk compensation
     *      Base rate range: 2%-20%, α = 10
     * @param price BTB/BTD price ratio (18 decimals, 1e18 = 1.0)
     * @param cr System collateral ratio (18 decimals, 1e18 = 100%)
     * @param defaultRateBps Default base rate in bps (governance parameter)
     * @return rateBps BTB bond rate in basis points
     */
    function calculateBTBRate(
        uint256 price,
        uint256 cr,
        uint256 defaultRateBps
    ) internal pure returns (uint256 rateBps) {
        // Calculate base rate based on CR (with 3x multiplier)
        uint256 baseRateBps = _calculateBTBBaseRate(cr, defaultRateBps);

        // Clamp base rate to valid range
        if (baseRateBps < R_MIN_BPS) baseRateBps = R_MIN_BPS;
        if (baseRateBps > BTB_R_MAX_BPS) baseRateBps = BTB_R_MAX_BPS;

        // If base rate is at max, return max
        if (baseRateBps >= BTB_R_MAX_BPS) {
            return BTB_R_MAX_BPS;
        }

        // Calculate β = ln(rbase / (rmax - rbase))
        int256 beta = _calculateBeta(baseRateBps, BTB_R_MAX_BPS);

        // Calculate x = -α × (P - 1) + β
        int256 priceDeviation = int256(price) - int256(ONE);
        int256 alphaTerm = -int256(Math.mulDiv(ALPHA_BTB, _abs(priceDeviation), ONE));
        if (priceDeviation > 0) {
            alphaTerm = -alphaTerm;
        }

        int256 x = alphaTerm + beta;

        // Calculate Sigmoid
        uint256 sigmoidValue = _sigmoid(x);

        // Rate = rmax × S(x)
        rateBps = Math.mulDiv(BTB_R_MAX_BPS, sigmoidValue, ONE);

        // Clamp to valid range
        if (rateBps < R_MIN_BPS) rateBps = R_MIN_BPS;
        if (rateBps > BTB_R_MAX_BPS) rateBps = BTB_R_MAX_BPS;
    }

    /**
     * @notice Calculate BTB base rate based on collateral ratio
     * @dev Same formula as BTD but with 3x ΔCR multiplier for risk compensation
     *      CR > 100%: same as BTD (rate decreases to 2%)
     *      CR < 100%: ΔCR = 3 × (1 - CR) / 0.8, capped at 3.0 (rate = 20%)
     * @param cr Collateral ratio (18 decimals)
     * @param defaultRateBps Default rate in bps
     * @return Base rate in basis points
     */
    function _calculateBTBBaseRate(uint256 cr, uint256 defaultRateBps) internal pure returns (uint256) {
        int256 deltaCR = _calculateBTBDeltaCR(cr);

        // rbase = rdefault × (1 + ΔCR)
        int256 multiplier = int256(ONE) + deltaCR;
        if (multiplier <= 0) multiplier = 1;

        return Math.mulDiv(defaultRateBps, uint256(multiplier), ONE);
    }

    /**
     * @notice Calculate BTB ΔCR based on collateral ratio
     * @dev Has 3x multiplier compared to BTD for higher risk compensation
     * @param cr Collateral ratio (18 decimals)
     * @return ΔCR (18 decimals, can be negative)
     */
    function _calculateBTBDeltaCR(uint256 cr) internal pure returns (int256) {
        if (cr >= CR_UPPER) {
            // CR >= 150%: ΔCR = -0.6 (same as BTD)
            return DELTA_CR_MIN;
        } else if (cr > CR_THRESHOLD) {
            // 100% < CR < 150%: linear decrease (same as BTD)
            uint256 excess = cr - CR_THRESHOLD;
            int256 delta = -int256(Math.mulDiv(6e17, excess, DELTA_CR_DENOM_UP));
            return delta < DELTA_CR_MIN ? DELTA_CR_MIN : delta;
        } else if (cr >= CR_MIN) {
            // 20% <= CR < 100%: ΔCR = 3 × (1 - CR) / 0.8, capped at 3.0
            uint256 deficit = CR_THRESHOLD - cr;
            uint256 delta = Math.mulDiv(deficit * BTB_DELTA_CR_MULTIPLIER, ONE, DELTA_CR_DENOM_DOWN);
            return int256(delta > 3 * ONE ? 3 * ONE : delta);
        } else {
            // CR < 20%: ΔCR = 3.0 (maximum, rate = 20%)
            return int256(3 * ONE);
        }
    }

    // ============ Public Helpers ============

    /**
     * @notice Get BTD base rate for given CR
     * @param cr Collateral ratio (18 decimals)
     * @param defaultRateBps Default rate in bps
     * @return Base rate in basis points
     */
    function getBTDBaseRate(uint256 cr, uint256 defaultRateBps) internal pure returns (uint256) {
        uint256 rate = _calculateBTDBaseRate(cr, defaultRateBps);
        if (rate < R_MIN_BPS) return R_MIN_BPS;
        if (rate > BTD_R_MAX_BPS) return BTD_R_MAX_BPS;
        return rate;
    }

    /**
     * @notice Get BTB base rate for given CR
     * @param cr Collateral ratio (18 decimals)
     * @param defaultRateBps Default rate in bps
     * @return Base rate in basis points
     */
    function getBTBBaseRate(uint256 cr, uint256 defaultRateBps) internal pure returns (uint256) {
        uint256 rate = _calculateBTBBaseRate(cr, defaultRateBps);
        if (rate < R_MIN_BPS) return R_MIN_BPS;
        if (rate > BTB_R_MAX_BPS) return BTB_R_MAX_BPS;
        return rate;
    }

    // ============ Internal Math Functions ============

    /**
     * @notice Calculate β = ln(rate / (rmax - rate))
     */
    function _calculateBeta(uint256 rateBps, uint256 maxRateBps) internal pure returns (int256 beta) {
        if (rateBps == 0 || rateBps >= maxRateBps) {
            if (rateBps == 0) return -10 * int256(ONE);
            return 10 * int256(ONE);
        }

        uint256 numerator = rateBps * ONE;
        uint256 denominator = maxRateBps - rateBps;
        uint256 ratio = numerator / denominator;

        return _ln(ratio);
    }

    /**
     * @notice Sigmoid function: S(x) = e^x / (1 + e^x)
     */
    function _sigmoid(int256 x) internal pure returns (uint256) {
        if (x >= 10 * int256(ONE)) {
            return ONE;
        }
        if (x <= -10 * int256(ONE)) {
            return 0;
        }

        uint256 expX = _exp(x);
        uint256 denominator = ONE + expX;

        if (denominator == 0) {
            return ONE;
        }

        return Math.mulDiv(expX, ONE, denominator);
    }

    /**
     * @notice Approximate e^x using lookup table
     */
    function _exp(int256 x) internal pure returns (uint256) {
        if (x >= 10 * int256(ONE)) {
            return EXP_10;
        }
        if (x <= -10 * int256(ONE)) {
            return EXP_NEG_10;
        }

        int256 intPart = x / int256(ONE);
        uint256 fracPart;
        if (x >= 0) {
            fracPart = uint256(x % int256(ONE));
        } else {
            int256 remainder = x % int256(ONE);
            if (remainder != 0) {
                intPart -= 1;
                fracPart = uint256(int256(ONE) + remainder);
            }
        }

        uint256 baseExp = _getExpLookup(intPart);

        if (fracPart == 0) {
            return baseExp;
        }

        uint256 expFrac = ONE + fracPart + Math.mulDiv(fracPart, fracPart, 2 * ONE);
        return Math.mulDiv(baseExp, expFrac, ONE);
    }

    /**
     * @notice Get e^n from lookup table
     */
    function _getExpLookup(int256 n) internal pure returns (uint256) {
        if (n == 0) return EXP_0;
        if (n == 1) return EXP_1;
        if (n == 2) return EXP_2;
        if (n == 3) return EXP_3;
        if (n == 4) return EXP_4;
        if (n == 5) return EXP_5;
        if (n >= 10) return EXP_10;
        if (n == -1) return EXP_NEG_1;
        if (n == -2) return EXP_NEG_2;
        if (n == -3) return EXP_NEG_3;
        if (n == -4) return EXP_NEG_4;
        if (n == -5) return EXP_NEG_5;
        if (n <= -10) return EXP_NEG_10;

        if (n > 5) {
            uint256 t = uint256(n - 5) * ONE / 5;
            return EXP_5 + Math.mulDiv(EXP_10 - EXP_5, t, ONE);
        }
        if (n < -5) {
            uint256 t = uint256(-5 - n) * ONE / 5;
            return EXP_NEG_5 - Math.mulDiv(EXP_NEG_5 - EXP_NEG_10, t, ONE);
        }

        return EXP_0;
    }

    /**
     * @notice Approximate natural logarithm ln(x)
     */
    function _ln(uint256 x) internal pure returns (int256) {
        if (x == 0) {
            return -10 * int256(ONE);
        }
        if (x == ONE) {
            return 0;
        }

        int256 power = 0;
        uint256 xNorm = x;

        while (xNorm >= EXP_1) {
            xNorm = Math.mulDiv(xNorm, ONE, EXP_1);
            power += 1;
        }

        while (xNorm < ONE && power > -10) {
            xNorm = Math.mulDiv(xNorm, EXP_1, ONE);
            power -= 1;
        }

        int256 num = int256(xNorm) - int256(ONE);
        uint256 denom = xNorm + ONE;
        int256 z = (num * int256(ONE)) / int256(denom);

        int256 z2 = (z * z) / int256(ONE);
        int256 z3 = (z2 * z) / int256(ONE);
        int256 z5 = (z3 * z2) / int256(ONE);
        int256 z7 = (z5 * z2) / int256(ONE);

        int256 lnX = 2 * (z + z3 / 3 + z5 / 5 + z7 / 7);

        return lnX + (power * int256(ONE));
    }

    /**
     * @notice Absolute value of int256
     */
    function _abs(int256 x) internal pure returns (uint256) {
        return x >= 0 ? uint256(x) : uint256(-x);
    }
}
