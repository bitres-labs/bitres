// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

/// @notice Foundry Fuzz Testing Complete Demonstration
/// @dev Demonstrates all core features of Foundry fuzz testing
contract FuzzBasicTest is Test {
    // ==================== Basic Fuzz Tests ====================

    /// @notice Fuzz test 1: Addition commutativity
    /// @dev Foundry defaults to running 256 random tests
    function testFuzz_AdditionCommutative(uint128 a, uint128 b) public pure {
        // Prevent overflow: convert to uint256
        uint256 sum1 = uint256(a) + uint256(b);
        uint256 sum2 = uint256(b) + uint256(a);

        // Verify: a + b == b + a
        assertEq(sum1, sum2);
    }

    /// @notice Fuzz test 2: Multiplication associativity
    function testFuzz_MultiplicationAssociative(uint64 a, uint64 b, uint64 c) public pure {
        // Prevent overflow: convert to uint256
        uint256 result1 = (uint256(a) * uint256(b)) * uint256(c);
        uint256 result2 = uint256(a) * (uint256(b) * uint256(c));

        // Verify: (a * b) * c == a * (b * c)
        assertEq(result1, result2);
    }

    /// @notice Fuzz test 3: Subtraction property
    function testFuzz_Subtraction(uint256 a, uint256 b) public pure {
        // Assumption: a >= b
        vm.assume(a >= b);

        uint256 result = a - b;

        // Verify: result + b == a
        assertEq(result + b, a);
    }

    // ==================== Using vm.assume to Constrain Input ====================

    /// @notice Fuzz test 4: Using bound to constrain input (preferred over assume for ranges)
    function testFuzz_WithBound(uint256 x) public pure {
        // Use bound instead of assume for range constraints (more efficient)
        x = bound(x, 100, 1000);

        // Verify x is indeed in range
        assertGe(x, 100);
        assertLe(x, 1000);
    }

    /// @notice Fuzz test 5: Division safety
    function testFuzz_SafeDivision(uint256 numerator, uint256 denominator) public pure {
        // Key: use assume to avoid division by zero
        vm.assume(denominator > 0);
        vm.assume(denominator <= type(uint128).max);
        vm.assume(numerator <= type(uint128).max);

        uint256 result = numerator / denominator;

        // Verify basic property
        assertLe(result, numerator);
    }

    // ==================== Percentage and Ratio Tests ====================

    /// @notice Fuzz test 6: Percentage calculation
    function testFuzz_Percentage(uint128 amount, uint16 bps) public pure {
        // bps = basis points (1 bps = 0.01%)
        vm.assume(bps <= 10000); // Max 100%

        uint256 result = (uint256(amount) * bps) / 10000;

        // Verify: Result doesn't exceed original amount
        assertLe(result, amount);

        // Verify: 0% returns 0
        if (bps == 0) {
            assertEq(result, 0);
        }

        // Verify: 100% returns original amount
        if (bps == 10000) {
            assertEq(result, amount);
        }
    }

    /// @notice Fuzz test 7: Ratio preservation
    function testFuzz_RatioPreservation(uint128 a, uint128 b, uint128 multiplier) public pure {
        vm.assume(b > 0);
        vm.assume(multiplier > 0 && multiplier < 1000);

        uint256 ratio1 = (uint256(a) * 1e18) / b;
        uint256 ratio2 = (uint256(a) * multiplier * 1e18) / (uint256(b) * multiplier);

        // Verify: Ratio should remain unchanged
        assertEq(ratio1, ratio2);
    }

    // ==================== Overflow and Boundary Tests ====================

    /// @notice Fuzz test 8: Test addition doesn't overflow
    function testFuzz_AdditionNoOverflow(uint128 a, uint128 b) public pure {
        // uint128 + uint128 in uint256 will never overflow
        uint256 sum = uint256(a) + uint256(b);

        // Verify basic properties
        assertGe(sum, a);
        assertGe(sum, b);
    }

    /// @notice Fuzz test 9: Boundary value tests
    function testFuzz_BoundaryValues(uint8 value) public pure {
        // Test all possible uint8 values (0-255)

        if (value == 0) {
            assertEq(value, 0);
        } else if (value == type(uint8).max) {
            assertEq(value, 255);
        } else {
            assertGt(value, 0);
            assertLt(value, 255);
        }
    }

    // ==================== Array and String Tests ====================

    /// @notice Fuzz test 10: Dynamic array length
    function testFuzz_ArrayLength(uint8 length) public pure {
        vm.assume(length > 0 && length <= 50);

        uint256[] memory arr = new uint256[](length);
        assertEq(arr.length, length);
    }

    /// @notice Fuzz test 11: Array element access safety
    function testFuzz_ArrayAccess(uint8 length, uint8 index) public pure {
        vm.assume(length > 0 && length <= 100);
        vm.assume(index < length);

        uint256[] memory arr = new uint256[](length);
        arr[index] = 42;

        assertEq(arr[index], 42);
    }

    // ==================== Bitwise Operation Tests ====================

    /// @notice Fuzz test 12: Bitwise AND operation
    function testFuzz_BitwiseAND(uint256 a, uint256 b) public pure {
        uint256 result = a & b;

        // Verify: Result is not greater than either input
        assertLe(result, a);
        assertLe(result, b);

        // Verify: a & a == a
        assertEq(a & a, a);
    }

    /// @notice Fuzz test 13: Bitwise OR operation
    function testFuzz_BitwiseOR(uint256 a, uint256 b) public pure {
        uint256 result = a | b;

        // Verify: Result is not less than either input
        assertGe(result, a);
        assertGe(result, b);

        // Verify: a | a == a
        assertEq(a | a, a);
    }

    /// @notice Fuzz test 14: Left shift
    function testFuzz_LeftShift(uint128 value, uint8 shift) public pure {
        vm.assume(shift < 128); // Avoid shifting out of range

        uint256 result = uint256(value) << shift;

        // Verify: Left shift equals multiply by 2^shift
        assertEq(result, uint256(value) * (2 ** shift));
    }

    // ==================== Complex Logic Tests ====================

    /// @notice Fuzz test 15: Triangle inequality
    function testFuzz_TriangleInequality(uint64 a, uint64 b) public pure {
        // |a - b| <= a + b
        uint256 diff = a > b ? a - b : b - a;
        uint256 sum = uint256(a) + uint256(b);

        assertLe(diff, sum);
    }

    /// @notice Fuzz test 16: Average value property
    function testFuzz_Average(uint128 a, uint128 b) public pure {
        uint256 avg = (uint256(a) + uint256(b)) / 2;

        // Average should be between the two numbers (or equal)
        if (a <= b) {
            assertGe(avg, a);
            assertLe(avg, b);
        } else {
            assertGe(avg, b);
            assertLe(avg, a);
        }
    }

    /// @notice Fuzz test 17: Maximum function
    function testFuzz_Max(uint256 a, uint256 b) public pure {
        uint256 max = a > b ? a : b;

        assertGe(max, a);
        assertGe(max, b);

        // max must equal a or b
        assertTrue(max == a || max == b);
    }

    /// @notice Fuzz test 18: Minimum function
    function testFuzz_Min(uint256 a, uint256 b) public pure {
        uint256 min = a < b ? a : b;

        assertLe(min, a);
        assertLe(min, b);

        // min must equal a or b
        assertTrue(min == a || min == b);
    }

    // ==================== Modulo Operation Tests ====================

    /// @notice Fuzz test 19: Modulo operation property
    function testFuzz_Modulo(uint256 a, uint256 m) public pure {
        vm.assume(m > 0);

        uint256 result = a % m;

        // Verify: Result is always less than modulus
        assertLt(result, m);
    }

    /// @notice Fuzz test 20: Modulo operation periodicity
    function testFuzz_ModuloPeriodicity(uint128 a, uint16 m) public pure {
        vm.assume(m > 0);

        uint256 result1 = a % m;
        uint256 result2 = (uint256(a) + m) % m;

        // Verify: a % m == (a + m) % m
        assertEq(result1, result2);
    }
}
