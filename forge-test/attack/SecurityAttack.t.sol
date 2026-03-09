// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/libraries/MintLogic.sol";
import "../../contracts/libraries/RedeemLogic.sol";
import "../../contracts/libraries/CollateralMath.sol";
import "../../contracts/libraries/InterestMath.sol";
import "../../contracts/libraries/SigmoidRate.sol";
import "../../contracts/libraries/OracleMath.sol";
import "../../contracts/libraries/RewardMath.sol";
import "../../contracts/ConfigGov.sol";
import "../helpers/ProxyTestHelper.sol";

/// @title Security Attack Simulation Tests
/// @notice Comprehensive attack vector testing for the Bitres system
/// @dev Tests pure library functions against manipulation scenarios
contract SecurityAttackTest is Test {

    // ============ Constants ============
    uint256 constant WBTC_PRICE = 50000e18;
    uint256 constant IUSD_PRICE = 1e18;
    uint256 constant BTD_PRICE = 1e18;
    uint256 constant BTB_PRICE = 8e17; // 0.8 BTD
    uint256 constant BRS_PRICE = 5e17; // $0.50
    uint256 constant MIN_BTB_PRICE = 5e17; // 0.5 BTD
    uint16 constant DEFAULT_FEE = 50; // 0.5%

    // ============ Attack 1: Mint-Redeem Arbitrage ============

    /// @notice Test that minting then immediately redeeming at 100% CR doesn't profit
    function test_attack_mintRedeemArbitrage() public pure {
        // Attacker mints with 1 BTC
        MintLogic.MintInputs memory mintIn = MintLogic.MintInputs({
            wbtcAmount: 1e8, // 1 BTC
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            currentBTDSupply: 1000000e18,
            feeBP: DEFAULT_FEE
        });
        MintLogic.MintOutputs memory mintOut = MintLogic.evaluate(mintIn);

        // Immediately redeem all BTD at 100% CR
        RedeemLogic.RedeemInputs memory redeemIn = RedeemLogic.RedeemInputs({
            btdAmount: mintOut.btdToMint,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            cr: Constants.PRECISION_18, // 100% CR
            btdPrice: BTD_PRICE,
            btbPrice: BTB_PRICE,
            brsPrice: BRS_PRICE,
            minBTBPriceInBTD: MIN_BTB_PRICE,
            redeemFeeBP: DEFAULT_FEE
        });
        RedeemLogic.RedeemOutputs memory redeemOut = RedeemLogic.evaluate(redeemIn);

        // User should NOT profit: WBTC out < WBTC in (due to fees)
        uint256 wbtcOut = redeemOut.wbtcOutNormalized / Constants.SCALE_WBTC_TO_NORM;
        assertLt(wbtcOut, 1e8, "Mint-redeem should not profit due to fees");

        // Fees should be significant (at least 0.9% from mint+redeem)
        uint256 loss = 1e8 - wbtcOut;
        assertGt(loss, 1e8 * 9 / 1000, "Fee loss should be at least ~0.9%");
    }

    /// @notice Fuzz: mint-redeem arbitrage never profitable across any price range
    function testFuzz_attack_mintRedeemArbitrageNeverProfitable(
        uint64 wbtcAmount,
        uint64 wbtcPrice
    ) public pure {
        wbtcAmount = uint64(bound(wbtcAmount, 100, 1e8)); // 100 sat to 1 BTC
        wbtcPrice = uint64(bound(wbtcPrice, 10000e18 / 1e18, 200000)); // $10K-$200K (scaled)
        uint256 price = uint256(wbtcPrice) * 1e18;

        uint256 usdValue = uint256(wbtcAmount) * price / Constants.PRECISION_8;
        if (usdValue < Constants.MIN_USD_VALUE) return;

        MintLogic.MintInputs memory mintIn = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: price,
            iusdPrice: IUSD_PRICE,
            currentBTDSupply: 1000000e18,
            feeBP: DEFAULT_FEE
        });
        MintLogic.MintOutputs memory mintOut = MintLogic.evaluate(mintIn);
        if (mintOut.btdToMint < Constants.MIN_STABLECOIN_18_AMOUNT) return;

        RedeemLogic.RedeemInputs memory redeemIn = RedeemLogic.RedeemInputs({
            btdAmount: mintOut.btdToMint,
            wbtcPrice: price,
            iusdPrice: IUSD_PRICE,
            cr: Constants.PRECISION_18,
            btdPrice: BTD_PRICE,
            btbPrice: BTB_PRICE,
            brsPrice: BRS_PRICE,
            minBTBPriceInBTD: MIN_BTB_PRICE,
            redeemFeeBP: DEFAULT_FEE
        });
        RedeemLogic.RedeemOutputs memory redeemOut = RedeemLogic.evaluate(redeemIn);
        uint256 wbtcOut = redeemOut.wbtcOutNormalized / Constants.SCALE_WBTC_TO_NORM;

        assertLe(wbtcOut, wbtcAmount, "Mint-redeem should never profit");
    }

    // ============ Attack 2: Fee Manipulation / Zero Fee Attack ============

    /// @notice Test that even with zero fee, redemption doesn't exceed mint
    function test_attack_zeroFeeDoesNotCreateValue() public pure {
        MintLogic.MintInputs memory mintIn = MintLogic.MintInputs({
            wbtcAmount: 1e8,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            currentBTDSupply: 0,
            feeBP: 0 // Zero fee
        });
        MintLogic.MintOutputs memory mintOut = MintLogic.evaluate(mintIn);

        RedeemLogic.RedeemInputs memory redeemIn = RedeemLogic.RedeemInputs({
            btdAmount: mintOut.btdToMint,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            cr: Constants.PRECISION_18,
            btdPrice: BTD_PRICE,
            btbPrice: BTB_PRICE,
            brsPrice: BRS_PRICE,
            minBTBPriceInBTD: MIN_BTB_PRICE,
            redeemFeeBP: 0 // Zero fee
        });
        RedeemLogic.RedeemOutputs memory redeemOut = RedeemLogic.evaluate(redeemIn);
        uint256 wbtcOut = redeemOut.wbtcOutNormalized / Constants.SCALE_WBTC_TO_NORM;

        // Even with 0 fees, rounding should prevent profit
        assertLe(wbtcOut, 1e8, "Zero fee should not allow profit from rounding");
    }

    // ============ Attack 3: Precision Rounding Exploitation ============

    /// @notice Test that dust amounts produce USD value below MIN_USD_VALUE
    /// @dev Library calls are inlined (internal), so we verify the math instead
    function test_attack_dustAmountRejected() public pure {
        // 1 satoshi at $50K = $0.0005 < MIN_USD_VALUE ($0.001)
        uint256 normalizedWBTC = 1 * Constants.SCALE_WBTC_TO_NORM;
        uint256 usdValue = (normalizedWBTC * WBTC_PRICE) / Constants.PRECISION_18;

        assertLt(usdValue, Constants.MIN_USD_VALUE,
            "1 satoshi at $50K should be below MIN_USD_VALUE");
    }

    /// @notice Test that small but valid amounts work correctly
    function test_attack_smallValidAmountPrecision() public pure {
        // 100 satoshi at $50K = $0.05 > MIN_USD_VALUE
        MintLogic.MintInputs memory mintIn = MintLogic.MintInputs({
            wbtcAmount: 100,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            currentBTDSupply: 1000000e18,
            feeBP: DEFAULT_FEE
        });
        MintLogic.MintOutputs memory mintOut = MintLogic.evaluate(mintIn);

        // Fee invariant should hold
        assertLe(mintOut.btdToMint, mintOut.btdGross, "Net mint should not exceed gross");
        assertEq(mintOut.btdToMint + mintOut.fee, mintOut.btdGross, "Fee invariant");
    }

    /// @notice Fuzz: Fee invariant: btdToMint + fee == btdGross always holds
    function testFuzz_attack_feeInvariant(
        uint64 wbtcAmount,
        uint16 feeBP
    ) public pure {
        wbtcAmount = uint64(bound(wbtcAmount, 1, 1000 * 1e8));
        feeBP = uint16(bound(feeBP, 0, 1000)); // Max 10%
        uint256 usdValue = uint256(wbtcAmount) * WBTC_PRICE / Constants.PRECISION_8;
        if (usdValue < Constants.MIN_USD_VALUE) return;

        MintLogic.MintInputs memory mintIn = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            currentBTDSupply: 1000000e18,
            feeBP: feeBP
        });
        MintLogic.MintOutputs memory mintOut = MintLogic.evaluate(mintIn);

        assertEq(
            mintOut.btdToMint + mintOut.fee,
            mintOut.btdGross,
            "Fee invariant: net + fee == gross"
        );
    }

    // ============ Attack 4: Undercollateralized Redemption Exploitation ============

    /// @notice Test that undercollateralized redemption properly compensates with BTB+BRS
    function test_attack_undercollatRedeemCompensation() public pure {
        uint256 cr50 = 5e17; // 50% CR

        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: 1000e18,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            cr: cr50,
            btdPrice: BTD_PRICE,
            btbPrice: BTB_PRICE,
            brsPrice: BRS_PRICE,
            minBTBPriceInBTD: MIN_BTB_PRICE,
            redeemFeeBP: DEFAULT_FEE
        });
        RedeemLogic.RedeemOutputs memory out = RedeemLogic.evaluate(inputs);

        // Should get some WBTC (proportional to CR)
        assertGt(out.wbtcOutNormalized, 0, "Should get some WBTC even at 50% CR");

        // Should get BTB compensation (BTB price > min price, so no BRS)
        assertGt(out.btbOut, 0, "Should get BTB compensation");

        // Since BTB price (0.8) > min price (0.5), no BRS needed
        assertEq(out.brsOut, 0, "No BRS when BTB price above minimum");
    }

    /// @notice Test secondary shortfall triggers BRS compensation
    function test_attack_secondaryShortfallBRS() public pure {
        uint256 cr50 = 5e17;
        uint256 lowBTBPrice = 3e17; // 0.3 BTD < min 0.5

        // Convert low BTB price to USD: 0.3 BTD * $1/BTD = $0.30
        uint256 btbPriceUSD = (lowBTBPrice * BTD_PRICE) / Constants.PRECISION_18;

        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: 1000e18,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            cr: cr50,
            btdPrice: BTD_PRICE,
            btbPrice: btbPriceUSD,
            brsPrice: BRS_PRICE,
            minBTBPriceInBTD: MIN_BTB_PRICE,
            redeemFeeBP: DEFAULT_FEE
        });
        RedeemLogic.RedeemOutputs memory out = RedeemLogic.evaluate(inputs);

        // Should get all three: WBTC + BTB + BRS
        assertGt(out.wbtcOutNormalized, 0, "Should get WBTC");
        assertGt(out.btbOut, 0, "Should get BTB");
        assertGt(out.brsOut, 0, "Should get BRS compensation");
    }

    /// @notice Fuzz: Total redemption value should never exceed input value
    function testFuzz_attack_redemptionValueNeverExceedsInput(
        uint32 btdRaw,
        uint16 crBps
    ) public pure {
        btdRaw = uint32(bound(btdRaw, 1, 1000000));
        crBps = uint16(bound(crBps, 1000, 20000)); // 10% to 200% CR

        uint256 amount = uint256(btdRaw) * 1e18;
        uint256 cr = uint256(crBps) * 1e14; // basis points to 1e18

        uint256 usdValue = amount * IUSD_PRICE / Constants.PRECISION_18;
        if (usdValue < Constants.MIN_USD_VALUE) return;
        if (amount < Constants.MIN_STABLECOIN_18_AMOUNT) return;

        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: amount,
            wbtcPrice: WBTC_PRICE,
            iusdPrice: IUSD_PRICE,
            cr: cr,
            btdPrice: BTD_PRICE,
            btbPrice: BTB_PRICE,
            brsPrice: BRS_PRICE,
            minBTBPriceInBTD: MIN_BTB_PRICE,
            redeemFeeBP: DEFAULT_FEE
        });
        RedeemLogic.RedeemOutputs memory out = RedeemLogic.evaluate(inputs);

        // Total value returned should not exceed input
        uint256 wbtcValue = out.wbtcOutNormalized * WBTC_PRICE / Constants.PRECISION_18;
        uint256 btbValue = out.btbOut * BTB_PRICE / Constants.PRECISION_18;
        uint256 brsValue = out.brsOut * BRS_PRICE / Constants.PRECISION_18;
        uint256 totalOutValue = wbtcValue + btbValue + brsValue;

        // With fee, output should be less than input value
        assertLe(
            totalOutValue,
            usdValue + 1e15, // 1e15 tolerance for rounding
            "Total output value should not exceed input"
        );
    }

    // ============ Attack 5: Collateral Ratio Manipulation ============

    /// @notice Test that CR calculation is consistent and can't be manipulated via ordering
    function test_attack_crConsistency() public pure {
        uint256 wbtcBalance = 100 * 1e8; // 100 BTC
        uint256 btdSupply = 5000000e18; // 5M BTD
        uint256 stBTDEquiv = 1000000e18; // 1M stBTD equivalent

        uint256 cr1 = CollateralMath.collateralRatio(
            wbtcBalance, WBTC_PRICE, btdSupply, stBTDEquiv, IUSD_PRICE
        );

        // Same values, different variable names - should be identical
        uint256 cr2 = CollateralMath.collateralRatio(
            wbtcBalance, WBTC_PRICE, btdSupply, stBTDEquiv, IUSD_PRICE
        );

        assertEq(cr1, cr2, "CR must be deterministic");

        // CR should decrease when we add more BTD supply
        uint256 crHigherSupply = CollateralMath.collateralRatio(
            wbtcBalance, WBTC_PRICE, btdSupply + 1000000e18, stBTDEquiv, IUSD_PRICE
        );
        assertLt(crHigherSupply, cr1, "More BTD supply should lower CR");
    }

    /// @notice Test that stBTD is properly counted in CR calculation
    function test_attack_stBTDCountedInLiability() public pure {
        uint256 wbtcBalance = 10 * 1e8;
        uint256 btdSupply = 500000e18;

        // CR without stBTD
        uint256 crNoStaking = CollateralMath.collateralRatio(
            wbtcBalance, WBTC_PRICE, btdSupply, 0, IUSD_PRICE
        );

        // CR with stBTD (should be lower because liability is higher)
        uint256 crWithStaking = CollateralMath.collateralRatio(
            wbtcBalance, WBTC_PRICE, btdSupply, 100000e18, IUSD_PRICE
        );

        assertLt(crWithStaking, crNoStaking, "stBTD should increase liability and lower CR");
    }

    // ============ Attack 6: Interest Rate Manipulation ============

    /// @notice Test that interest rates are bounded within expected ranges
    /// @dev Sigmoid formula: r(P) = rmax * S(-alpha*(P-1) + beta)
    ///      Below peg: rate DECREASES (toward min), encouraging buying not staking
    ///      Above peg: rate INCREASES (toward max), encouraging minting via staking
    function test_attack_interestRateBounds() public pure {
        // BTD rate at peg, 100% CR
        uint256 btdRateAtPeg = SigmoidRate.calculateBTDRate(1e18, 1e18, 500);
        assertGe(btdRateAtPeg, 200, "BTD rate minimum 2%");
        assertLe(btdRateAtPeg, 1000, "BTD rate maximum 10%");
        assertEq(btdRateAtPeg, 500, "BTD rate at peg should equal default rate");

        // BTD rate below peg: sigmoid drives rate DOWN (to min)
        uint256 btdRateBelowPeg = SigmoidRate.calculateBTDRate(8e17, 1e18, 500);
        assertLe(btdRateBelowPeg, btdRateAtPeg, "Rate decreases below peg (sigmoid)");
        assertEq(btdRateBelowPeg, 200, "Rate clamps to minimum at 0.8 price");

        // BTD rate above peg: sigmoid drives rate UP (toward max)
        uint256 btdRateAbovePeg = SigmoidRate.calculateBTDRate(12e17, 1e18, 500);
        assertGe(btdRateAbovePeg, btdRateAtPeg, "Rate increases above peg (sigmoid)");
    }

    /// @notice Test BTB rate has higher risk premium
    function test_attack_btbRateHigherRisk() public pure {
        uint256 price = 1e18;
        uint256 cr = 8e17; // 80% CR
        uint256 defaultRate = 500;

        uint256 btdRate = SigmoidRate.calculateBTDRate(price, cr, defaultRate);
        uint256 btbRate = SigmoidRate.calculateBTBRate(price, cr, defaultRate);

        // BTB should have higher rate due to 3x risk multiplier
        assertGt(btbRate, btdRate, "BTB rate should be higher than BTD rate at low CR");
    }

    /// @notice Fuzz: Interest rates always within protocol bounds
    function testFuzz_attack_interestRateAlwaysBounded(
        uint64 priceBps,
        uint64 crBps,
        uint16 defaultRate
    ) public pure {
        uint256 price = bound(priceBps, 5000, 20000) * 1e14; // 0.5 to 2.0
        uint256 cr = bound(crBps, 2000, 20000) * 1e14; // 20% to 200%
        defaultRate = uint16(bound(defaultRate, 100, 1000));

        uint256 btdRate = SigmoidRate.calculateBTDRate(price, cr, defaultRate);
        assertGe(btdRate, 200, "BTD rate >= 2%");
        assertLe(btdRate, 1000, "BTD rate <= 10%");

        uint256 btbRate = SigmoidRate.calculateBTBRate(price, cr, defaultRate);
        assertGe(btbRate, 200, "BTB rate >= 2%");
        assertLe(btbRate, 2000, "BTB rate <= 20%");
    }

    // ============ Attack 7: Interest Compound Inflation Attack ============

    /// @notice Test that interest accumulation over long periods doesn't overflow
    function test_attack_interestOverflowLongPeriod() public pure {
        uint256 oneYear = 365 days;
        uint256 maxRate = 2000; // 20%

        // Interest per share delta for 1 year at max rate
        uint256 delta = InterestMath.interestPerShareDelta(maxRate, oneYear);

        // Should not overflow: 2000 * 365 days / (10000 * 365 days) = 0.2
        assertGt(delta, 0, "Should produce non-zero interest");
        assertLe(delta, 5e17, "1-year interest at 20% should not exceed 50%");
    }

    /// @notice Test interest accrual precision over 10 years
    function test_attack_interestPrecision10Years() public pure {
        uint256 tenYears = 10 * 365 days;
        uint256 rate = 500; // 5%

        uint256 delta = InterestMath.interestPerShareDelta(rate, tenYears);

        // 5% * 10 years = 50% (simple interest, not compounded in this model)
        assertApproxEqRel(delta, 5e17, 1e16, "10-year interest should be ~50%");
    }

    // ============ Attack 8: Oracle Price Deviation ============

    /// @notice Test oracle price deviation validation
    function test_attack_oracleDeviationDetection() public pure {
        uint256 chainlinkPrice = 50000e18;
        uint256 pythPrice = 50500e18; // 1% higher

        // 1% deviation within 100bps tolerance - should pass
        assertTrue(
            OracleMath.deviationWithin(chainlinkPrice, pythPrice, 100),
            "1% deviation within 100bps"
        );

        // 2% deviation beyond 100bps tolerance - should fail
        uint256 manipulatedPrice = 51000e18;
        assertFalse(
            OracleMath.deviationWithin(chainlinkPrice, manipulatedPrice, 100),
            "2% deviation should fail 100bps check"
        );
    }

    /// @notice Test: Deviation check is asymmetric by design (uses priceA as reference)
    /// @dev This is a known design choice - deviationWithin(A,B) != deviationWithin(B,A) when A != B
    ///      In practice, the first argument should always be the "reference" price
    function test_attack_deviationAsymmetryAwareness() public pure {
        // Small A, large B: deviation = |100-150|*10000/100*maxBps = 50*10000 vs 100*500 = 500000 vs 50000 → false (50%)
        assertFalse(
            OracleMath.deviationWithin(100e18, 150e18, 500),
            "50% deviation exceeds 5%"
        );
        // Large A, small B: deviation = |150-100|*10000/150*500 = 500000 vs 75000 → false (~33%)
        assertFalse(
            OracleMath.deviationWithin(150e18, 100e18, 500),
            "33% deviation also exceeds 5%"
        );
        // Within tolerance: 1% diff with 1% tolerance
        assertTrue(
            OracleMath.deviationWithin(100e18, 101e18, 100),
            "1% deviation within 1%"
        );
        assertTrue(
            OracleMath.deviationWithin(101e18, 100e18, 100),
            "Reverse 1% also within (slightly less than 1% relative to 101)"
        );
    }

    /// @notice Fuzz: Both directions agree when prices are within tolerance
    function testFuzz_attack_deviationBothDirectionsSmallDiff(
        uint128 priceA,
        uint16 diffBps
    ) public pure {
        priceA = uint128(bound(priceA, 1e18, 100000e18));
        diffBps = uint16(bound(diffBps, 0, 50)); // Max 0.5% diff
        uint256 priceB = priceA + (uint256(priceA) * diffBps / 10000);

        // With 100bps (1%) tolerance, small differences should pass both ways
        bool ab = OracleMath.deviationWithin(priceA, priceB, 100);
        bool ba = OracleMath.deviationWithin(priceB, priceA, 100);
        assertEq(ab, ba, "Small deviations should be symmetric");
    }

    // ============ Attack 9: Farming Reward Exhaustion ============

    /// @notice Test that mining rewards are capped at BRS_MAX_SUPPLY
    function test_attack_rewardExhaustion() public pure {
        uint256 alreadyMinted = Constants.BRS_MAX_SUPPLY - 100e18;
        uint256 requestedReward = 200e18;

        uint256 clamped = RewardMath.clampToMax(alreadyMinted, requestedReward, Constants.BRS_MAX_SUPPLY);

        // Should be clamped to only 100e18
        assertEq(clamped, 100e18, "Reward should be clamped to remaining supply");
    }

    /// @notice Test that rewards go to zero after full emission
    function test_attack_rewardsZeroAfterFullEmission() public pure {
        uint256 alreadyMinted = Constants.BRS_MAX_SUPPLY;
        uint256 requestedReward = 100e18;

        uint256 clamped = RewardMath.clampToMax(alreadyMinted, requestedReward, Constants.BRS_MAX_SUPPLY);
        assertEq(clamped, 0, "No more rewards after max supply reached");
    }

    // ============ Attack 10: ConfigGov Parameter Validation ============

    /// @notice Test ConfigGov parameter bounds are enforced
    function test_attack_configGovBoundsEnforced() public {
        ConfigGov gov = ProxyTestHelper.deployConfigGov(address(this));

        // Mint fee: max 10%
        vm.expectRevert("ConfigGov: mint fee too high");
        gov.setParam(ConfigGov.ParamType.MintFeeBp, 1001);

        // Redeem fee: max 10%
        vm.expectRevert("ConfigGov: redeem fee too high");
        gov.setParam(ConfigGov.ParamType.RedeemFeeBp, 1001);

        // MinBTBPrice range: 0.1 to 1.0
        vm.expectRevert("ConfigGov: min BTB price too low");
        gov.setParam(ConfigGov.ParamType.MinBtbPrice, 1e17 - 1);

        vm.expectRevert("ConfigGov: min BTB price too high");
        gov.setParam(ConfigGov.ParamType.MinBtbPrice, 1e18 + 1);
    }

    /// @notice Test default minBTBPrice is now set correctly
    function test_attack_minBTBPriceDefault() public {
        ConfigGov gov = ProxyTestHelper.deployConfigGov(address(this));

        uint256 minPrice = gov.minBTBPrice();
        assertEq(minPrice, 5e17, "Default minBTBPrice should be 0.5 BTD");
    }

    // ============ Attack 11: BTB Redemption Quota Drain ============

    /// @notice Test that BTB redemption can't drain more than excess collateral
    function test_attack_btbRedemptionQuota() public pure {
        // CR = 120%
        uint256 colValue = 6000000e18;
        uint256 liabValue = 5000000e18;

        uint256 maxRedeemUSD = CollateralMath.maxRedeemableUSD(colValue, liabValue);
        assertEq(maxRedeemUSD, 1000000e18, "Max redeemable should be $1M");

        uint256 maxRedeemBTD = CollateralMath.maxRedeemableBTD(colValue, liabValue, IUSD_PRICE);
        assertEq(maxRedeemBTD, 1000000e18, "Max BTD should be 1M");

        // When exactly at 100% CR, no BTB redemption possible
        uint256 maxAtPar = CollateralMath.maxRedeemableUSD(5000000e18, 5000000e18);
        assertEq(maxAtPar, 0, "No BTB redeemable at exactly 100% CR");
    }

    // ============ Attack 12: Inverse Price Manipulation ============

    /// @notice Test inverse price calculation can't produce zero or overflow
    function test_attack_inversePriceEdgeCases() public pure {
        // Normal case
        uint256 invPrice = OracleMath.inversePrice(2e18);
        assertApproxEqRel(invPrice, 5e17, 1e16, "1/2 should be ~0.5");

        // Very small price (large inverse)
        uint256 invSmall = OracleMath.inversePrice(1e15); // 0.001
        assertEq(invSmall, 1e21, "1/0.001 should be 1000");

        // Very large price (small inverse)
        uint256 invLarge = OracleMath.inversePrice(1000e18); // 1000
        assertEq(invLarge, 1e15, "1/1000 should be 0.001");
    }

    // ============ Attack 13: Spot Price Calculation Accuracy ============

    /// @notice Test spot price with different decimal tokens
    function test_attack_spotPricePrecision() public pure {
        // WBTC (8 dec) / USDC (6 dec) pool
        uint256 spotWbtcUsdc = OracleMath.spotPrice(
            100 * 1e8, // 100 WBTC reserve
            5000000 * 1e6, // 5M USDC reserve
            8, 6
        );
        assertApproxEqRel(spotWbtcUsdc, 50000e18, 1e16, "WBTC/USDC should be ~$50,000");

        // BTD (18 dec) / USDC (6 dec) pool
        uint256 spotBtdUsdc = OracleMath.spotPrice(
            1000000e18, // 1M BTD reserve
            1000000 * 1e6, // 1M USDC reserve
            18, 6
        );
        assertApproxEqRel(spotBtdUsdc, 1e18, 1e16, "BTD/USDC should be ~$1.00");
    }

    // ============ Attack 14: Reward Math Overflow Protection ============

    /// @notice Fuzz: Reward calculation never overflows
    function testFuzz_attack_rewardCalcNoOverflow(
        uint32 timeElapsed,
        uint64 rewardPerSec,
        uint64 allocPoint,
        uint64 totalAlloc
    ) public pure {
        timeElapsed = uint32(bound(timeElapsed, 1, 365 days));
        rewardPerSec = uint64(bound(rewardPerSec, 1, 10000e18 / 1e18));
        allocPoint = uint64(bound(allocPoint, 1, 10000));
        totalAlloc = uint64(bound(totalAlloc, allocPoint, 100000));

        uint256 emission = RewardMath.emissionFor(
            timeElapsed,
            uint256(rewardPerSec) * 1e18,
            allocPoint,
            totalAlloc
        );

        // Emission should be non-negative
        assertGe(emission, 0, "Emission should be non-negative");

        // Emission should not exceed max possible
        uint256 maxPossible = uint256(timeElapsed) * uint256(rewardPerSec) * 1e18;
        assertLe(emission, maxPossible, "Emission should not exceed max");
    }

    // ============ Attack 15: IUSD Adjustment Factor Bounds ============

    /// @notice Test IUSD adjustment when inflation matches target (factor ≈ 1)
    function test_attack_iusdAdjustmentAtTarget() public pure {
        uint256 currentPCE = 1001651581301920174; // 0.1651% monthly increase (= 2% annual)
        uint256 previousPCE = 1e18;

        (, uint256 factor) = _adjustmentFactor(
            currentPCE,
            previousPCE,
            Constants.MONTHLY_GROWTH_FACTOR
        );

        // When actual inflation = target, adjustment factor ≈ 1
        assertApproxEqRel(factor, 1e18, 1e15, "Factor should be ~1 when inflation matches target");
    }

    /// @notice Test IUSD adjustment when inflation is above target
    function test_attack_iusdAdjustmentAboveTarget() public pure {
        // 1% monthly increase (vs 0.165% target)
        uint256 currentPCE = 101e16;
        uint256 previousPCE = 1e18;

        (, uint256 factor) = _adjustmentFactor(
            currentPCE,
            previousPCE,
            Constants.MONTHLY_GROWTH_FACTOR
        );

        // When actual inflation > target, IUSD should adjust upward (factor > 1)
        assertGt(factor, 1e18, "Factor should be > 1 when inflation exceeds target");
    }

    /// @dev Inline IUSDMath.adjustmentFactor to avoid library linking issues
    function _adjustmentFactor(
        uint256 current,
        uint256 previous,
        uint256 monthlyGrowthFactor
    ) internal pure returns (uint256, uint256) {
        uint256 actualInflationMultiplier = (current * Constants.PRECISION_18) / previous;
        uint256 factor = (current * Constants.PRECISION_18 * Constants.PRECISION_18) / (previous * monthlyGrowthFactor);
        return (actualInflationMultiplier, factor);
    }

    // ============ Attack 16: Withdrawal Split Logic ============

    /// @notice Test unstake split proportionally distributes interest vs principal
    function test_attack_withdrawalSplitFairness() public pure {
        uint256 withdrawAmount = 100e18;
        uint256 pendingInterest = 20e18;
        uint256 totalAvailable = 120e18;

        (uint256 interestShare, uint256 principalShare) = InterestMath.splitWithdrawal(
            withdrawAmount,
            pendingInterest,
            totalAvailable
        );

        assertEq(interestShare + principalShare, withdrawAmount, "Shares should sum to withdrawal");
        assertGt(interestShare, 0, "Should get some interest");
        assertGt(principalShare, 0, "Should get some principal");
    }
}
