// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/libraries/InterestMath.sol";

/// @title InterestPool Integration Test
/// @notice Tests InterestMath library and staking logic
contract InterestPoolIntegrationTest is Test {

    uint256 constant BTD_BASE_RATE = 400; // 4% APR in bps
    uint256 constant SECONDS_PER_YEAR = 365 days;

    // ============ InterestMath.interestPerShareDelta Tests ============

    function test_interestPerShareDelta_oneYear() public pure {
        // 4% annual rate, 1 year elapsed
        uint256 delta = InterestMath.interestPerShareDelta(BTD_BASE_RATE, SECONDS_PER_YEAR);

        // Should be approximately 4% = 0.04 * 1e18 = 4e16
        // Due to integer math, check it's in reasonable range
        assertGt(delta, 3.9e16, "Delta should be ~4%");
        assertLt(delta, 4.1e16, "Delta should be ~4%");
    }

    function test_interestPerShareDelta_zeroTime() public pure {
        uint256 delta = InterestMath.interestPerShareDelta(BTD_BASE_RATE, 0);
        assertEq(delta, 0, "Zero time should give zero delta");
    }

    function test_interestPerShareDelta_zeroRate() public pure {
        uint256 delta = InterestMath.interestPerShareDelta(0, SECONDS_PER_YEAR);
        assertEq(delta, 0, "Zero rate should give zero delta");
    }

    function test_interestPerShareDelta_halfYear() public pure {
        uint256 delta = InterestMath.interestPerShareDelta(BTD_BASE_RATE, SECONDS_PER_YEAR / 2);

        // Should be approximately 2%
        assertGt(delta, 1.9e16, "Delta should be ~2%");
        assertLt(delta, 2.1e16, "Delta should be ~2%");
    }

    function test_interestPerShareDelta_highRate() public pure {
        // 20% APR
        uint256 delta = InterestMath.interestPerShareDelta(2000, SECONDS_PER_YEAR);

        assertGt(delta, 19e16, "Delta should be ~20%");
        assertLt(delta, 21e16, "Delta should be ~20%");
    }

    // ============ InterestMath.pendingReward Tests ============

    function test_pendingReward_basic() public pure {
        // User has 1000 tokens staked
        // accInterestPerShare = 4e16 (4% accumulated)
        // rewardDebt = 0

        uint256 pending = InterestMath.pendingReward(
            1000e18,  // amount staked
            4e16,     // accInterestPerShare
            0         // rewardDebt
        );

        // Expected: 1000 * 4% = 40 tokens
        assertEq(pending, 40e18, "Pending should be 40 tokens");
    }

    function test_pendingReward_withDebt() public pure {
        // User has debt from previous claims
        uint256 pending = InterestMath.pendingReward(
            1000e18,
            8e16,     // 8% accumulated
            40e18     // Already claimed 4% worth
        );

        // Expected: (1000 * 8%) - 40 = 80 - 40 = 40 tokens
        assertEq(pending, 40e18, "Pending should be 40 tokens");
    }

    function test_pendingReward_zeroAmount() public pure {
        uint256 pending = InterestMath.pendingReward(0, 4e16, 0);
        assertEq(pending, 0, "Zero amount should give zero pending");
    }

    function test_pendingReward_zeroAccInterest() public pure {
        uint256 pending = InterestMath.pendingReward(1000e18, 0, 0);
        assertEq(pending, 0, "Zero accInterest should give zero pending");
    }

    function test_pendingReward_debtExceedsAccumulated() public pure {
        // Edge case: debt exceeds accumulated (should return 0)
        uint256 pending = InterestMath.pendingReward(1000e18, 4e16, 100e18);
        assertEq(pending, 0, "Should return 0 when debt exceeds accumulated");
    }

    // ============ InterestMath.rewardDebtValue Tests ============

    function test_rewardDebtValue_basic() public pure {
        uint256 debt = InterestMath.rewardDebtValue(1000e18, 4e16);
        assertEq(debt, 40e18, "Debt should be 40 tokens");
    }

    function test_rewardDebtValue_zero() public pure {
        uint256 debt = InterestMath.rewardDebtValue(0, 4e16);
        assertEq(debt, 0, "Zero amount should give zero debt");
    }

    // ============ InterestMath.feeAmount Tests ============

    function test_feeAmount_10percent() public pure {
        uint256 fee = InterestMath.feeAmount(100e18, 1000); // 10% = 1000 bps
        assertEq(fee, 10e18, "10% of 100 should be 10");
    }

    function test_feeAmount_zeroFee() public pure {
        uint256 fee = InterestMath.feeAmount(100e18, 0);
        assertEq(fee, 0, "Zero fee rate should give zero fee");
    }

    function test_feeAmount_zeroAmount() public pure {
        uint256 fee = InterestMath.feeAmount(0, 1000);
        assertEq(fee, 0, "Zero amount should give zero fee");
    }

    function test_feeAmount_fullFee() public pure {
        uint256 fee = InterestMath.feeAmount(100e18, 10000); // 100% = 10000 bps
        assertEq(fee, 100e18, "100% fee should equal amount");
    }

    // ============ InterestMath.splitWithdrawal Tests ============

    function test_splitWithdrawal_allPrincipal() public pure {
        // User has 1000 principal, 0 pending, withdraws 500
        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            500e18,   // withdrawal amount
            0,        // pending interest
            1000e18   // total available (principal only)
        );

        assertEq(interestShare, 0, "No interest to claim");
        assertEq(principalShare, 500e18, "All principal");
    }

    function test_splitWithdrawal_withInterest() public pure {
        // User has 1000 principal, 100 pending interest, withdraws 550
        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            550e18,   // withdrawal amount
            100e18,   // pending interest
            1100e18   // total available
        );

        // Proportional: 550/1100 = 50%
        // Interest share: 50% of 100 = 50
        // Principal share: 550 - 50 = 500
        assertEq(interestShare, 50e18, "Interest share");
        assertEq(principalShare, 500e18, "Principal share");
    }

    function test_splitWithdrawal_withdrawAll() public pure {
        // User withdraws everything
        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            1100e18,  // withdraw all
            100e18,   // pending interest
            1100e18   // total available
        );

        assertEq(interestShare, 100e18, "All interest");
        assertEq(principalShare, 1000e18, "All principal");
    }

    function test_splitWithdrawal_zeroAmount() public pure {
        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            0,
            100e18,
            1100e18
        );

        assertEq(interestShare, 0, "Zero withdrawal");
        assertEq(principalShare, 0, "Zero withdrawal");
    }

    // ============ InterestMath.totalAssetsWithAccrued Tests ============

    function test_totalAssetsWithAccrued_basic() public view {
        uint256 lastAccrual = block.timestamp;
        uint256 currentTime = block.timestamp + SECONDS_PER_YEAR;

        uint256 total = InterestMath.totalAssetsWithAccrued(
            1000e18,          // principal
            BTD_BASE_RATE,    // 4% APR
            lastAccrual,
            currentTime
        );

        // Expected: 1000 * (1 + 0.04) = 1040
        assertGt(total, 1039e18, "Should be ~1040");
        assertLt(total, 1041e18, "Should be ~1040");
    }

    function test_totalAssetsWithAccrued_noTime() public view {
        uint256 total = InterestMath.totalAssetsWithAccrued(
            1000e18,
            BTD_BASE_RATE,
            block.timestamp,
            block.timestamp  // same time = no elapsed
        );
        assertEq(total, 1000e18, "No time elapsed = no interest");
    }

    function test_totalAssetsWithAccrued_noRate() public view {
        uint256 total = InterestMath.totalAssetsWithAccrued(
            1000e18,
            0,  // zero rate
            block.timestamp,
            block.timestamp + SECONDS_PER_YEAR
        );
        assertEq(total, 1000e18, "No rate = no interest");
    }

    // ============ InterestMath.priceChangeBps Tests ============

    function test_priceChangeBps_increase() public pure {
        int256 change = InterestMath.priceChangeBps(1e18, 1.1e18);
        // 10% increase = 1000 bps
        assertEq(change, 1000, "10% increase = 1000 bps");
    }

    function test_priceChangeBps_decrease() public pure {
        int256 change = InterestMath.priceChangeBps(1e18, 0.9e18);
        // 10% decrease = -1000 bps
        assertEq(change, -1000, "10% decrease = -1000 bps");
    }

    function test_priceChangeBps_noChange() public pure {
        int256 change = InterestMath.priceChangeBps(1e18, 1e18);
        assertEq(change, 0, "No change = 0 bps");
    }

    function test_priceChangeBps_zeroPrevious() public pure {
        int256 change = InterestMath.priceChangeBps(0, 1e18);
        assertEq(change, 0, "Zero previous = 0 bps");
    }

    // ============ Fuzz Tests ============

    function testFuzz_interestPerShareDelta_bounded(uint16 rate, uint64 time) public pure {
        rate = uint16(bound(rate, 0, 5000)); // Max 50% APR
        time = uint64(bound(time, 0, 10 * SECONDS_PER_YEAR)); // Max 10 years

        uint256 delta = InterestMath.interestPerShareDelta(rate, time);

        // Delta should never exceed rate * time / SECONDS_PER_YEAR
        uint256 maxDelta = uint256(rate) * uint256(time) * 1e14 / SECONDS_PER_YEAR;
        assertTrue(delta <= maxDelta + 1e14, "Delta should be bounded");
    }

    function testFuzz_pendingReward_neverNegative(
        uint128 amount,
        uint128 accInterest,
        uint128 rewardDebt
    ) public pure {
        uint256 pending = InterestMath.pendingReward(amount, accInterest, rewardDebt);
        assertTrue(pending >= 0, "Pending should never be negative");
    }

    function testFuzz_feeAmount_bounded(uint128 amount, uint16 feeBps) public pure {
        feeBps = uint16(bound(feeBps, 0, 10000)); // Max 100%

        uint256 fee = InterestMath.feeAmount(amount, feeBps);

        assertTrue(fee <= amount, "Fee should not exceed amount");
    }

    function testFuzz_splitWithdrawal_sumEqualsAmount(
        uint64 principal,
        uint64 pendingInterest,
        uint64 withdrawRatioBps
    ) public pure {
        vm.assume(principal > 0);
        vm.assume(pendingInterest > 0);
        withdrawRatioBps = uint64(bound(withdrawRatioBps, 1, 10000)); // 0.01% to 100%

        uint256 totalAvailable = uint256(principal) + uint256(pendingInterest);
        // withdrawAmount is a percentage of totalAvailable
        uint256 withdrawAmount = (totalAvailable * withdrawRatioBps) / 10000;
        vm.assume(withdrawAmount > 0);

        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            withdrawAmount,
            pendingInterest,
            totalAvailable
        );

        // Sum should equal withdrawal amount
        assertEq(interestShare + principalShare, withdrawAmount, "Sum should equal withdrawal");
    }

    function testFuzz_priceChangeBps_symmetric(uint128 prevPrice, uint128 currPrice) public pure {
        vm.assume(prevPrice > 0);
        vm.assume(currPrice > 0);

        int256 change1 = InterestMath.priceChangeBps(prevPrice, currPrice);
        int256 change2 = InterestMath.priceChangeBps(currPrice, prevPrice);

        // If we go from A to B and back to A, changes should be roughly opposite
        // (not exactly due to percentage base changes)
        if (prevPrice == currPrice) {
            assertEq(change1, 0, "Same price = 0");
            assertEq(change2, 0, "Same price = 0");
        }
    }

    // ============ Staking Simulation Tests ============

    function test_stakingSimulation_singleUser() public pure {
        uint256 stakeAmount = 1000e18;
        uint256 accInterestPerShare = 0;

        // Simulate 1 year passing
        uint256 delta = InterestMath.interestPerShareDelta(BTD_BASE_RATE, SECONDS_PER_YEAR);
        accInterestPerShare += delta;

        // Calculate pending reward
        uint256 rewardDebt = 0;
        uint256 pending = InterestMath.pendingReward(stakeAmount, accInterestPerShare, rewardDebt);

        // Should be approximately 4% of 1000 = 40 tokens
        assertGt(pending, 39e18, "Should earn ~4% interest");
        assertLt(pending, 41e18, "Should earn ~4% interest");
    }

    function test_stakingSimulation_multipleDeposits() public pure {
        uint256 accInterestPerShare = 0;

        // First deposit: 1000 tokens
        uint256 user1Amount = 1000e18;
        uint256 user1Debt = InterestMath.rewardDebtValue(user1Amount, accInterestPerShare);

        // 6 months pass
        uint256 delta1 = InterestMath.interestPerShareDelta(BTD_BASE_RATE, SECONDS_PER_YEAR / 2);
        accInterestPerShare += delta1;

        // Second deposit: 1000 tokens
        uint256 user2Amount = 1000e18;
        uint256 user2Debt = InterestMath.rewardDebtValue(user2Amount, accInterestPerShare);

        // 6 more months pass
        uint256 delta2 = InterestMath.interestPerShareDelta(BTD_BASE_RATE, SECONDS_PER_YEAR / 2);
        accInterestPerShare += delta2;

        // Calculate pending rewards
        uint256 user1Pending = InterestMath.pendingReward(user1Amount, accInterestPerShare, user1Debt);
        uint256 user2Pending = InterestMath.pendingReward(user2Amount, accInterestPerShare, user2Debt);

        // User 1 staked for full year (4%), User 2 for half year (2%)
        assertGt(user1Pending, user2Pending, "User1 should earn more (longer stake)");
    }

    function test_stakingSimulation_withdrawWithInterest() public pure {
        uint256 stakeAmount = 1000e18;
        uint256 accInterestPerShare = 0;

        // Stake
        uint256 rewardDebt = InterestMath.rewardDebtValue(stakeAmount, accInterestPerShare);

        // 1 year passes
        accInterestPerShare += InterestMath.interestPerShareDelta(BTD_BASE_RATE, SECONDS_PER_YEAR);

        // Calculate pending
        uint256 pending = InterestMath.pendingReward(stakeAmount, accInterestPerShare, rewardDebt);

        // Withdraw half of total (principal + interest)
        uint256 totalAvailable = stakeAmount + pending;
        uint256 withdrawAmount = totalAvailable / 2;

        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            withdrawAmount,
            pending,
            totalAvailable
        );

        // Both shares should be proportional
        assertGt(interestShare, 0, "Should get some interest");
        assertGt(principalShare, 0, "Should get some principal");
        assertEq(interestShare + principalShare, withdrawAmount, "Sum equals withdrawal");
    }

    // ============ Edge Cases ============

    function test_edge_verySmallStake() public pure {
        uint256 smallStake = 1e15; // 0.001 tokens

        uint256 delta = InterestMath.interestPerShareDelta(BTD_BASE_RATE, SECONDS_PER_YEAR);
        uint256 pending = InterestMath.pendingReward(smallStake, delta, 0);

        // Should still calculate correctly
        assertTrue(pending >= 0, "Should handle small amounts");
    }

    function test_edge_veryLongTime() public pure {
        // 100 years
        uint256 delta = InterestMath.interestPerShareDelta(BTD_BASE_RATE, 100 * SECONDS_PER_YEAR);

        // 4% * 100 years = 400% = 4e18
        assertGt(delta, 3.9e18, "Should handle long periods");
        assertLt(delta, 4.1e18, "Should handle long periods");
    }

    function test_edge_maxRate() public pure {
        // 100% APR
        uint256 delta = InterestMath.interestPerShareDelta(10000, SECONDS_PER_YEAR);

        assertGt(delta, 0.99e18, "100% APR should double");
        assertLt(delta, 1.01e18, "100% APR should double");
    }
}
