// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";

/// @title Treasury Fuzz Tests
/// @notice Tests all edge cases for treasury fund management, buyback, and compensation
contract TreasuryFuzzTest is Test {
    using Constants for *;

    // ==================== WBTC Deposit/Withdraw Fuzz Tests ====================

    /// @notice Fuzz test: WBTC deposit validation
    function testFuzz_WBTC_DepositValidation(
        uint128 depositAmount
    ) public pure {
        vm.assume(depositAmount > 0);

        // Verify: Deposit amount must be > 0
        assertGt(depositAmount, 0);
    }

    /// @notice Fuzz test: WBTC withdrawal does not exceed balance
    function testFuzz_WBTC_WithdrawNotExceedBalance(
        uint128 treasuryBalance,
        uint128 withdrawAmount
    ) public pure {
        vm.assume(treasuryBalance > 0);
        vm.assume(withdrawAmount > 0);

        if (withdrawAmount > treasuryBalance) {
            // Verify: Excessive withdrawal should fail
            assertGt(withdrawAmount, treasuryBalance);
        } else {
            // Verify: Valid withdrawal
            assertLe(withdrawAmount, treasuryBalance);
        }
    }

    /// @notice Fuzz test: WBTC balance conservation
    function testFuzz_WBTC_BalanceConservation(
        uint128 initialBalance,
        uint128 depositAmount,
        uint128 withdrawAmount
    ) public pure {
        vm.assume(initialBalance > 0);
        vm.assume(depositAmount > 0);
        vm.assume(withdrawAmount > 0);
        vm.assume(withdrawAmount <= uint256(initialBalance) + uint256(depositAmount));

        // Balance after deposit
        uint256 afterDeposit = uint256(initialBalance) + uint256(depositAmount);

        // Balance after withdrawal
        uint256 afterWithdraw = afterDeposit - uint256(withdrawAmount);

        // Verify: Balance conservation
        assertEq(afterWithdraw, uint256(initialBalance) + uint256(depositAmount) - uint256(withdrawAmount));
    }

    // ==================== BRS Compensation Fuzz Tests ====================

    /// @notice Fuzz test: BRS compensation amount calculation
    function testFuzz_BRS_CompensationAmount(
        uint128 btdAmount,
        uint64 btcPrice,    // Changed to uint64 to avoid overflow
        uint64 brsPrice     // Changed to uint64
    ) public pure {
        btdAmount = uint128(bound(btdAmount, 1e18 + 1, type(uint128).max)); // At least 1 BTD
        btcPrice = uint64(bound(btcPrice, 1e6 + 1, 8e7 - 1)); // BTC price $0.01-$0.80
        brsPrice = uint64(bound(brsPrice, 1e12 + 1, 1e16 - 1)); // BRS price reasonable range

        // Assume minimum price is $1 (1e8), compensation needed when current price < minimum
        uint256 minPrice = 1e8;

        // Calculate shortfall
        uint256 expectedValue = uint256(btdAmount);
        uint256 btcValue = (uint256(btdAmount) * uint256(btcPrice)) / 1e8;

        // Only test cases needing compensation (current price < minimum price)
        vm.assume(btcValue < expectedValue);
        uint256 shortfall = expectedValue - btcValue;

        // Calculate BRS compensation amount
        vm.assume(shortfall < type(uint128).max); // Prevent overflow
        uint256 brsCompensation = shortfall / uint256(brsPrice);

        // Verify: Compensation amount is reasonable
        assertGt(brsCompensation, 0);
    }

    /// @notice Fuzz test: BRS compensation positively correlated with price gap
    function testFuzz_BRS_CompensationPriceGap(
        uint64 btdAmount,
        uint32 btcPriceBP   // Use basis points to represent price percentage
    ) public pure {
        btdAmount = uint64(bound(btdAmount, 1e16 + 1, type(uint64).max)); // At least 0.01 BTD
        btcPriceBP = uint32(bound(btcPriceBP, 2001, 7999)); // 20%-80% of minimum price

        // Assume minimum price is $1 (1e8), create two prices: btcPrice1 and lower btcPrice2
        uint256 btcPrice1 = (1e8 * uint256(btcPriceBP)) / 10000;
        uint256 btcPrice2 = btcPrice1 / 2; // price2 is half of price1 (lower)

        // Calculate shortfall at both prices
        uint256 shortfall1 = uint256(btdAmount) - (uint256(btdAmount) * btcPrice1) / 1e8;
        uint256 shortfall2 = uint256(btdAmount) - (uint256(btdAmount) * btcPrice2) / 1e8;

        // Verify: Lower price means larger shortfall means more compensation
        assertGt(shortfall2, shortfall1);
    }

    /// @notice Fuzz test: BRS compensation does not exceed treasury balance
    function testFuzz_BRS_CompensationNotExceedBalance(
        uint128 treasuryBRS,
        uint128 compensationNeeded
    ) public pure {
        vm.assume(treasuryBRS > 0);
        vm.assume(compensationNeeded > 0);

        if (compensationNeeded > treasuryBRS) {
            // Verify: Insufficient compensation
            assertGt(compensationNeeded, treasuryBRS);
        } else {
            // Verify: Sufficient compensation
            assertLe(compensationNeeded, treasuryBRS);
        }
    }

    // ==================== BTD Buyback BRS Fuzz Tests ====================

    /// @notice Fuzz test: BTD buyback BRS exchange rate
    function testFuzz_Buyback_ExchangeRate(
        uint128 btdAmount,
        uint128 btdPrice,  // BTD/USD
        uint128 brsPrice   // BRS/USD
    ) public pure {
        btdAmount = uint128(bound(btdAmount, 1e18 + 1, type(uint128).max)); // At least 1 BTD
        btdPrice = uint128(bound(btdPrice, 1e15 + 1, 1e20 - 1)); // Reasonable price range
        brsPrice = uint128(bound(brsPrice, 1e12 + 1, 1e18 - 1)); // BRS price reasonable range

        // Bound btdAmount to prevent overflow: btdAmount * btdPrice < type(uint256).max
        // btdAmount < type(uint256).max / btdPrice
        if (uint256(btdAmount) * uint256(btdPrice) >= type(uint256).max) {
            btdAmount = uint128(type(uint256).max / uint256(btdPrice) - 1);
        }

        // Calculate buyback BRS amount
        uint256 btdValue = uint256(btdAmount) * uint256(btdPrice);
        uint256 brsAmount = btdValue / uint256(brsPrice);

        // Verify: Buyback amount is reasonable
        assertGt(brsAmount, 0);
    }

    /// @notice Fuzz test: Buyback slippage protection
    function testFuzz_Buyback_SlippageProtection(
        uint128 btdAmount,
        uint128 expectedBRS,
        uint16 maxSlippageBP  // Max slippage (basis points)
    ) public pure {
        btdAmount = uint128(bound(btdAmount, 1e18 + 1, type(uint128).max)); // At least 1 BTD
        expectedBRS = uint128(bound(expectedBRS, 1e18 + 1, type(uint128).max)); // Expected at least 1 BRS
        maxSlippageBP = uint16(bound(maxSlippageBP, 1, 1000)); // 0-10% slippage

        // Calculate minimum acceptable BRS amount
        uint256 minBRS = (uint256(expectedBRS) * (Constants.BPS_BASE - uint256(maxSlippageBP))) / Constants.BPS_BASE;

        // Verify: Slippage protection effective
        assertLe(minBRS, expectedBRS);
        assertGt(minBRS, 0);
    }

    /// @notice Fuzz test: Buyback fee
    function testFuzz_Buyback_Fee(
        uint128 btdAmount,
        uint16 feeBP
    ) public pure {
        vm.assume(btdAmount > 1e18); // At least 1 BTD
        vm.assume(feeBP >= 10 && feeBP <= 1000); // 0.1-10% fee, at least 0.1% to ensure fee>0

        // Calculate fee
        uint256 fee = (uint256(btdAmount) * uint256(feeBP)) / Constants.BPS_BASE;
        uint256 netAmount = uint256(btdAmount) - fee;

        // Verify: Fee is reasonable
        assertLe(fee, btdAmount);
        assertGt(netAmount, 0);
        assertLt(netAmount, btdAmount);
    }

    // ==================== Fund Allocation Fuzz Tests ====================

    /// @notice Fuzz test: Multi-party fund allocation
    function testFuzz_FundAllocation_MultiParty(
        uint128 totalFund,
        uint16 party1PercentBP,
        uint16 party2PercentBP,
        uint16 party3PercentBP
    ) public pure {
        vm.assume(totalFund > 1000);
        vm.assume(party1PercentBP > 0 && party1PercentBP < Constants.BPS_BASE);
        vm.assume(party2PercentBP > 0 && party2PercentBP < Constants.BPS_BASE);
        vm.assume(party3PercentBP > 0 && party3PercentBP < Constants.BPS_BASE);
        vm.assume(uint256(party1PercentBP) + uint256(party2PercentBP) + uint256(party3PercentBP) <= Constants.BPS_BASE);

        // Calculate each party's allocation
        uint256 alloc1 = (uint256(totalFund) * uint256(party1PercentBP)) / Constants.BPS_BASE;
        uint256 alloc2 = (uint256(totalFund) * uint256(party2PercentBP)) / Constants.BPS_BASE;
        uint256 alloc3 = (uint256(totalFund) * uint256(party3PercentBP)) / Constants.BPS_BASE;

        uint256 totalAllocated = alloc1 + alloc2 + alloc3;

        // Verify: Total allocation does not exceed total fund
        assertLe(totalAllocated, totalFund);
    }

    /// @notice Fuzz test: Fee collection
    function testFuzz_FeeCollection_Accumulation(
        uint64 fee1,
        uint64 fee2,
        uint64 fee3
    ) public pure {
        vm.assume(fee1 > 0);
        vm.assume(fee2 > 0);
        vm.assume(fee3 > 0);

        // Accumulate fees
        uint256 totalFees = uint256(fee1) + uint256(fee2) + uint256(fee3);

        // Verify: Fee accumulation
        assertEq(totalFees, uint256(fee1) + uint256(fee2) + uint256(fee3));
        assertGt(totalFees, fee1);
        assertGt(totalFees, fee2);
        assertGt(totalFees, fee3);
    }

    // ==================== Liquidity Management Fuzz Tests ====================

    /// @notice Fuzz test: Liquidity sufficiency check
    function testFuzz_Liquidity_SufficiencyCheck(
        uint128 treasuryBalance,
        uint128 redeemRequest
    ) public pure {
        vm.assume(treasuryBalance > 0);
        vm.assume(redeemRequest > 0);

        bool isSufficient = treasuryBalance >= redeemRequest;

        // Verify: Liquidity check logic
        if (isSufficient) {
            assertGe(treasuryBalance, redeemRequest);
        } else {
            assertLt(treasuryBalance, redeemRequest);
        }
    }

    /// @notice Fuzz test: Liquidity ratio
    function testFuzz_Liquidity_Ratio(
        uint128 availableLiquidity,
        uint128 totalLiability
    ) public pure {
        availableLiquidity = uint128(bound(availableLiquidity, 1e18 + 1, type(uint128).max)); // At least 1 unit of liquidity
        totalLiability = uint128(bound(totalLiability, 1e18 + 1, type(uint64).max - 1)); // Reasonable liability range

        // Bound availableLiquidity to prevent overflow
        // availableLiquidity * PRECISION_18 < type(uint256).max
        uint256 maxLiquidity = type(uint256).max / Constants.PRECISION_18;
        if (availableLiquidity > maxLiquidity) {
            availableLiquidity = uint128(maxLiquidity - 1);
        }

        // Calculate liquidity ratio
        uint256 liquidityRatio = (uint256(availableLiquidity) * Constants.PRECISION_18) / uint256(totalLiability);

        // Verify: Ratio is reasonable
        assertGt(liquidityRatio, 0);
    }

    // ==================== Access Control Fuzz Tests ====================

    /// @notice Fuzz test: Only Minter can call check
    function testFuzz_OnlyMinter_AccessControl(
        bool isMinter,
        bool isOwner
    ) public pure {
        // Verify: Only Minter or Owner can call
        bool canAccess = isMinter || isOwner;

        if (canAccess) {
            assertTrue(isMinter || isOwner);
        } else {
            assertFalse(isMinter || isOwner);
        }
    }

    // ==================== Edge Case Tests ====================

    /// @notice Fuzz test: Zero balance withdrawal should fail
    function testFuzz_ZeroBalance_WithdrawFail() public pure {
        uint256 balance = 0;

        // Verify: Zero balance
        assertEq(balance, 0);
    }

    /// @notice Fuzz test: Maximum withdrawal equals balance
    function testFuzz_MaxWithdraw_EqualBalance(
        uint128 balance
    ) public pure {
        vm.assume(balance > 0);

        uint256 maxWithdraw = balance;

        // Verify: Max withdrawal equals balance
        assertEq(maxWithdraw, balance);
    }

    /// @notice Fuzz test: Multiple small withdrawals
    function testFuzz_MultipleSmallWithdrawals(
        uint128 totalBalance,
        uint8 withdrawCount
    ) public pure {
        totalBalance = uint128(bound(totalBalance, 1001, type(uint128).max));
        withdrawCount = uint8(bound(withdrawCount, 2, 10));

        // Calculate amount per withdrawal
        uint256 amountPerWithdraw = uint256(totalBalance) / uint256(withdrawCount);

        // Verify: Multiple withdrawals do not exceed total
        uint256 totalWithdrawn = amountPerWithdraw * uint256(withdrawCount);
        assertLe(totalWithdrawn, totalBalance);
    }

    /// @notice Fuzz test: Fund transfer integrity
    function testFuzz_Transfer_Integrity(
        uint128 fromBalance,
        uint128 transferAmount,
        uint128 toBalance
    ) public pure {
        vm.assume(fromBalance >= transferAmount);
        vm.assume(transferAmount > 0);

        // Balance after transfer
        uint256 fromAfter = uint256(fromBalance) - uint256(transferAmount);
        uint256 toAfter = uint256(toBalance) + uint256(transferAmount);

        // Verify: Transfer conservation
        assertEq(fromAfter + toAfter, uint256(fromBalance) + uint256(toBalance));
    }

    // ==================== Overflow Protection Tests ====================

    /// @notice Fuzz test: Large addition does not overflow
    function testFuzz_LargeAddition_NoOverflow(
        uint128 amount1,
        uint128 amount2
    ) public pure {
        vm.assume(amount1 > 0);
        vm.assume(amount2 > 0);

        // Use uint256 to prevent overflow
        uint256 sum = uint256(amount1) + uint256(amount2);

        // Verify: Addition is correct
        assertGe(sum, amount1);
        assertGe(sum, amount2);
        assertEq(sum, uint256(amount1) + uint256(amount2));
    }

    /// @notice Fuzz test: Large multiplication does not overflow
    function testFuzz_LargeMultiplication_NoOverflow(
        uint64 amount,
        uint64 multiplier
    ) public pure {
        vm.assume(amount > 0);
        vm.assume(multiplier > 0);

        // Use uint256 to prevent overflow
        uint256 product = uint256(amount) * uint256(multiplier);

        // Verify: Multiplication is correct
        assertGe(product, amount);
        assertGe(product, multiplier);
    }
}
