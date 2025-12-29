// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/PriceBlend.sol";
import "../../contracts/libraries/MintLogic.sol";
import "../../contracts/libraries/RedeemLogic.sol";
import "../../contracts/libraries/RewardMath.sol";
import "../../contracts/libraries/InterestMath.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/libraries/TokenPrecision.sol";

/**
 * @title Library Fuzz Tests
 * @notice Comprehensive fuzz tests for all pure math libraries
 */
contract LibraryFuzzTest is Test {

    // ============ PriceBlend Tests ============

    /// @notice Fuzz test median3 returns middle value
    function testFuzz_Median3_ReturnsMiddle(uint64 a, uint64 b, uint64 c) public pure {
        uint256 result = PriceBlend.median3(a, b, c);

        // Result should be >= min and <= max of inputs
        uint256 minVal = a < b ? (a < c ? a : c) : (b < c ? b : c);
        uint256 maxVal = a > b ? (a > c ? a : c) : (b > c ? b : c);

        assert(result >= minVal);
        assert(result <= maxVal);
    }

    /// @notice Fuzz test median3 with equal values
    function testFuzz_Median3_EqualValues(uint64 value) public pure {
        uint256 result = PriceBlend.median3(value, value, value);
        assert(result == value);
    }

    /// @notice Fuzz test median3 with two equal values
    function testFuzz_Median3_TwoEqual(uint64 a, uint64 b) public pure {
        // When two values are equal, median is that value
        uint256 result1 = PriceBlend.median3(a, a, b);
        uint256 result2 = PriceBlend.median3(a, b, a);
        uint256 result3 = PriceBlend.median3(b, a, a);

        // All permutations should give same result
        assert(result1 == result2);
        assert(result2 == result3);

        // Result should be between a and b
        if (a <= b) {
            assert(result1 >= a && result1 <= b);
        } else {
            assert(result1 >= b && result1 <= a);
        }
    }

    /// @notice Fuzz test blendMultiSource with valid inputs
    function testFuzz_BlendMultiSource_ValidInputs(
        uint256 seed1,
        uint256 seed2,
        uint256 seed3
    ) public pure {
        // Bound base price
        uint256 price1 = bound(seed1, 1e18, 100000e18);
        // Bound deviations to be within 0.5% to ensure we're safely within 1% total deviation
        uint256 maxDev = (price1 * 50) / 10000; // 0.5%

        uint256 price2 = bound(seed2, price1 > maxDev ? price1 - maxDev : price1, price1 + maxDev);
        uint256 price3 = bound(seed3, price1 > maxDev ? price1 - maxDev : price1, price1 + maxDev);

        uint256[] memory prices = new uint256[](3);
        prices[0] = price1;
        prices[1] = price2;
        prices[2] = price3;

        uint256 result = PriceBlend.blendMultiSource(prices, 100); // 1% max deviation

        // Result should be median
        uint256 expectedMedian = PriceBlend.median3(price1, price2, price3);
        assert(result == expectedMedian);
    }

    /// @notice Fuzz test validateAllWithinBounds
    function testFuzz_ValidateAllWithinBounds(
        uint256 seed1,
        uint256 seed2,
        uint256 seed3
    ) public pure {
        uint256 basePrice = bound(seed1, 1e18, 100000e18);
        // Generate deviations within 2% of each other
        uint256 maxDev = (basePrice * 200) / 10000; // 2%
        uint256 price2 = bound(seed2, basePrice > maxDev ? basePrice - maxDev : basePrice, basePrice + maxDev);
        uint256 price3 = bound(seed3, basePrice > maxDev ? basePrice - maxDev : basePrice, basePrice + maxDev);

        uint256[] memory prices = new uint256[](3);
        prices[0] = basePrice;
        prices[1] = price2;
        prices[2] = price3;

        // Test with 5% max deviation (should always pass for 2% actual deviation)
        bool result = PriceBlend.validateAllWithinBounds(prices, 500);

        // With maxDeviationBP > all deviations, should always be valid
        assert(result == true);
    }

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

    // ============ TokenPrecision Tests ============

    // Mock addresses for testing
    address constant MOCK_WBTC = address(0x1);
    address constant MOCK_USDC = address(0x2);
    address constant MOCK_USDT = address(0x3);
    address constant MOCK_BTD = address(0x4);

    /// @notice Fuzz test: WBTC toNormalized and fromNormalized are inverse operations
    function testFuzz_TokenPrecision_WBTCRoundTrip(uint64 wbtcAmount) public pure {
        // Bound to realistic WBTC amounts (avoid overflow: max 10 billion WBTC in 8 decimals)
        wbtcAmount = uint64(bound(wbtcAmount, 1, 10_000_000_000e8));

        uint256 normalized = TokenPrecision.toNormalized(MOCK_WBTC, wbtcAmount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 recovered = TokenPrecision.fromNormalized(MOCK_WBTC, normalized, MOCK_WBTC, MOCK_USDC, MOCK_USDT);

        // Round trip should preserve value exactly
        assertEq(recovered, wbtcAmount, "WBTC round trip should preserve value");
    }

    /// @notice Fuzz test: USDC toNormalized and fromNormalized are inverse operations
    function testFuzz_TokenPrecision_USDCRoundTrip(uint64 usdcAmount) public pure {
        // Bound to realistic USDC amounts
        usdcAmount = uint64(bound(usdcAmount, 1, 1_000_000_000_000e6)); // Max 1 trillion USDC

        uint256 normalized = TokenPrecision.toNormalized(MOCK_USDC, usdcAmount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 recovered = TokenPrecision.fromNormalized(MOCK_USDC, normalized, MOCK_WBTC, MOCK_USDC, MOCK_USDT);

        assertEq(recovered, usdcAmount, "USDC round trip should preserve value");
    }

    /// @notice Fuzz test: USDT toNormalized and fromNormalized are inverse operations
    function testFuzz_TokenPrecision_USDTRoundTrip(uint64 usdtAmount) public pure {
        usdtAmount = uint64(bound(usdtAmount, 1, 1_000_000_000_000e6));

        uint256 normalized = TokenPrecision.toNormalized(MOCK_USDT, usdtAmount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 recovered = TokenPrecision.fromNormalized(MOCK_USDT, normalized, MOCK_WBTC, MOCK_USDC, MOCK_USDT);

        assertEq(recovered, usdtAmount, "USDT round trip should preserve value");
    }

    /// @notice Fuzz test: 18-decimal tokens pass through unchanged
    function testFuzz_TokenPrecision_18DecimalsPassThrough(uint128 amount) public pure {
        uint256 normalized = TokenPrecision.toNormalized(MOCK_BTD, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        assertEq(normalized, amount, "18-decimal tokens should pass through unchanged");

        uint256 denormalized = TokenPrecision.fromNormalized(MOCK_BTD, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        assertEq(denormalized, amount, "18-decimal tokens should pass through unchanged");
    }

    /// @notice Fuzz test: Normalized amount preserves relative ordering
    function testFuzz_TokenPrecision_PreservesOrdering(uint64 amount1, uint64 amount2) public pure {
        // Test with WBTC
        uint256 norm1 = TokenPrecision.toNormalized(MOCK_WBTC, amount1, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 norm2 = TokenPrecision.toNormalized(MOCK_WBTC, amount2, MOCK_WBTC, MOCK_USDC, MOCK_USDT);

        if (amount1 < amount2) {
            assertTrue(norm1 < norm2, "Ordering should be preserved");
        } else if (amount1 > amount2) {
            assertTrue(norm1 > norm2, "Ordering should be preserved");
        } else {
            assertEq(norm1, norm2, "Equal amounts should give equal normalized");
        }
    }

    /// @notice Fuzz test: Scale factors are consistent
    function testFuzz_TokenPrecision_ScaleFactorConsistency(uint64 amount) public pure {
        // WBTC: scale factor is 1e10
        uint256 wbtcNorm = TokenPrecision.toNormalized(MOCK_WBTC, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 wbtcScale = TokenPrecision.getScaleToNorm(MOCK_WBTC, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        assertEq(wbtcNorm, uint256(amount) * wbtcScale, "WBTC normalization should use scale factor");

        // USDC: scale factor is 1e12
        uint256 usdcNorm = TokenPrecision.toNormalized(MOCK_USDC, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 usdcScale = TokenPrecision.getScaleToNorm(MOCK_USDC, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        assertEq(usdcNorm, uint256(amount) * usdcScale, "USDC normalization should use scale factor");
    }

    /// @notice Fuzz test: Simplified functions match generic functions
    function testFuzz_TokenPrecision_SimplifiedMatchGeneric(uint64 amount) public pure {
        // WBTC
        uint256 genericWbtc = TokenPrecision.toNormalized(MOCK_WBTC, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 simplifiedWbtc = TokenPrecision.wbtcToNormalized(amount);
        assertEq(genericWbtc, simplifiedWbtc, "Simplified WBTC should match generic");

        // USDC
        uint256 genericUsdc = TokenPrecision.toNormalized(MOCK_USDC, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 simplifiedUsdc = TokenPrecision.usdcToNormalized(amount);
        assertEq(genericUsdc, simplifiedUsdc, "Simplified USDC should match generic");

        // USDT
        uint256 genericUsdt = TokenPrecision.toNormalized(MOCK_USDT, amount, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 simplifiedUsdt = TokenPrecision.usdtToNormalized(amount);
        assertEq(genericUsdt, simplifiedUsdt, "Simplified USDT should match generic");
    }

    /// @notice Fuzz test: FromNormalized simplified functions match generic
    function testFuzz_TokenPrecision_FromNormalizedSimplifiedMatch(uint128 normalized) public pure {
        // WBTC
        uint256 genericWbtc = TokenPrecision.fromNormalized(MOCK_WBTC, normalized, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 simplifiedWbtc = TokenPrecision.normalizedToWbtc(normalized);
        assertEq(genericWbtc, simplifiedWbtc, "Simplified fromNormalized WBTC should match");

        // USDC
        uint256 genericUsdc = TokenPrecision.fromNormalized(MOCK_USDC, normalized, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 simplifiedUsdc = TokenPrecision.normalizedToUsdc(normalized);
        assertEq(genericUsdc, simplifiedUsdc, "Simplified fromNormalized USDC should match");

        // USDT
        uint256 genericUsdt = TokenPrecision.fromNormalized(MOCK_USDT, normalized, MOCK_WBTC, MOCK_USDC, MOCK_USDT);
        uint256 simplifiedUsdt = TokenPrecision.normalizedToUsdt(normalized);
        assertEq(genericUsdt, simplifiedUsdt, "Simplified fromNormalized USDT should match");
    }

    /// @notice Fuzz test: Normalization is monotonic (larger input = larger output)
    function testFuzz_TokenPrecision_Monotonic(uint64 a, uint64 b) public pure {
        vm.assume(a <= b);

        uint256 normA = TokenPrecision.wbtcToNormalized(a);
        uint256 normB = TokenPrecision.wbtcToNormalized(b);

        assertTrue(normA <= normB, "Normalization should be monotonic");
    }

    /// @notice Fuzz test: No precision loss for values within range
    function testFuzz_TokenPrecision_NoPrecisionLoss(uint32 wbtcSatoshis) public pure {
        // Even single satoshi should normalize correctly
        uint256 normalized = TokenPrecision.wbtcToNormalized(wbtcSatoshis);
        uint256 recovered = TokenPrecision.normalizedToWbtc(normalized);

        assertEq(recovered, wbtcSatoshis, "No precision loss for any satoshi amount");
    }
}
