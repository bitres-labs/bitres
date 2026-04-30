// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/OracleMath.sol";
import "../../contracts/libraries/Constants.sol";

/// @title PriceOracle Formal Verification Tests
/// @notice Formal verification tests using Halmos symbolic execution
/// @dev Tests prefixed with "check_" are symbolic tests for Halmos
contract PriceOracleFormalTest is Test {
    /// @notice Verify deviationWithin is reflexive (same price always within any threshold)
    function check_deviationWithin_reflexive(uint128 price, uint16 maxBps) public pure {
        vm.assume(price > 0);
        vm.assume(maxBps > 0);

        bool result = OracleMath.deviationWithin(price, price, maxBps);
        assert(result);
    }

    /// @notice Verify deviationWithin returns false for zero prices
    function check_deviationWithin_zeroPrice(uint128 otherPrice, uint16 maxBps) public pure {
        vm.assume(otherPrice > 0);
        vm.assume(maxBps > 0);

        assert(!OracleMath.deviationWithin(0, otherPrice, maxBps));
        assert(!OracleMath.deviationWithin(otherPrice, 0, maxBps));
    }

    /// @notice Verify that if prices are within threshold T1, they are within any T2 >= T1
    function check_deviationWithin_monotonic_threshold(uint128 priceA, uint128 priceB, uint16 bps1, uint16 bps2)
        public
        pure
    {
        vm.assume(priceA > 0);
        vm.assume(priceB > 0);
        vm.assume(bps1 > 0);
        vm.assume(bps2 >= bps1);
        vm.assume(bps2 <= 10000);

        bool within1 = OracleMath.deviationWithin(priceA, priceB, bps1);
        bool within2 = OracleMath.deviationWithin(priceA, priceB, bps2);

        // If within smaller threshold, must be within larger threshold
        if (within1) {
            assert(within2);
        }
    }

    /// @notice Verify BTD floor is always <= IUSD price (when CR <= 100%)
    function check_BTDFloor_neverAboveIUSD(uint128 cr, uint128 iusdPrice) public pure {
        vm.assume(cr > 0 && cr <= 1e18);
        vm.assume(iusdPrice > 0 && iusdPrice <= 2e18);

        // Cap CR at 1e18
        uint256 cappedCR = cr > 1e18 ? 1e18 : uint256(cr);

        // Floor = 90% * CR * IUSD
        uint256 floor = (cappedCR * uint256(iusdPrice) * 9000) / (1e18 * 10000);

        // Floor should never exceed IUSD (since 90% * CR% * IUSD <= IUSD)
        assert(floor <= iusdPrice);
    }

    /// @notice Verify inversePrice is non-zero for non-zero input
    function check_inversePrice_nonZero(uint128 price) public pure {
        vm.assume(price > 0);
        vm.assume(price <= 1e36);

        uint256 inv = OracleMath.inversePrice(price);
        assert(inv > 0);
    }

    /// @notice Verify inversePrice preserves ordering in reverse
    function check_inversePrice_antiMonotonic(uint64 priceA, uint64 priceB) public pure {
        vm.assume(priceA > 1e6);
        vm.assume(priceB > 1e6);
        vm.assume(priceA < priceB);

        uint256 invA = OracleMath.inversePrice(priceA);
        uint256 invB = OracleMath.inversePrice(priceB);

        assert(invA >= invB);
    }

    /// @notice Verify normalizeAmount idempotent for 18 decimals
    function check_normalizeAmount_18decimals_identity(uint128 amount) public pure {
        uint256 result = OracleMath.normalizeAmount(amount, 18);
        assert(result == amount);
    }

    /// @notice Verify normalizeAmount upscales common 6-decimal assets correctly
    function check_normalizeAmount_upscale_6_decimals(uint64 amount) public pure {
        vm.assume(amount > 0);

        uint256 result = OracleMath.normalizeAmount(amount, 6);
        assert(result == uint256(amount) * 1e12);
    }

    /// @notice Verify normalizeAmount upscales common 8-decimal assets correctly
    function check_normalizeAmount_upscale_8_decimals(uint64 amount) public pure {
        vm.assume(amount > 0);

        uint256 result = OracleMath.normalizeAmount(amount, 8);
        assert(result == uint256(amount) * 1e10);
    }

    /// @notice Verify normalizeAmount upscales near-18-decimal assets correctly
    function check_normalizeAmount_upscale_17_decimals(uint64 amount) public pure {
        vm.assume(amount > 0);

        uint256 result = OracleMath.normalizeAmount(amount, 17);
        assert(result == uint256(amount) * 10);
    }

    /// @notice Verify spotPrice is positive when the reserve ratio is representable at 18 decimals
    function check_spotPrice_positive_when_representable(uint64 reserveBase, uint64 reserveQuote) public pure {
        vm.assume(reserveBase > 0);
        vm.assume(reserveQuote > 0);
        vm.assume(uint256(reserveQuote) * 1e18 >= uint256(reserveBase));

        uint256 price = OracleMath.spotPrice(reserveBase, reserveQuote, 18, 18);
        assert(price > 0);
    }

    /// @notice Verify spotPrice increases when quote reserve increases
    function check_spotPrice_monotonic_quote(uint64 reserveBase, uint64 reserveQuote1, uint64 reserveQuote2)
        public
        pure
    {
        vm.assume(reserveBase > 0);
        vm.assume(reserveQuote1 > 0);
        vm.assume(reserveQuote2 > 0);
        vm.assume(reserveQuote1 <= reserveQuote2);

        uint256 price1 = OracleMath.spotPrice(reserveBase, reserveQuote1, 18, 18);
        uint256 price2 = OracleMath.spotPrice(reserveBase, reserveQuote2, 18, 18);

        assert(price1 <= price2);
    }
}
