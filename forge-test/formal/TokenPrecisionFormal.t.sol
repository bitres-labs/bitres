// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/TokenPrecision.sol";
import "../../contracts/libraries/Constants.sol";

/**
 * @title TokenPrecision Formal Verification Tests
 * @notice Formal verification tests using Halmos symbolic execution
 * @dev Tests prefixed with "check_" are symbolic tests for Halmos
 *      Tests prefixed with "test_" are concrete tests for Foundry
 *
 * Key properties verified:
 * 1. Round-trip identity: fromNormalized(toNormalized(x)) == x
 * 2. Monotonicity: a <= b => toNormalized(a) <= toNormalized(b)
 * 3. Scale factor consistency: toNormalized(x) == x * scaleFactor
 * 4. Zero preservation: toNormalized(0) == 0, fromNormalized(0) == 0
 * 5. 18-decimal pass-through: 18-decimal tokens are unchanged
 */
contract TokenPrecisionFormalTest is Test {

    // Mock addresses for testing
    address constant MOCK_WBTC = address(0x1);
    address constant MOCK_USDC = address(0x2);
    address constant MOCK_USDT = address(0x3);
    address constant MOCK_BTD = address(0x4);

    // ============ Round-Trip Identity ============

    /**
     * @notice Verify WBTC round-trip: fromNormalized(toNormalized(x)) == x
     * @dev This is the critical property for precision conversion correctness
     */
    function check_wbtc_roundtrip_identity(uint64 wbtcAmount) public pure {
        uint256 normalized = TokenPrecision.toNormalized(MOCK_WBTC, wbtcAmount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 recovered = TokenPrecision.fromNormalized(MOCK_WBTC, normalized, MOCK_WBTC, MOCK_USDC, MOCK_USDT);

        assert(recovered == wbtcAmount);
    }

    /**
     * @notice Verify USDC round-trip identity
     */
    function check_usdc_roundtrip_identity(uint64 usdcAmount) public pure {
        uint256 normalized = TokenPrecision.toNormalized(MOCK_USDC, usdcAmount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 recovered = TokenPrecision.fromNormalized(MOCK_USDC, normalized, MOCK_WBTC, MOCK_USDC, MOCK_USDT);

        assert(recovered == usdcAmount);
    }

    /**
     * @notice Verify USDT round-trip identity
     */
    function check_usdt_roundtrip_identity(uint64 usdtAmount) public pure {
        uint256 normalized = TokenPrecision.toNormalized(MOCK_USDT, usdtAmount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 recovered = TokenPrecision.fromNormalized(MOCK_USDT, normalized, MOCK_WBTC, MOCK_USDC, MOCK_USDT);

        assert(recovered == usdtAmount);
    }

    /**
     * @notice Verify 18-decimal tokens round-trip identity
     */
    function check_18decimal_roundtrip_identity(uint128 amount) public pure {
        uint256 normalized = TokenPrecision.toNormalized(MOCK_BTD, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 recovered = TokenPrecision.fromNormalized(MOCK_BTD, normalized, MOCK_WBTC, MOCK_USDC, MOCK_USDT);

        assert(recovered == amount);
    }

    // ============ Monotonicity ============

    /**
     * @notice Verify toNormalized is monotonic for WBTC
     * @dev a <= b implies toNormalized(a) <= toNormalized(b)
     */
    function check_wbtc_monotonic(uint64 a, uint64 b) public pure {
        vm.assume(a <= b);

        uint256 normA = TokenPrecision.toNormalized(MOCK_WBTC, a, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 normB = TokenPrecision.toNormalized(MOCK_WBTC, b, MOCK_WBTC, MOCK_USDC, MOCK_USDT);

        assert(normA <= normB);
    }

    /**
     * @notice Verify toNormalized is monotonic for USDC
     */
    function check_usdc_monotonic(uint64 a, uint64 b) public pure {
        vm.assume(a <= b);

        uint256 normA = TokenPrecision.toNormalized(MOCK_USDC, a, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 normB = TokenPrecision.toNormalized(MOCK_USDC, b, MOCK_WBTC, MOCK_USDC, MOCK_USDT);

        assert(normA <= normB);
    }

    /**
     * @notice Verify fromNormalized is monotonic
     */
    function check_fromNormalized_monotonic(uint128 a, uint128 b) public pure {
        vm.assume(a <= b);

        uint256 denormA = TokenPrecision.fromNormalized(MOCK_WBTC, a, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 denormB = TokenPrecision.fromNormalized(MOCK_WBTC, b, MOCK_WBTC, MOCK_USDC, MOCK_USDT);

        assert(denormA <= denormB);
    }

    // ============ Scale Factor Consistency ============

    /**
     * @notice Verify WBTC toNormalized uses correct scale factor
     */
    function check_wbtc_scale_factor(uint64 amount) public pure {
        uint256 normalized = TokenPrecision.toNormalized(MOCK_WBTC, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 expected = uint256(amount) * Constants.SCALE_WBTC_TO_NORM;

        assert(normalized == expected);
    }

    /**
     * @notice Verify USDC toNormalized uses correct scale factor
     */
    function check_usdc_scale_factor(uint64 amount) public pure {
        uint256 normalized = TokenPrecision.toNormalized(MOCK_USDC, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 expected = uint256(amount) * Constants.SCALE_USDC_TO_NORM;

        assert(normalized == expected);
    }

    /**
     * @notice Verify USDT toNormalized uses correct scale factor
     */
    function check_usdt_scale_factor(uint64 amount) public pure {
        uint256 normalized = TokenPrecision.toNormalized(MOCK_USDT, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 expected = uint256(amount) * Constants.SCALE_USDT_TO_NORM;

        assert(normalized == expected);
    }

    /**
     * @notice Verify getScaleToNorm returns correct values
     */
    function check_getScaleToNorm_consistency() public pure {
        assert(TokenPrecision.getScaleToNorm(MOCK_WBTC, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == Constants.SCALE_WBTC_TO_NORM);
        assert(TokenPrecision.getScaleToNorm(MOCK_USDC, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == Constants.SCALE_USDC_TO_NORM);
        assert(TokenPrecision.getScaleToNorm(MOCK_USDT, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == Constants.SCALE_USDT_TO_NORM);
        assert(TokenPrecision.getScaleToNorm(MOCK_BTD, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == 1);
    }

    // ============ Zero Preservation ============

    /**
     * @notice Verify toNormalized(0) == 0 for all tokens
     */
    function check_toNormalized_zero() public pure {
        assert(TokenPrecision.toNormalized(MOCK_WBTC, 0, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == 0);
        assert(TokenPrecision.toNormalized(MOCK_USDC, 0, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == 0);
        assert(TokenPrecision.toNormalized(MOCK_USDT, 0, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == 0);
        assert(TokenPrecision.toNormalized(MOCK_BTD, 0, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == 0);
    }

    /**
     * @notice Verify fromNormalized(0) == 0 for all tokens
     */
    function check_fromNormalized_zero() public pure {
        assert(TokenPrecision.fromNormalized(MOCK_WBTC, 0, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == 0);
        assert(TokenPrecision.fromNormalized(MOCK_USDC, 0, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == 0);
        assert(TokenPrecision.fromNormalized(MOCK_USDT, 0, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == 0);
        assert(TokenPrecision.fromNormalized(MOCK_BTD, 0, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == 0);
    }

    // ============ 18-Decimal Pass-Through ============

    /**
     * @notice Verify 18-decimal tokens pass through unchanged in toNormalized
     */
    function check_18decimal_passthrough_toNormalized(uint128 amount) public pure {
        uint256 normalized = TokenPrecision.toNormalized(MOCK_BTD, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        assert(normalized == amount);
    }

    /**
     * @notice Verify 18-decimal tokens pass through unchanged in fromNormalized
     */
    function check_18decimal_passthrough_fromNormalized(uint128 amount) public pure {
        uint256 denormalized = TokenPrecision.fromNormalized(MOCK_BTD, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        assert(denormalized == amount);
    }

    // ============ Simplified Function Equivalence ============

    /**
     * @notice Verify simplified wbtcToNormalized matches generic toNormalized
     */
    function check_wbtc_simplified_equivalence(uint64 amount) public pure {
        uint256 generic = TokenPrecision.toNormalized(MOCK_WBTC, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 simplified = TokenPrecision.wbtcToNormalized(amount);

        assert(generic == simplified);
    }

    /**
     * @notice Verify simplified normalizedToWbtc matches generic fromNormalized
     */
    function check_wbtc_simplified_fromNormalized_equivalence(uint128 normalized) public pure {
        uint256 generic = TokenPrecision.fromNormalized(MOCK_WBTC, normalized, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 simplified = TokenPrecision.normalizedToWbtc(normalized);

        assert(generic == simplified);
    }

    /**
     * @notice Verify simplified USDC functions match generic
     */
    function check_usdc_simplified_equivalence(uint64 amount) public pure {
        uint256 genericTo = TokenPrecision.toNormalized(MOCK_USDC, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 simplifiedTo = TokenPrecision.usdcToNormalized(amount);
        assert(genericTo == simplifiedTo);
    }

    /**
     * @notice Verify simplified USDT functions match generic
     */
    function check_usdt_simplified_equivalence(uint64 amount) public pure {
        uint256 genericTo = TokenPrecision.toNormalized(MOCK_USDT, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 simplifiedTo = TokenPrecision.usdtToNormalized(amount);
        assert(genericTo == simplifiedTo);
    }

    // ============ Decimals Lookup ============

    /**
     * @notice Verify getDecimals returns correct values
     */
    function check_getDecimals_correctness() public pure {
        assert(TokenPrecision.getDecimals(MOCK_WBTC, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == 8);
        assert(TokenPrecision.getDecimals(MOCK_USDC, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == 6);
        assert(TokenPrecision.getDecimals(MOCK_USDT, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == 6);
        assert(TokenPrecision.getDecimals(MOCK_BTD, MOCK_WBTC, MOCK_USDC, MOCK_USDT) == 18);
    }

    // ============ Ordering Preservation ============

    /**
     * @notice Verify strict ordering is preserved
     * @dev a < b implies toNormalized(a) < toNormalized(b) for non-zero scale
     */
    function check_strict_ordering_preserved(uint64 a, uint64 b) public pure {
        vm.assume(a < b);

        uint256 normA = TokenPrecision.wbtcToNormalized(a);
        uint256 normB = TokenPrecision.wbtcToNormalized(b);

        // Since scale factor is positive (1e10), strict ordering is preserved
        assert(normA < normB);
    }

    // ============ No Overflow in Expected Range ============

    /**
     * @notice Verify no overflow for maximum realistic WBTC amount
     * @dev Max WBTC supply is 21 million, so uint64 is more than enough
     */
    function check_wbtc_no_overflow_max_supply() public pure {
        uint256 maxWbtc = 21_000_000e8; // 21 million WBTC in 8 decimals
        uint256 normalized = TokenPrecision.wbtcToNormalized(maxWbtc);

        // Should equal 21 million in 18 decimals
        assert(normalized == 21_000_000e18);

        // Round trip should work
        uint256 recovered = TokenPrecision.normalizedToWbtc(normalized);
        assert(recovered == maxWbtc);
    }

    /**
     * @notice Verify no overflow for maximum realistic USDC amount
     */
    function check_usdc_no_overflow_realistic() public pure {
        uint256 largeUsdc = 1_000_000_000_000e6; // 1 trillion USDC
        uint256 normalized = TokenPrecision.usdcToNormalized(largeUsdc);

        assert(normalized == 1_000_000_000_000e18);

        uint256 recovered = TokenPrecision.normalizedToUsdc(normalized);
        assert(recovered == largeUsdc);
    }
}
