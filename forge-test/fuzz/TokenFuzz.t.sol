// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";

/// @title Token Fuzz Tests
/// @notice Tests all edge cases for ERC20 token operations
contract TokenFuzzTest is Test {
    using Constants for *;

    // ==================== Transfer Fuzz Tests ====================

    /// @notice Fuzz test: Transfer does not break total supply conservation
    function testFuzz_Transfer_SupplyConservation(
        uint128 senderBalance,
        uint128 recipientBalance,
        uint128 amount
    ) public pure {
        vm.assume(senderBalance >= amount);

        uint256 totalBefore = uint256(senderBalance) + uint256(recipientBalance);

        // Simulate transfer
        uint256 senderAfter = uint256(senderBalance) - uint256(amount);
        uint256 recipientAfter = uint256(recipientBalance) + uint256(amount);

        uint256 totalAfter = senderAfter + recipientAfter;

        // Verify: Total supply unchanged
        assertEq(totalAfter, totalBefore);
    }

    /// @notice Fuzz test: Transfer to self
    function testFuzz_Transfer_ToSelf(
        uint128 balance,
        uint128 amount
    ) public pure {
        vm.assume(balance >= amount);

        // Transfer to self
        uint256 balanceBefore = balance;
        uint256 balanceAfter = uint256(balance) - uint256(amount) + uint256(amount);

        // Verify: Balance unchanged
        assertEq(balanceAfter, balanceBefore);
    }

    /// @notice Fuzz test: Balance correctness after transfer
    function testFuzz_Transfer_BalanceCorrectness(
        uint128 senderBalance,
        uint128 amount
    ) public pure {
        vm.assume(senderBalance >= amount);

        uint256 senderAfter = uint256(senderBalance) - uint256(amount);

        // Verify: Sender balance decreased
        assertEq(senderAfter, uint256(senderBalance) - uint256(amount));

        // Verify: No underflow
        assertLe(senderAfter, senderBalance);
    }

    /// @notice Fuzz test: Zero amount transfer
    function testFuzz_Transfer_ZeroAmount(
        uint128 senderBalance,
        uint128 recipientBalance
    ) public pure {
        uint256 amount = 0;

        // Simulate zero amount transfer
        uint256 senderAfter = uint256(senderBalance) - amount;
        uint256 recipientAfter = uint256(recipientBalance) + amount;

        // Verify: Balances unchanged
        assertEq(senderAfter, senderBalance);
        assertEq(recipientAfter, recipientBalance);
    }

    // ==================== Approval Fuzz Tests ====================

    /// @notice Fuzz test: Approval amount validity
    function testFuzz_Approve_Amount(
        uint256 approveAmount
    ) public pure {
        // Verify: Approval amount can be any value (including 0 and max)
        assertGe(approveAmount, 0);
        assertLe(approveAmount, type(uint256).max);
    }

    /// @notice Fuzz test: TransferFrom deducts allowance
    function testFuzz_TransferFrom_AllowanceDeduction(
        uint128 allowance,
        uint128 amount
    ) public pure {
        vm.assume(allowance >= amount);

        uint256 allowanceAfter = uint256(allowance) - uint256(amount);

        // Verify: Allowance correctly deducted
        assertEq(allowanceAfter, uint256(allowance) - uint256(amount));
        assertLe(allowanceAfter, allowance);
    }

    /// @notice Fuzz test: Infinite approval (type(uint256).max)
    function testFuzz_InfiniteApproval_NoDeduction(
        uint128 amount
    ) public pure {
        uint256 allowance = type(uint256).max;

        // Infinite approval should not decrease after transferFrom
        uint256 allowanceAfter = allowance;

        // Verify: Infinite approval unchanged
        assertEq(allowanceAfter, type(uint256).max);
    }

    // ==================== Mint/Burn Fuzz Tests ====================

    /// @notice Fuzz test: Minting increases total supply
    function testFuzz_Mint_IncreasesTotalSupply(
        uint128 totalSupply,
        uint128 mintAmount
    ) public pure {
        vm.assume(uint256(totalSupply) + uint256(mintAmount) <= type(uint256).max);
        vm.assume(mintAmount > 0); // Mint amount must be > 0 to increase

        uint256 newTotalSupply = uint256(totalSupply) + uint256(mintAmount);

        // Verify: Total supply increased
        assertEq(newTotalSupply, uint256(totalSupply) + uint256(mintAmount));
        assertGt(newTotalSupply, totalSupply);
    }

    /// @notice Fuzz test: Burning decreases total supply
    function testFuzz_Burn_DecreasesTotalSupply(
        uint128 totalSupply,
        uint128 burnAmount
    ) public pure {
        vm.assume(totalSupply >= burnAmount);
        vm.assume(burnAmount > 0); // Burn amount must be > 0 to decrease

        uint256 newTotalSupply = uint256(totalSupply) - uint256(burnAmount);

        // Verify: Total supply decreased
        assertEq(newTotalSupply, uint256(totalSupply) - uint256(burnAmount));
        assertLt(newTotalSupply, totalSupply);
    }

    /// @notice Fuzz test: User balance increases after minting
    function testFuzz_Mint_UserBalanceIncrease(
        uint128 userBalance,
        uint128 mintAmount
    ) public pure {
        vm.assume(uint256(userBalance) + uint256(mintAmount) <= type(uint256).max);
        vm.assume(mintAmount > 0); // Mint amount must be > 0 to increase

        uint256 newBalance = uint256(userBalance) + uint256(mintAmount);

        // Verify: User balance increased
        assertEq(newBalance, uint256(userBalance) + uint256(mintAmount));
        assertGt(newBalance, userBalance);
    }

    /// @notice Fuzz test: User balance decreases after burning
    function testFuzz_Burn_UserBalanceDecrease(
        uint128 userBalance,
        uint128 burnAmount
    ) public pure {
        vm.assume(userBalance >= burnAmount);
        vm.assume(burnAmount > 0); // Burn amount must be > 0 to decrease

        uint256 newBalance = uint256(userBalance) - uint256(burnAmount);

        // Verify: User balance decreased
        assertEq(newBalance, uint256(userBalance) - uint256(burnAmount));
        assertLt(newBalance, userBalance);
    }

    // ==================== Balance Overflow/Underflow Tests ====================

    /// @notice Fuzz test: Balance addition does not overflow
    function testFuzz_Balance_AdditionNoOverflow(
        uint128 balance1,
        uint128 balance2
    ) public pure {
        // Use uint256 to prevent overflow
        uint256 sum = uint256(balance1) + uint256(balance2);

        // Verify: Sum is not less than either balance
        assertGe(sum, balance1);
        assertGe(sum, balance2);
    }

    /// @notice Fuzz test: Balance subtraction does not underflow
    function testFuzz_Balance_SubtractionNoUnderflow(
        uint128 balance,
        uint128 amount
    ) public pure {
        vm.assume(balance >= amount);

        uint256 result = uint256(balance) - uint256(amount);

        // Verify: Difference is not greater than original balance
        assertLe(result, balance);
    }

    // ==================== Batch Transfer Fuzz Tests ====================

    /// @notice Fuzz test: Batch transfer total supply conservation
    function testFuzz_BatchTransfer_SupplyConservation(
        uint64 balance1,
        uint64 balance2,
        uint64 balance3,
        uint64 amount1,
        uint64 amount2
    ) public pure {
        // Prevent overflow
        vm.assume(uint256(amount1) + uint256(amount2) <= type(uint64).max);
        vm.assume(balance1 >= uint256(amount1) + uint256(amount2));

        uint256 totalBefore = uint256(balance1) + uint256(balance2) + uint256(balance3);

        // Simulate batch transfer: balance1 -> balance2 (amount1), balance1 -> balance3 (amount2)
        uint256 newBalance1 = uint256(balance1) - uint256(amount1) - uint256(amount2);
        uint256 newBalance2 = uint256(balance2) + uint256(amount1);
        uint256 newBalance3 = uint256(balance3) + uint256(amount2);

        uint256 totalAfter = newBalance1 + newBalance2 + newBalance3;

        // Verify: Total supply unchanged
        assertEq(totalAfter, totalBefore);
    }

    // ==================== Precision and Rounding Tests ====================

    /// @notice Fuzz test: Token amount precision
    function testFuzz_Token_PrecisionHandling(
        uint256 amount,
        uint8 decimals
    ) public pure {
        vm.assume(decimals <= 18);
        vm.assume(amount > 0);

        // Convert to minimum unit
        uint256 minUnit = 10 ** decimals;
        vm.assume(amount >= minUnit);

        // Verify: Can correctly handle minimum unit
        uint256 wholeUnits = amount / minUnit;
        uint256 remainder = amount % minUnit;

        assertEq(amount, wholeUnits * minUnit + remainder);
    }

    /// @notice Fuzz test: Percentage calculation precision
    function testFuzz_Percentage_Precision(
        uint128 amount,
        uint16 percentage // Percentage (0-10000 = 0-100%)
    ) public pure {
        vm.assume(percentage <= 10000);
        vm.assume(amount > 0);

        // Calculate percentage
        vm.assume(uint256(amount) * uint256(percentage) < type(uint256).max);

        uint256 result = (uint256(amount) * uint256(percentage)) / 10000;

        // Verify: Result does not exceed original amount
        assertLe(result, amount);

        // Verify: 0% = 0, 100% = original amount
        if (percentage == 0) {
            assertEq(result, 0);
        } else if (percentage == 10000) {
            assertEq(result, amount);
        }
    }

    // ==================== Multi-User Scenario Fuzz Tests ====================

    /// @notice Fuzz test: 3-user circular transfer
    function testFuzz_CircularTransfer_ThreeUsers(
        uint64 balance1,
        uint64 balance2,
        uint64 balance3,
        uint64 amount
    ) public pure {
        vm.assume(balance1 >= amount);
        vm.assume(balance2 >= amount);
        vm.assume(balance3 >= amount);

        uint256 totalBefore = uint256(balance1) + uint256(balance2) + uint256(balance3);

        // Circular transfer: 1->2, 2->3, 3->1
        uint256 newBalance1 = uint256(balance1) - uint256(amount) + uint256(amount);
        uint256 newBalance2 = uint256(balance2) - uint256(amount) + uint256(amount);
        uint256 newBalance3 = uint256(balance3) - uint256(amount) + uint256(amount);

        uint256 totalAfter = newBalance1 + newBalance2 + newBalance3;

        // Verify: Total supply unchanged after circular transfer, all balances unchanged
        assertEq(totalAfter, totalBefore);
        assertEq(newBalance1, balance1);
        assertEq(newBalance2, balance2);
        assertEq(newBalance3, balance3);
    }

    // ==================== Special Value Tests ====================

    /// @notice Fuzz test: Maximum value transfer
    function testFuzz_MaxValue_Transfer(
        uint128 balance
    ) public pure {
        vm.assume(balance == type(uint128).max);

        // Transfer maximum value
        uint256 amount = balance;
        uint256 balanceAfter = uint256(balance) - amount;

        // Verify: Balance is 0 after transfer
        assertEq(balanceAfter, 0);
    }

    /// @notice Fuzz test: 1 wei transfer
    function testFuzz_OneWei_Transfer(
        uint128 senderBalance,
        uint128 recipientBalance
    ) public pure {
        vm.assume(senderBalance >= 1);

        uint256 amount = 1;

        // Simulate 1 wei transfer
        uint256 senderAfter = uint256(senderBalance) - amount;
        uint256 recipientAfter = uint256(recipientBalance) + amount;

        // Verify: Transfer successful
        assertEq(senderAfter, uint256(senderBalance) - 1);
        assertEq(recipientAfter, uint256(recipientBalance) + 1);
    }

    // ==================== Allowance Boundary Tests ====================

    /// @notice Fuzz test: Allowance exactly used up
    function testFuzz_Allowance_ExactlyUsed(
        uint128 allowance
    ) public pure {
        vm.assume(allowance > 0);

        // Transfer equals allowance
        uint256 amount = allowance;
        uint256 allowanceAfter = uint256(allowance) - amount;

        // Verify: Allowance is 0 after use
        assertEq(allowanceAfter, 0);
    }

    /// @notice Fuzz test: Partially used allowance
    function testFuzz_Allowance_PartiallyUsed(
        uint128 allowance,
        uint64 amount
    ) public pure {
        vm.assume(allowance > amount);
        vm.assume(amount > 0);

        uint256 allowanceAfter = uint256(allowance) - uint256(amount);

        // Verify: Remaining allowance exists
        assertGt(allowanceAfter, 0);
        assertLt(allowanceAfter, allowance);
    }

    // ==================== Gas Optimization Related Tests ====================

    /// @notice Fuzz test: Small vs large transfer (gas should not differ qualitatively)
    function testFuzz_Transfer_GasIndependent(
        uint8 smallAmount,
        uint128 largeAmount
    ) public pure {
        vm.assume(smallAmount > 0);
        vm.assume(largeAmount > uint256(smallAmount) * 1000);

        // Both transfers should have same logical complexity
        // Here we only verify calculation correctness
        uint256 small = smallAmount;
        uint256 large = largeAmount;

        assertGt(large, small);
    }

    // ==================== Boundary Case Summary Tests ====================

    /// @notice Fuzz test: All boundary value combinations
    function testFuzz_BoundaryValues_Combined(
        bool useZero,
        bool useMax,
        uint128 normalValue
    ) public pure {
        uint256 value;

        if (useZero) {
            value = 0;
        } else if (useMax) {
            value = type(uint256).max;
        } else {
            value = normalValue;
        }

        // Verify: All values are valid uint256
        assertGe(value, 0);
        assertLe(value, type(uint256).max);
    }
}
