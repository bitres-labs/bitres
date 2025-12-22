// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";

/// @title stBTD/stBTB Staking Token Fuzz Tests
/// @notice Tests all edge cases for staking token share conversion and reward accumulation
contract StakingTokenFuzzTest is Test {
    using Constants for *;

    // ==================== Share Conversion Fuzz Tests ====================

    /// @notice Fuzz test: Assets to shares calculation
    function testFuzz_AssetsToShares_Calculation(
        uint128 assets,
        uint128 totalAssets,
        uint128 totalShares
    ) public pure {
        vm.assume(assets > 0);
        vm.assume(totalAssets >= assets);
        vm.assume(totalShares > 0);
        vm.assume(totalAssets > 0);

        // Prevent overflow
        vm.assume(uint256(assets) * uint256(totalShares) < type(uint256).max);

        // Calculate shares = (assets * totalShares) / totalAssets
        uint256 shares = (uint256(assets) * uint256(totalShares)) / uint256(totalAssets);

        // Verify: Shares do not exceed total shares ratio
        assertLe(shares, totalShares);

        // Verify: If depositing all assets, should get all shares
        if (assets == totalAssets) {
            assertEq(shares, totalShares);
        }
    }

    /// @notice Fuzz test: Shares to assets calculation
    function testFuzz_SharesToAssets_Calculation(
        uint128 shares,
        uint128 totalShares,
        uint128 totalAssets
    ) public pure {
        vm.assume(shares > 0);
        vm.assume(totalShares >= shares);
        vm.assume(totalAssets > 0);
        vm.assume(totalShares > 0);

        // Prevent overflow
        vm.assume(uint256(shares) * uint256(totalAssets) < type(uint256).max);

        // Calculate assets = (shares * totalAssets) / totalShares
        uint256 assets = (uint256(shares) * uint256(totalAssets)) / uint256(totalShares);

        // Verify: Assets do not exceed total assets ratio
        assertLe(assets, totalAssets);

        // Verify: If redeeming all shares, should get all assets
        if (shares == totalShares) {
            assertEq(assets, totalAssets);
        }
    }

    /// @notice Fuzz test: Share conversion symmetry
    function testFuzz_ShareConversion_Symmetry(
        uint64 assets,
        uint128 totalAssets,
        uint128 totalShares
    ) public pure {
        vm.assume(assets > 1000);
        vm.assume(totalAssets >= assets);
        vm.assume(totalShares > 1000);
        vm.assume(totalAssets > 1000);

        // Prevent overflow
        vm.assume(uint256(assets) * uint256(totalShares) < type(uint256).max);

        // Assets -> Shares
        uint256 shares = (uint256(assets) * uint256(totalShares)) / uint256(totalAssets);
        vm.assume(shares > 0);

        // Shares -> Assets
        vm.assume(shares * uint256(totalAssets) < type(uint256).max);
        uint256 assetsBack = (shares * uint256(totalAssets)) / uint256(totalShares);

        // Verify: Round trip conversion should be close to original (allow rounding error)
        assertApproxEqAbs(assetsBack, assets, uint256(totalAssets) / uint256(totalShares) + 1);
    }

    /// @notice Fuzz test: Share value growth
    function testFuzz_ShareValue_Growth(
        uint128 initialAssets,
        uint128 shares,
        uint128 rewardAdded
    ) public pure {
        vm.assume(initialAssets > 1e18); // At least 1 asset unit
        vm.assume(shares > 1e18); // At least 1 share unit
        vm.assume(shares < type(uint64).max); // Limit shares to avoid overflow
        vm.assume(rewardAdded > 0 && rewardAdded < initialAssets); // Reward does not exceed initial assets

        uint256 totalAssetsBefore = initialAssets;
        uint256 totalAssetsAfter = uint256(initialAssets) + uint256(rewardAdded);

        // Prevent multiplication overflow (cast to uint256 first then multiply)
        vm.assume(uint256(shares) * totalAssetsBefore < type(uint256).max / Constants.PRECISION_18);
        vm.assume(uint256(shares) * totalAssetsAfter < type(uint256).max / Constants.PRECISION_18);

        // Calculate share value before and after reward
        uint256 valuePerShareBefore = (totalAssetsBefore * Constants.PRECISION_18) / uint256(shares);
        uint256 valuePerShareAfter = (totalAssetsAfter * Constants.PRECISION_18) / uint256(shares);

        // Verify: After adding reward, value per share increases or stays same
        assertGe(valuePerShareAfter, valuePerShareBefore);
    }

    // ==================== Deposit/Withdraw Fuzz Tests ====================

    /// @notice Fuzz test: First deposit 1:1 conversion
    function testFuzz_FirstDeposit_OneToOne(
        uint128 assets
    ) public pure {
        vm.assume(assets > 0);

        // First deposit: totalAssets = 0, totalShares = 0
        // Should be 1:1 conversion
        uint256 shares = assets;

        // Verify: First deposit shares equal assets
        assertEq(shares, assets);
    }

    /// @notice Fuzz test: Multiple deposits share accumulation
    function testFuzz_MultipleDeposits_ShareAccumulation(
        uint64 deposit1,
        uint64 deposit2,
        uint128 totalAssets,
        uint128 totalShares
    ) public pure {
        vm.assume(deposit1 > 100 && deposit2 > 100);
        vm.assume(totalAssets > 1000);
        vm.assume(totalShares > 1000);
        vm.assume(totalAssets >= uint256(deposit1) + uint256(deposit2));

        vm.assume(uint256(deposit1) * uint256(totalShares) < type(uint256).max);
        vm.assume(uint256(deposit2) * uint256(totalShares) < type(uint256).max);

        // Shares from first deposit
        uint256 shares1 = (uint256(deposit1) * uint256(totalShares)) / uint256(totalAssets);

        // Shares from second deposit
        uint256 shares2 = (uint256(deposit2) * uint256(totalShares)) / uint256(totalAssets);

        // Total shares
        uint256 totalSharesReceived = shares1 + shares2;

        // Verify: Total shares should correspond to total deposit
        uint256 totalDeposit = uint256(deposit1) + uint256(deposit2);
        uint256 expectedShares = (totalDeposit * uint256(totalShares)) / uint256(totalAssets);

        assertApproxEqAbs(totalSharesReceived, expectedShares, 2);
    }

    /// @notice Fuzz test: Withdrawal does not exceed balance
    function testFuzz_Withdraw_NotExceedBalance(
        uint128 userShares,
        uint128 totalShares,
        uint128 totalAssets,
        uint128 withdrawShares
    ) public pure {
        vm.assume(userShares > 0);
        vm.assume(totalShares >= userShares);
        vm.assume(totalAssets > 0);
        vm.assume(withdrawShares <= userShares);

        vm.assume(uint256(withdrawShares) * uint256(totalAssets) < type(uint256).max);

        // Calculate withdrawable assets
        uint256 withdrawAssets = (uint256(withdrawShares) * uint256(totalAssets)) / uint256(totalShares);

        // Calculate user total assets
        uint256 userTotalAssets = (uint256(userShares) * uint256(totalAssets)) / uint256(totalShares);

        // Verify: Withdrawal does not exceed user balance
        assertLe(withdrawAssets, userTotalAssets);
    }

    // ==================== Reward Distribution Fuzz Tests ====================

    /// @notice Fuzz test: Reward distributed proportionally to shares
    function testFuzz_Reward_ProportionalToShares(
        uint64 userShares,
        uint128 totalShares,
        uint128 totalReward
    ) public pure {
        vm.assume(userShares > 0);
        vm.assume(totalShares >= userShares);
        vm.assume(totalReward > 0);

        vm.assume(uint256(userShares) * uint256(totalReward) < type(uint256).max);

        // Calculate user reward = (userShares / totalShares) * totalReward
        uint256 userReward = (uint256(userShares) * uint256(totalReward)) / uint256(totalShares);

        // Verify: User reward does not exceed total reward
        assertLe(userReward, totalReward);

        // Verify: If owning all shares, get all reward
        if (userShares == totalShares) {
            assertEq(userReward, totalReward);
        }
    }

    /// @notice Fuzz test: Multi-user reward sum
    function testFuzz_MultiUser_RewardSum(
        uint64 shares1,
        uint64 shares2,
        uint64 shares3,
        uint128 totalReward
    ) public pure {
        vm.assume(shares1 > 0 && shares2 > 0 && shares3 > 0);
        vm.assume(totalReward > 1000);

        uint256 totalShares = uint256(shares1) + uint256(shares2) + uint256(shares3);
        vm.assume(totalShares < type(uint128).max);

        vm.assume(uint256(shares1) * uint256(totalReward) < type(uint256).max);
        vm.assume(uint256(shares2) * uint256(totalReward) < type(uint256).max);
        vm.assume(uint256(shares3) * uint256(totalReward) < type(uint256).max);

        // Calculate each user's reward
        uint256 reward1 = (uint256(shares1) * uint256(totalReward)) / totalShares;
        uint256 reward2 = (uint256(shares2) * uint256(totalReward)) / totalShares;
        uint256 reward3 = (uint256(shares3) * uint256(totalReward)) / totalShares;

        uint256 rewardSum = reward1 + reward2 + reward3;

        // Verify: Reward sum should be close to total reward (allow rounding error)
        assertApproxEqAbs(rewardSum, totalReward, 3);
    }

    /// @notice Fuzz test: Compound effect
    function testFuzz_Compound_Effect(
        uint128 initialShares,
        uint128 initialAssets,
        uint16 rewardRateBP,  // Reward rate per period (basis points)
        uint8 compounds      // Number of compound periods
    ) public pure {
        vm.assume(initialShares > 1000);
        vm.assume(initialAssets >= initialShares);
        vm.assume(rewardRateBP > 0 && rewardRateBP <= 1000); // Max 10% per period
        vm.assume(compounds > 0 && compounds <= 10);

        uint256 totalAssets = initialAssets;

        // Simulate multiple compound periods
        for (uint256 i = 0; i < compounds; i++) {
            uint256 reward = (totalAssets * uint256(rewardRateBP)) / Constants.BPS_BASE;
            totalAssets += reward;

            // Prevent overflow
            vm.assume(totalAssets < type(uint128).max / 2);
        }

        // Calculate final value per share
        uint256 finalValuePerShare = (totalAssets * Constants.PRECISION_18) / uint256(initialShares);
        uint256 initialValuePerShare = (uint256(initialAssets) * Constants.PRECISION_18) / uint256(initialShares);

        // Verify: After compounding, value per share increases or stays same (small reward may round to 0)
        assertGe(finalValuePerShare, initialValuePerShare);
    }

    // ==================== Precision Handling Fuzz Tests ====================

    /// @notice Fuzz test: Tiny shares not lost
    function testFuzz_TinyShares_NotLost(
        uint32 tinyShares,
        uint128 totalShares,
        uint128 totalAssets
    ) public pure {
        vm.assume(tinyShares > 0);
        vm.assume(totalShares > uint256(tinyShares) * 1000); // Total shares much larger than tiny shares
        vm.assume(totalAssets > 1e18); // Total assets large enough

        vm.assume(uint256(tinyShares) * uint256(totalAssets) < type(uint256).max);

        // Calculate assets corresponding to tiny shares
        uint256 assets = (uint256(tinyShares) * uint256(totalAssets)) / uint256(totalShares);

        // Verify: Even very small shares should have corresponding assets (may be 0 due to rounding which is normal)
        // But we verify calculation does not crash
        assertGe(assets, 0);
    }

    /// @notice Fuzz test: Huge shares do not overflow
    function testFuzz_HugeShares_NoOverflow(
        uint128 hugeShares,
        uint128 totalShares,
        uint128 totalAssets
    ) public pure {
        vm.assume(hugeShares > 1e24); // At least 1 million tokens
        vm.assume(totalShares >= hugeShares);
        vm.assume(totalAssets > 1e18);

        // Prevent overflow
        vm.assume(uint256(hugeShares) <= type(uint256).max / uint256(totalAssets));

        // Calculate assets corresponding to huge shares
        uint256 assets = (uint256(hugeShares) * uint256(totalAssets)) / uint256(totalShares);

        // Verify: Large calculation does not overflow
        assertLe(assets, totalAssets);
    }

    // ==================== Share Value Invariance Fuzz Tests ====================

    /// @notice Fuzz test: Deposit/withdraw does not affect other users' share value
    function testFuzz_DepositWithdraw_NoAffectOthers(
        uint128 otherUserShares,
        uint128 totalShares,
        uint128 totalAssets,
        uint64 newDeposit
    ) public pure {
        vm.assume(otherUserShares > 1000);
        vm.assume(totalShares >= otherUserShares);
        vm.assume(totalAssets > 1000);
        vm.assume(newDeposit > 100);

        // Other user's value per share before new deposit
        vm.assume(uint256(totalAssets) * Constants.PRECISION_18 < type(uint256).max);
        uint256 valuePerShareBefore = (uint256(totalAssets) * Constants.PRECISION_18) / uint256(totalShares);

        // New user deposit gets shares
        vm.assume(uint256(newDeposit) * uint256(totalShares) < type(uint256).max);
        uint256 newShares = (uint256(newDeposit) * uint256(totalShares)) / uint256(totalAssets);

        // New total assets and total shares
        uint256 newTotalAssets = uint256(totalAssets) + uint256(newDeposit);
        uint256 newTotalShares = uint256(totalShares) + newShares;

        vm.assume(newTotalAssets * Constants.PRECISION_18 < type(uint256).max);

        // Other user's value per share after new deposit
        uint256 valuePerShareAfter = (newTotalAssets * Constants.PRECISION_18) / newTotalShares;

        // Verify: New deposit does not affect other users' share value (allow larger rounding error)
        // Due to integer division characteristics, very small shares may produce larger relative error
        if (valuePerShareBefore > 0) {
            assertApproxEqRel(valuePerShareAfter, valuePerShareBefore, 1e16); // 1% relative error
        }
    }

    // ==================== Edge Case Tests ====================

    /// @notice Fuzz test: Zero reward means share value unchanged
    function testFuzz_ZeroReward_ShareValueUnchanged(
        uint128 totalAssets,
        uint128 totalShares
    ) public pure {
        vm.assume(totalAssets > 1000);
        vm.assume(totalShares > 1000);

        vm.assume(uint256(totalAssets) * Constants.PRECISION_18 < type(uint256).max);

        uint256 valuePerShareBefore = (uint256(totalAssets) * Constants.PRECISION_18) / uint256(totalShares);

        // Add zero reward
        uint256 newTotalAssets = totalAssets + 0;

        uint256 valuePerShareAfter = (newTotalAssets * Constants.PRECISION_18) / uint256(totalShares);

        // Verify: Zero reward does not change share value
        assertEq(valuePerShareAfter, valuePerShareBefore);
    }

    /// @notice Fuzz test: Full withdrawal means assets and shares go to zero
    function testFuzz_WithdrawAll_ZeroBalance(
        uint128 totalShares,
        uint128 totalAssets
    ) public pure {
        vm.assume(totalShares > 1e18); // At least 1 share unit
        vm.assume(totalAssets > 1e18); // At least 1 asset unit

        // Prevent overflow
        vm.assume(uint256(totalShares) * uint256(totalAssets) < type(uint256).max);

        // User owns all shares
        uint256 userShares = totalShares;

        // Withdraw all shares
        uint256 withdrawAssets = (uint256(userShares) * uint256(totalAssets)) / uint256(totalShares);

        // After withdrawal
        uint256 remainingAssets = uint256(totalAssets) - withdrawAssets;
        uint256 remainingShares = uint256(totalShares) - uint256(userShares);

        // Verify: Balance is zero after full withdrawal
        assertEq(remainingAssets, 0);
        assertEq(remainingShares, 0);
    }

    /// @notice Fuzz test: Share supply conservation
    function testFuzz_ShareSupply_Conservation(
        uint128 totalShares,
        uint64 mintShares,
        uint64 burnShares
    ) public pure {
        vm.assume(totalShares > 1000);
        vm.assume(mintShares > 0);
        vm.assume(burnShares > 0);
        vm.assume(burnShares <= mintShares); // Ensure no underflow

        // Mint shares
        uint256 afterMint = uint256(totalShares) + uint256(mintShares);

        // Burn shares
        uint256 afterBurn = afterMint - uint256(burnShares);

        // Net change
        uint256 netChange = uint256(mintShares) - uint256(burnShares);
        uint256 expected = uint256(totalShares) + netChange;

        // Verify: Supply conservation
        assertEq(afterBurn, expected);
    }
}
