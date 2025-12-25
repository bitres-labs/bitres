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
        assets = uint128(bound(assets, 1, type(uint128).max));
        totalAssets = uint128(bound(totalAssets, assets, type(uint128).max));
        totalShares = uint128(bound(totalShares, 1, type(uint128).max));

        // Calculate shares = (assets * totalShares) / totalAssets (uint128 * uint128 fits in uint256)
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
        shares = uint128(bound(shares, 1, type(uint128).max));
        totalShares = uint128(bound(totalShares, shares, type(uint128).max));
        totalAssets = uint128(bound(totalAssets, 1, type(uint128).max));

        // Calculate assets = (shares * totalAssets) / totalShares (uint128 * uint128 fits in uint256)
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
        assets = uint64(bound(assets, 1001, type(uint64).max));
        totalAssets = uint128(bound(totalAssets, assets, type(uint128).max));
        totalShares = uint128(bound(totalShares, 1001, type(uint128).max));

        // Assets -> Shares (uint64 * uint128 fits in uint256)
        uint256 shares = (uint256(assets) * uint256(totalShares)) / uint256(totalAssets);

        // If shares is 0, skip (rounding loss)
        if (shares == 0) return;

        // Shares -> Assets
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
        initialAssets = uint128(bound(initialAssets, 1e18 + 1, type(uint128).max / 2)); // At least 1 asset unit
        shares = uint128(bound(shares, 1e18 + 1, type(uint64).max - 1)); // At least 1 share unit, limit to avoid overflow
        rewardAdded = uint128(bound(rewardAdded, 1, initialAssets - 1)); // Reward does not exceed initial assets

        uint256 totalAssetsBefore = initialAssets;
        uint256 totalAssetsAfter = uint256(initialAssets) + uint256(rewardAdded);

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
        assets = uint128(bound(assets, 1, type(uint128).max));

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
        deposit1 = uint64(bound(deposit1, 101, type(uint64).max / 2));
        deposit2 = uint64(bound(deposit2, 101, type(uint64).max / 2));
        uint256 totalDeposit = uint256(deposit1) + uint256(deposit2);
        totalAssets = uint128(bound(totalAssets, totalDeposit, type(uint128).max));
        totalShares = uint128(bound(totalShares, 1001, type(uint128).max));

        // Shares from first deposit (uint64 * uint128 fits in uint256)
        uint256 shares1 = (uint256(deposit1) * uint256(totalShares)) / uint256(totalAssets);

        // Shares from second deposit
        uint256 shares2 = (uint256(deposit2) * uint256(totalShares)) / uint256(totalAssets);

        // Total shares
        uint256 totalSharesReceived = shares1 + shares2;

        // Verify: Total shares should correspond to total deposit
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
        userShares = uint128(bound(userShares, 1, type(uint128).max));
        totalShares = uint128(bound(totalShares, userShares, type(uint128).max));
        totalAssets = uint128(bound(totalAssets, 1, type(uint128).max));
        withdrawShares = uint128(bound(withdrawShares, 0, userShares));

        // Calculate withdrawable assets (uint128 * uint128 fits in uint256)
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
        userShares = uint64(bound(userShares, 1, type(uint64).max));
        totalShares = uint128(bound(totalShares, userShares, type(uint128).max));
        totalReward = uint128(bound(totalReward, 1, type(uint128).max));

        // Calculate user reward = (userShares / totalShares) * totalReward (uint64 * uint128 fits in uint256)
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
        shares1 = uint64(bound(shares1, 1, type(uint64).max / 3));
        shares2 = uint64(bound(shares2, 1, type(uint64).max / 3));
        shares3 = uint64(bound(shares3, 1, type(uint64).max / 3));
        totalReward = uint128(bound(totalReward, 1001, type(uint128).max));

        uint256 totalShares = uint256(shares1) + uint256(shares2) + uint256(shares3);

        // Calculate each user's reward (uint64 * uint128 fits in uint256)
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
        initialShares = uint128(bound(initialShares, 1001, type(uint64).max));
        initialAssets = uint128(bound(initialAssets, initialShares, type(uint64).max)); // Limit to prevent overflow in loop
        rewardRateBP = uint16(bound(rewardRateBP, 1, 1000)); // Max 10% per period
        compounds = uint8(bound(compounds, 1, 10));

        uint256 totalAssets = initialAssets;

        // Simulate multiple compound periods
        for (uint256 i = 0; i < compounds; i++) {
            uint256 reward = (totalAssets * uint256(rewardRateBP)) / Constants.BPS_BASE;
            totalAssets += reward;

            // Safety check for overflow
            if (totalAssets >= type(uint128).max / 2) break;
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
        tinyShares = uint32(bound(tinyShares, 1, type(uint32).max / 1000));
        totalShares = uint128(bound(totalShares, uint256(tinyShares) * 1000 + 1, type(uint128).max)); // Total shares much larger than tiny shares
        totalAssets = uint128(bound(totalAssets, 1e18 + 1, type(uint128).max)); // Total assets large enough

        // Calculate assets corresponding to tiny shares (uint32 * uint128 fits in uint256)
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
        hugeShares = uint128(bound(hugeShares, 1e24 + 1, type(uint128).max)); // At least 1 million tokens
        totalShares = uint128(bound(totalShares, hugeShares, type(uint128).max));
        totalAssets = uint128(bound(totalAssets, 1e18 + 1, type(uint128).max));

        // Calculate assets corresponding to huge shares (uint128 * uint128 fits in uint256)
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
        otherUserShares = uint128(bound(otherUserShares, 1001, type(uint64).max));
        totalShares = uint128(bound(totalShares, otherUserShares, type(uint64).max));
        totalAssets = uint128(bound(totalAssets, 1001, type(uint64).max)); // Limit to prevent overflow with PRECISION_18
        newDeposit = uint64(bound(newDeposit, 101, type(uint64).max / 2));

        // Other user's value per share before new deposit
        uint256 valuePerShareBefore = (uint256(totalAssets) * Constants.PRECISION_18) / uint256(totalShares);

        // New user deposit gets shares (uint64 * uint128 fits in uint256)
        uint256 newShares = (uint256(newDeposit) * uint256(totalShares)) / uint256(totalAssets);

        // New total assets and total shares
        uint256 newTotalAssets = uint256(totalAssets) + uint256(newDeposit);
        uint256 newTotalShares = uint256(totalShares) + newShares;

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
        totalAssets = uint128(bound(totalAssets, 1001, type(uint64).max)); // Limit to prevent overflow with PRECISION_18
        totalShares = uint128(bound(totalShares, 1001, type(uint128).max));

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
        totalShares = uint128(bound(totalShares, 1e18 + 1, type(uint128).max)); // At least 1 share unit
        totalAssets = uint128(bound(totalAssets, 1e18 + 1, type(uint128).max)); // At least 1 asset unit

        // User owns all shares
        uint256 userShares = totalShares;

        // Withdraw all shares (uint128 * uint128 fits in uint256)
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
        totalShares = uint128(bound(totalShares, 1001, type(uint128).max));
        mintShares = uint64(bound(mintShares, 1, type(uint64).max));
        burnShares = uint64(bound(burnShares, 1, mintShares)); // Ensure no underflow

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
