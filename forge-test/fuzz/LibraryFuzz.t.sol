// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/MintLogic.sol";
import "../../contracts/libraries/RedeemLogic.sol";
import "../../contracts/libraries/RewardMath.sol";
import "../../contracts/libraries/InterestMath.sol";
import "../../contracts/libraries/Constants.sol";

/**
 * @title Library Fuzz Tests
 * @notice Comprehensive fuzz tests for all pure math libraries
 */
contract LibraryFuzzTest is Test {

    // ============ MintLogic Tests ============

    /// @notice Fuzz test MintLogic with valid inputs
    function testFuzz_MintLogic_ValidInputs(
        uint256 wbtcSeed,
        uint256 priceSeed,
        uint256 iusdSeed,
        uint16 feeBP
    ) public pure {
        uint256 wbtcAmount = bound(wbtcSeed, 1e8, 100e8); // 1 to 100 WBTC (8 decimals)
        uint256 wbtcPrice = bound(priceSeed, 20000e18, 100000e18); // $20k to $100k (18 decimals)
        uint256 iusdPrice = bound(iusdSeed, 0.9e18, 1.1e18); // 0.9 to 1.1 (18 decimals)
        feeBP = uint16(bound(feeBP, 0, 500)); // 0-5%

        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            currentBTDSupply: 0,
            feeBP: feeBP
        });

        MintLogic.MintOutputs memory out = MintLogic.evaluate(inputs);

        // Output should be positive
        assert(out.btdToMint > 0);

        // btdGross should equal btdToMint + fee
        assert(out.btdGross == out.btdToMint + out.fee);

        // Fee should be non-zero if feeBP > 0 and gross is large enough
        if (feeBP > 0 && out.btdGross >= 10000) {
            assert(out.fee > 0);
        }
    }

    /// @notice Fuzz test MintLogic fee calculation
    function testFuzz_MintLogic_FeeCalculation(
        uint256 wbtcSeed,
        uint16 feeBP
    ) public pure {
        uint256 wbtcAmount = bound(wbtcSeed, 1e8, 100e8);
        feeBP = uint16(bound(feeBP, 1, 1000)); // 0.01% to 10%

        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: 50000e18,
            iusdPrice: 1e18,
            currentBTDSupply: 0,
            feeBP: feeBP
        });

        MintLogic.MintOutputs memory out = MintLogic.evaluate(inputs);

        // Fee percentage should match gross amount (using mulDiv for precise calculation)
        uint256 expectedFee = (out.btdGross * feeBP) / 10000;

        // Allow for rounding (within 1 wei)
        assert(out.fee >= expectedFee - 1 && out.fee <= expectedFee + 1);
    }

    // ============ RedeemLogic Tests ============

    /// @notice Fuzz test RedeemLogic healthy redemption (CR >= 100%)
    function testFuzz_RedeemLogic_HealthyRedemption(
        uint64 btdAmount,
        uint64 wbtcPrice,
        uint16 feeBP
    ) public pure {
        btdAmount = uint64(bound(btdAmount, 100e18, 1000000e18)); // 100 to 1M BTD
        wbtcPrice = uint64(bound(wbtcPrice, 20000e18, 200000e18));
        feeBP = uint16(bound(feeBP, 0, 500));

        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: 1e18,
            cr: 1.5e18, // 150% CR - healthy
            btdPrice: 0,
            btbPrice: 0,
            brsPrice: 0,
            minBTBPriceInBTD: 0,
            redeemFeeBP: feeBP
        });

        RedeemLogic.RedeemOutputs memory out = RedeemLogic.evaluate(inputs);

        // Should get WBTC output
        assert(out.wbtcOutNormalized > 0);

        // No BTB or BRS compensation in healthy state
        assert(out.btbOut == 0);
        assert(out.brsOut == 0);
    }

    /// @notice Fuzz test RedeemLogic underwater redemption (CR < 100%)
    function testFuzz_RedeemLogic_UnderwaterRedemption(
        uint256 btdSeed,
        uint256 priceSeed,
        uint256 crSeed
    ) public pure {
        // Ensure minimum USD value is met (MIN_USD_VALUE = 1e6 from Constants)
        // After 0.5% fee deduction, effective amount must still be >= 1e6
        uint256 btdAmount = bound(btdSeed, 1000e18, 100000e18); // 1000 to 100k BTD
        uint256 wbtcPrice = bound(priceSeed, 20000e18, 100000e18); // $20k to $100k
        uint256 cr = bound(crSeed, 0.5e18, 0.99e18); // 50% to 99% CR

        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: 1e18,
            cr: cr,
            btdPrice: 1e18,
            btbPrice: 0.5e18, // BTB at 50% of BTD
            brsPrice: 0.1e18, // BRS at $0.10
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: 50 // 0.5%
        });

        RedeemLogic.RedeemOutputs memory out = RedeemLogic.evaluate(inputs);

        // Should get some WBTC (proportional to CR)
        assert(out.wbtcOutNormalized > 0);

        // Should get BTB compensation (since BTB price 0.5 > min 0.3)
        assert(out.btbOut > 0);
    }

    // ============ RewardMath Tests ============

    /// @notice Fuzz test emission calculation
    function testFuzz_RewardMath_Emission(
        uint256 rewardSeed,
        uint256 durationSeed,
        uint256 allocSeed,
        uint256 totalAllocSeed
    ) public pure {
        uint256 rewardPerSecond = bound(rewardSeed, 1e15, 1e20); // 0.001 to 100 tokens/sec
        uint256 duration = bound(durationSeed, 1, 365 days);
        uint256 allocPoint = bound(allocSeed, 1, 10000);
        uint256 totalAllocPoint = bound(totalAllocSeed, allocPoint, 100000);

        uint256 emission = RewardMath.emissionFor(
            duration,
            rewardPerSecond,
            allocPoint,
            totalAllocPoint
        );

        // If all inputs are non-zero, emission should be positive
        if (duration > 0 && rewardPerSecond > 0 && allocPoint > 0 && totalAllocPoint > 0) {
            assert(emission > 0);
        }

        // Emission should not exceed max possible
        uint256 expectedMax = rewardPerSecond * duration;
        assert(emission <= expectedMax);
    }

    /// @notice Fuzz test reward clamping
    function testFuzz_RewardMath_Clamp(
        uint256 mintedSeed,
        uint256 rewardSeed,
        uint256 maxSupplySeed
    ) public pure {
        uint256 minted = bound(mintedSeed, 0, 1e24);
        uint256 maxSupply = bound(maxSupplySeed, minted, 1e25);
        uint256 reward = bound(rewardSeed, 0, 1e24);

        uint256 clamped = RewardMath.clampToMax(minted, reward, maxSupply);

        // Clamped should not exceed remaining supply
        assert(minted + clamped <= maxSupply);

        // If enough room, should equal original reward
        if (minted + reward <= maxSupply) {
            assert(clamped == reward);
        }
    }

    /// @notice Fuzz test accumulated reward per share
    function testFuzz_RewardMath_AccRewardPerShare(
        uint256 currentSeed,
        uint256 rewardSeed,
        uint256 stakedSeed
    ) public pure {
        uint256 currentAcc = bound(currentSeed, 0, 1e24);
        uint256 reward = bound(rewardSeed, 0, 1e20);
        uint256 totalStaked = bound(stakedSeed, 1e18, 1e24); // Avoid small values

        uint256 newAcc = RewardMath.accRewardPerShare(currentAcc, reward, totalStaked);

        // Should be >= current
        assert(newAcc >= currentAcc);

        // If reward is 0, should be unchanged
        if (reward == 0) {
            assert(newAcc == currentAcc);
        }
    }

    /// @notice Fuzz test pending reward calculation
    function testFuzz_RewardMath_Pending(
        uint256 amountSeed,
        uint256 accSeed,
        uint256 debtSeed
    ) public pure {
        uint256 amount = bound(amountSeed, 0, 1e24);
        uint256 accPerShare = bound(accSeed, 0, 1e20);

        // Calculate max possible debt (amount * accPerShare / 1e12)
        uint256 maxDebt = (amount * accPerShare) / 1e12;
        uint256 rewardDebt = bound(debtSeed, 0, maxDebt);

        uint256 pendingReward = RewardMath.pending(amount, accPerShare, rewardDebt);

        // Pending should be (amount * accPerShare / 1e12) - rewardDebt or 0
        uint256 accumulated = (amount * accPerShare) / 1e12;
        if (accumulated > rewardDebt) {
            assert(pendingReward == accumulated - rewardDebt);
        } else {
            assert(pendingReward == 0);
        }
    }

    // ============ InterestMath Tests ============

    /// @notice Fuzz test interest per share delta
    function testFuzz_InterestMath_PerShareDelta(
        uint16 annualRateBps,
        uint32 timeElapsed
    ) public pure {
        annualRateBps = uint16(bound(annualRateBps, 0, 5000)); // 0-50% APR
        timeElapsed = uint32(bound(timeElapsed, 0, 365 days));

        uint256 delta = InterestMath.interestPerShareDelta(annualRateBps, timeElapsed);

        // Delta should be proportional to rate and time
        if (annualRateBps == 0 || timeElapsed == 0) {
            assert(delta == 0);
        } else {
            assert(delta > 0);
        }

        // Upper bound check
        uint256 maxDelta = (uint256(annualRateBps) * 1e18 * timeElapsed) / (365 days * 10000);
        assert(delta <= maxDelta + 1); // Allow 1 for rounding
    }

    /// @notice Fuzz test fee calculation
    function testFuzz_InterestMath_Fee(
        uint64 amount,
        uint16 feeBps
    ) public pure {
        amount = uint64(bound(amount, 0, 1e24));
        feeBps = uint16(bound(feeBps, 0, 10000)); // 0-100%

        uint256 fee = InterestMath.feeAmount(amount, feeBps);

        // Fee should be correct percentage
        uint256 expected = (uint256(amount) * feeBps) / 10000;
        assert(fee == expected);

        // Fee should not exceed amount
        assert(fee <= amount);
    }

    /// @notice Fuzz test split withdrawal
    function testFuzz_InterestMath_SplitWithdrawal(
        uint256 amountSeed,
        uint256 interestSeed,
        uint256 availableSeed
    ) public pure {
        uint256 amount = bound(amountSeed, 1e18, 1e24);
        uint256 pendingInterest = bound(interestSeed, 0, amount);
        uint256 totalAvailable = bound(availableSeed, amount, 1e25);

        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            amount,
            pendingInterest,
            totalAvailable
        );

        // Sum should equal requested amount
        assert(interestShare + principalShare == amount);

        // Interest share should not exceed pending
        assert(interestShare <= pendingInterest);
    }

}
