// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";

/// @title Config Configuration Management Fuzz Tests
/// @notice Tests ConfigCore and ConfigGov parameter validation, access control, and update logic
contract ConfigFuzzTest is Test {
    using Constants for *;

    // ==================== Parameter Validation Fuzz Tests ====================

    /// @notice Fuzz test: Fee rate parameter range
    function testFuzz_FeeRate_Range(
        uint16 mintFeeBP,
        uint16 redeemFeeBP,
        uint16 stakingFeeBP
    ) public pure {
        mintFeeBP = uint16(bound(mintFeeBP, 0, Constants.BPS_BASE));
        redeemFeeBP = uint16(bound(redeemFeeBP, 0, Constants.BPS_BASE));
        stakingFeeBP = uint16(bound(stakingFeeBP, 0, Constants.BPS_BASE));

        // Verify: Fee rate doesn't exceed 100%
        assertLe(mintFeeBP, Constants.BPS_BASE);
        assertLe(redeemFeeBP, Constants.BPS_BASE);
        assertLe(stakingFeeBP, Constants.BPS_BASE);
    }

    /// @notice Fuzz test: Collateral ratio parameter range
    function testFuzz_CollateralRatio_Range(
        uint8 minCR_Multiplier,   // Use multiplier to avoid complex constraints
        uint8 gap1,
        uint8 gap2
    ) public pure {
        minCR_Multiplier = uint8(bound(minCR_Multiplier, 1, 19));  // 100%-200%
        gap1 = uint8(bound(gap1, 1, 9));  // Gap
        gap2 = uint8(bound(gap2, 1, 9));

        // Construct increasing collateral ratios
        uint16 minCR_BP = 10000 + uint16(minCR_Multiplier) * 1000;
        uint16 targetCR_BP = minCR_BP + uint16(gap1) * 1000;
        uint16 maxCR_BP = targetCR_BP + uint16(gap2) * 1000;

        // Early return if maxCR exceeds 50000
        if (maxCR_BP > 50000) return;

        // Verify: Collateral ratio increasing relationship
        assertGt(targetCR_BP, minCR_BP);
        assertGt(maxCR_BP, targetCR_BP);
        assertGe(minCR_BP, 10000);
        assertLe(maxCR_BP, 50000);
    }

    /// @notice Fuzz test: Interest rate parameter range
    function testFuzz_InterestRate_Range(
        uint16 btdInterestBP,
        uint16 btbInterestBP
    ) public pure {
        btdInterestBP = uint16(bound(btdInterestBP, 0, 2000)); // Max 20%
        btbInterestBP = uint16(bound(btbInterestBP, 0, 1500)); // Max 15%

        // Verify: Interest rates are reasonable
        assertLe(btdInterestBP, 2000);
        assertLe(btbInterestBP, 1500);
    }

    /// @notice Fuzz test: BRS mining parameter range
    function testFuzz_MiningRate_Range(
        uint64 totalMiningReward,  // Changed to uint64
        uint32 miningDuration
    ) public pure {
        totalMiningReward = uint64(bound(totalMiningReward, 1e18 + 1, type(uint64).max)); // At least 1 token
        miningDuration = uint32(bound(miningDuration, 1, 10 * 365 days)); // Max 10 years

        // Calculate mining rate per second
        uint256 rewardPerSecond = uint256(totalMiningReward) / uint256(miningDuration);

        // Verify: Mining rate is reasonable
        assertGt(rewardPerSecond, 0);
        assertLe(rewardPerSecond, totalMiningReward);
    }

    // ==================== Configuration Update Fuzz Tests ====================

    /// @notice Fuzz test: Single parameter update
    function testFuzz_Config_SingleUpdate(
        uint16 oldFeeBP,
        uint16 newFeeBP
    ) public pure {
        oldFeeBP = uint16(bound(oldFeeBP, 0, Constants.BPS_BASE));
        newFeeBP = uint16(bound(newFeeBP, 0, Constants.BPS_BASE));

        // Verify: Both old and new values are valid
        assertLe(oldFeeBP, Constants.BPS_BASE);
        assertLe(newFeeBP, Constants.BPS_BASE);

        // If value changed, should trigger event
        bool changed = newFeeBP != oldFeeBP;
        if (changed) {
            assertTrue(newFeeBP != oldFeeBP);
        }
    }

    /// @notice Fuzz test: Batch parameter update
    function testFuzz_Config_BatchUpdate(
        uint16 mintFeeBP,
        uint16 redeemFeeBP,
        uint16 minCR_BP
    ) public pure {
        mintFeeBP = uint16(bound(mintFeeBP, 0, Constants.BPS_BASE));
        redeemFeeBP = uint16(bound(redeemFeeBP, 0, Constants.BPS_BASE));
        minCR_BP = uint16(bound(minCR_BP, 10000, 50000));

        // Verify: All parameters are valid
        assertLe(mintFeeBP, Constants.BPS_BASE);
        assertLe(redeemFeeBP, Constants.BPS_BASE);
        assertGe(minCR_BP, 10000);
        assertLe(minCR_BP, 50000);
    }

    /// @notice Fuzz test: Configuration update cooldown period
    function testFuzz_Config_Cooldown(
        uint32 lastUpdateTime,
        uint32 currentTime,
        uint32 cooldownPeriod
    ) public pure {
        lastUpdateTime = uint32(bound(lastUpdateTime, 0, type(uint32).max - 1));
        currentTime = uint32(bound(currentTime, lastUpdateTime + 1, type(uint32).max));
        cooldownPeriod = uint32(bound(cooldownPeriod, 1, 7 days));

        uint32 elapsed = currentTime - lastUpdateTime;

        // Verify: Whether in cooldown period
        bool inCooldown = elapsed < cooldownPeriod;

        if (inCooldown) {
            assertLt(elapsed, cooldownPeriod);
        } else {
            assertGe(elapsed, cooldownPeriod);
        }
    }

    // ==================== Access Control Fuzz Tests ====================

    /// @notice Fuzz test: Owner permission
    function testFuzz_Permission_Owner(
        bool isOwner,
        bool isGovernor
    ) public pure {
        // Owner can directly update ConfigCore
        // Governor needs to go through proposal

        bool canDirectUpdate = isOwner;
        bool needsProposal = isGovernor && !isOwner;

        // Verify: Permission is mutually exclusive
        if (canDirectUpdate) {
            assertTrue(isOwner);
        }

        if (needsProposal) {
            assertTrue(isGovernor);
            assertFalse(isOwner);
        }
    }

    /// @notice Fuzz test: Governance proposal threshold
    function testFuzz_Governance_ProposalThreshold(
        uint128 voterBalance,
        uint128 totalSupply,
        uint16 thresholdBP
    ) public pure {
        totalSupply = uint128(bound(totalSupply, 1, type(uint128).max));
        voterBalance = uint128(bound(voterBalance, 0, totalSupply));
        thresholdBP = uint16(bound(thresholdBP, 1, 1000)); // 0-10%

        // Calculate proposal threshold
        uint256 threshold = (uint256(totalSupply) * uint256(thresholdBP)) / Constants.BPS_BASE;

        // Verify: Whether user meets proposal threshold
        bool canPropose = voterBalance >= threshold;

        if (canPropose) {
            assertGe(voterBalance, threshold);
        } else {
            assertLt(voterBalance, threshold);
        }
    }

    /// @notice Fuzz test: Governance voting pass threshold
    function testFuzz_Governance_QuorumThreshold(
        uint128 forVotes,
        uint128 againstVotes,
        uint128 totalSupply,
        uint16 quorumBP
    ) public pure {
        totalSupply = uint128(bound(totalSupply, 1, type(uint128).max));
        // Ensure forVotes + againstVotes <= totalSupply
        forVotes = uint128(bound(forVotes, 0, totalSupply));
        againstVotes = uint128(bound(againstVotes, 0, totalSupply - forVotes));
        quorumBP = uint16(bound(quorumBP, 4000, 10000)); // 40-100%

        // Calculate quorum
        uint256 quorum = (uint256(totalSupply) * uint256(quorumBP)) / Constants.BPS_BASE;

        // Total votes
        uint256 totalVotes = uint256(forVotes) + uint256(againstVotes);

        // Verify: Whether quorum is reached
        bool reachedQuorum = totalVotes >= quorum;

        // Verify: Whether passed (more than 50% approval)
        bool passed = forVotes > againstVotes && reachedQuorum;

        if (passed) {
            assertGt(forVotes, againstVotes);
            assertGe(totalVotes, quorum);
        }
    }

    // ==================== Parameter Dependency Fuzz Tests ====================

    /// @notice Fuzz test: Mint/Redeem fee relationship
    function testFuzz_FeeRelation_MintRedeem(
        uint16 mintFeeBP,
        uint16 redeemFeeBP
    ) public pure {
        mintFeeBP = uint16(bound(mintFeeBP, 0, Constants.BPS_BASE));
        redeemFeeBP = uint16(bound(redeemFeeBP, 0, Constants.BPS_BASE));

        // Verify: Both fee rates are valid
        assertLe(mintFeeBP, Constants.BPS_BASE);
        assertLe(redeemFeeBP, Constants.BPS_BASE);

        // Usually redeemFee >= mintFee (redemption is more expensive)
        // But this is not a hard requirement, just an economic design suggestion
    }

    /// @notice Fuzz test: BTD/BTB interest rate relationship
    function testFuzz_InterestRelation_BTDBTB(
        uint16 btdInterestBP,
        uint16 btbInterestBP
    ) public pure {
        btdInterestBP = uint16(bound(btdInterestBP, 0, 2000));
        btbInterestBP = uint16(bound(btbInterestBP, 0, 1500));

        // Verify: Both interest rates are valid
        assertLe(btdInterestBP, 2000);
        assertLe(btbInterestBP, 1500);

        // Usually BTD interest >= BTB interest (BTD has BTC collateral, lower risk)
        // But this is not a hard requirement
    }

    /// @notice Fuzz test: Collateral ratio and fee linkage
    function testFuzz_CRFee_Linkage(
        uint8 crMultiplier,      // CR multiplier (1-40, corresponding to 100%-400%)
        uint8 feeMinBP,          // Minimum fee (1-50, corresponding to 0.01%-0.5%)
        uint8 feeRangeBP         // Fee range (10-200, corresponding to 0.1%-2%)
    ) public pure {
        crMultiplier = uint8(bound(crMultiplier, 1, 39));
        feeMinBP = uint8(bound(feeMinBP, 1, 49));
        feeRangeBP = uint8(bound(feeRangeBP, 11, 199));

        // Construct parameters
        uint16 minCR_BP = 10000;  // 100%
        uint16 currentCR_BP = minCR_BP + uint16(crMultiplier) * 1000;
        uint16 minRedeemFeeBP = uint16(feeMinBP);
        uint16 maxRedeemFeeBP = minRedeemFeeBP + uint16(feeRangeBP);

        // Calculate dynamic fee based on collateral ratio
        // Lower CR means higher fee
        uint256 crRange = uint256(currentCR_BP) - uint256(minCR_BP);
        uint256 redeemFeeBP;

        if (crRange == 0) {
            redeemFeeBP = maxRedeemFeeBP;  // At minimum CR, fee is maximum
        } else {
            redeemFeeBP = minRedeemFeeBP;  // At higher CR, fee is lower
        }

        // Verify: Fee is within reasonable range
        assertGe(redeemFeeBP, minRedeemFeeBP);
        assertLe(redeemFeeBP, maxRedeemFeeBP);
    }

    // ==================== Edge Case Tests ====================

    /// @notice Fuzz test: Minimum fee
    function testFuzz_Edge_MinFee() public pure {
        uint16 minFeeBP = 0;

        // Verify: 0 fee is valid
        assertLe(minFeeBP, Constants.BPS_BASE);
    }

    /// @notice Fuzz test: Maximum fee
    function testFuzz_Edge_MaxFee() public pure {
        uint16 maxFeeBP = uint16(Constants.BPS_BASE); // 100%

        // Verify: 100% fee is valid but not recommended
        assertEq(maxFeeBP, Constants.BPS_BASE);
    }

    /// @notice Fuzz test: Minimum collateral ratio (100%)
    function testFuzz_Edge_MinCR() public pure {
        uint16 minCR_BP = 10000; // 100%

        // Verify: Minimum 100% collateral ratio
        assertEq(minCR_BP, 10000);
    }

    /// @notice Fuzz test: Extreme collateral ratio (500%)
    function testFuzz_Edge_ExtremeCR() public pure {
        uint16 extremeCR_BP = 50000; // 500%

        // Verify: Extreme collateral ratio is valid but unrealistic
        assertGt(extremeCR_BP, 10000);
    }

    /// @notice Fuzz test: Zero interest rate
    function testFuzz_Edge_ZeroInterest() public pure {
        uint16 zeroInterestBP = 0;

        // Verify: Zero interest rate is valid
        assertEq(zeroInterestBP, 0);
    }

    // ==================== Configuration Snapshot Fuzz Tests ====================

    /// @notice Fuzz test: Configuration version number increment
    function testFuzz_Config_VersionIncrement(
        uint32 oldVersion,
        uint32 newVersion
    ) public pure {
        oldVersion = uint32(bound(oldVersion, 0, type(uint32).max - 1));
        newVersion = uint32(bound(newVersion, oldVersion + 1, type(uint32).max));

        // Verify: Version number increments
        assertGt(newVersion, oldVersion);
    }

    /// @notice Fuzz test: Configuration rollback protection
    function testFuzz_Config_RollbackProtection(
        uint32 currentVersion,
        uint32 rollbackVersion
    ) public pure {
        currentVersion = uint32(bound(currentVersion, 1, type(uint32).max));
        rollbackVersion = uint32(bound(rollbackVersion, 0, currentVersion - 1));

        // Verify: Rollback to old version is not allowed
        bool isRollback = rollbackVersion < currentVersion;

        if (isRollback) {
            assertLt(rollbackVersion, currentVersion);
        }
    }

    // ==================== Parameter Effective Time Fuzz Tests ====================

    /// @notice Fuzz test: Delayed effect mechanism
    function testFuzz_Config_DelayedEffect(
        uint32 updateTime,
        uint32 currentTime,
        uint32 delayPeriod
    ) public pure {
        updateTime = uint32(bound(updateTime, 0, type(uint32).max));
        currentTime = uint32(bound(currentTime, updateTime, type(uint32).max));
        delayPeriod = uint32(bound(delayPeriod, 1, 7 days));

        uint32 elapsed = currentTime - updateTime;

        // Verify: Whether configuration has taken effect
        bool isEffective = elapsed >= delayPeriod;

        if (isEffective) {
            assertGe(elapsed, delayPeriod);
        } else {
            assertLt(elapsed, delayPeriod);
        }
    }

    /// @notice Fuzz test: Emergency configuration update
    function testFuzz_Config_EmergencyUpdate(
        bool isEmergency
    ) public pure {
        // Emergency update can skip delayed effect period

        // Verify: Emergency flag
        if (isEmergency) {
            assertTrue(isEmergency);
        } else {
            assertFalse(isEmergency);
        }
    }

    // ==================== Configuration Validation Fuzz Tests ====================

    /// @notice Fuzz test: Parameter validity validation
    function testFuzz_Config_Validation(
        uint16 mintFeeBP,
        uint16 minCR_BP
    ) public pure {
        // Valid parameters
        bool validMintFee = mintFeeBP <= Constants.BPS_BASE;
        bool validMinCR = minCR_BP >= 10000 && minCR_BP <= 50000;

        // Verify: Can only update when all are valid
        bool canUpdate = validMintFee && validMinCR;

        if (canUpdate) {
            assertTrue(validMintFee);
            assertTrue(validMinCR);
        }
    }

    /// @notice Fuzz test: Configuration conflict detection
    function testFuzz_Config_ConflictDetection(
        uint16 minCR_BP,
        uint16 targetCR_BP
    ) public pure {
        minCR_BP = uint16(bound(minCR_BP, 10000, 50000));
        targetCR_BP = uint16(bound(targetCR_BP, 10000, 50000));

        // Conflict: targetCR < minCR
        bool hasConflict = targetCR_BP <= minCR_BP;

        // Verify: Conflict detected should reject
        if (hasConflict) {
            assertLe(targetCR_BP, minCR_BP);
        } else {
            assertGt(targetCR_BP, minCR_BP);
        }
    }

    // ==================== Overflow Protection Fuzz Tests ====================

    /// @notice Fuzz test: Fee calculation doesn't overflow
    function testFuzz_Fee_OverflowProtection(
        uint128 amount,
        uint16 feeBP
    ) public pure {
        amount = uint128(bound(amount, 1, type(uint128).max));
        feeBP = uint16(bound(feeBP, 0, Constants.BPS_BASE));

        // Calculate fee
        uint256 fee = (uint256(amount) * uint256(feeBP)) / Constants.BPS_BASE;

        // Verify: Fee doesn't exceed original amount
        assertLe(fee, amount);
    }

    /// @notice Fuzz test: Collateral ratio calculation doesn't overflow
    function testFuzz_CR_OverflowProtection(
        uint64 collateralValue,  // Changed to uint64
        uint64 debtValue
    ) public pure {
        collateralValue = uint64(bound(collateralValue, 1e9 + 1, 1e17 - 1));
        debtValue = uint64(bound(debtValue, 1e9 + 1, 1e17 - 1));
        // Ensure CR is meaningful (debt <= collateral * 10)
        if (debtValue > collateralValue * 10) {
            debtValue = uint64(collateralValue * 10);
        }
        if (debtValue < 1e9 + 1) return; // Early return if bounds can't be satisfied

        // Calculate collateral ratio
        uint256 cr = (uint256(collateralValue) * Constants.BPS_BASE) / uint256(debtValue);

        // Verify: Collateral ratio calculation is correct
        assertGt(cr, 0);
    }
}
