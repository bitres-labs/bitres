// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/SigmoidRate.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/ConfigGov.sol";

/// @title InterestPool Rate Integration Tests
/// @notice Tests the integration of SigmoidRate calculations with ConfigGov parameters
/// @dev Tests the new CR-based rate calculation without CDY dependency
contract InterestPoolRateIntegrationTest is Test {

    ConfigGov public gov;

    // Test constants
    uint256 constant DEFAULT_BASE_RATE_BPS = 500;  // 5%
    uint256 constant CR_100_PERCENT = 1e18;
    uint256 constant CR_150_PERCENT = 15e17;
    uint256 constant CR_60_PERCENT = 6e17;
    uint256 constant CR_20_PERCENT = 2e17;
    uint256 constant PRICE_AT_PEG = 1e18;

    function setUp() public {
        gov = new ConfigGov(address(this));
    }

    // ============ Base Rate from Governance Tests ============

    function test_rateCalculation_usesGovernanceDefaultRate() public view {
        uint256 defaultRate = gov.baseRateDefault();
        assertEq(defaultRate, DEFAULT_BASE_RATE_BPS, "Gov should return 500 bps");

        // Calculate BTD rate at peg using governance rate
        uint256 btdRate = SigmoidRate.calculateBTDRate(
            PRICE_AT_PEG,
            CR_100_PERCENT,
            defaultRate
        );

        assertEq(btdRate, defaultRate, "BTD rate at peg should equal governance rate");
    }

    function test_rateCalculation_respondsToGovernanceChange() public {
        // Change governance default rate
        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, 300); // 3%

        uint256 newDefault = gov.baseRateDefault();
        assertEq(newDefault, 300, "Gov should return new rate");

        // Calculate rate with new default
        uint256 btdRate = SigmoidRate.calculateBTDRate(
            PRICE_AT_PEG,
            CR_100_PERCENT,
            newDefault
        );

        // Allow tolerance for numerical precision
        assertApproxEqAbs(btdRate, 300, 5, "BTD rate should use new governance rate");
    }

    // ============ Full Rate Calculation Flow Tests ============

    function test_fullFlow_BTD_normalConditions() public view {
        // Normal conditions: price = 1.0, CR = 100%
        uint256 defaultRate = gov.baseRateDefault();
        uint256 price = PRICE_AT_PEG;
        uint256 cr = CR_100_PERCENT;

        uint256 rate = SigmoidRate.calculateBTDRate(price, cr, defaultRate);

        // At normal conditions, rate should be close to 5% (allow numerical precision tolerance)
        assertApproxEqAbs(rate, 500, 10, "BTD rate should be ~5% at normal conditions");
    }

    function test_fullFlow_BTD_lowCR() public view {
        // Low CR: price = 1.0, CR = 60%
        uint256 defaultRate = gov.baseRateDefault();
        uint256 price = PRICE_AT_PEG;
        uint256 cr = CR_60_PERCENT;

        uint256 rate = SigmoidRate.calculateBTDRate(price, cr, defaultRate);

        // At CR = 60%, base rate = 7.5%, at peg rate = base rate (with tolerance)
        assertApproxEqAbs(rate, 750, 10, "BTD rate should be ~7.5% at CR=60%");
    }

    function test_fullFlow_BTD_highCR() public view {
        // High CR: price = 1.0, CR = 150%
        uint256 defaultRate = gov.baseRateDefault();
        uint256 price = PRICE_AT_PEG;
        uint256 cr = CR_150_PERCENT;

        uint256 rate = SigmoidRate.calculateBTDRate(price, cr, defaultRate);

        // At CR >= 150%, rate should be minimum (2%)
        assertEq(rate, 200, "BTD rate should be 2% at CR>=150%");
    }

    function test_fullFlow_BTB_normalConditions() public view {
        uint256 defaultRate = gov.baseRateDefault();
        uint256 price = PRICE_AT_PEG;
        uint256 cr = CR_100_PERCENT;

        uint256 rate = SigmoidRate.calculateBTBRate(price, cr, defaultRate);

        // Allow tolerance for numerical precision
        assertApproxEqAbs(rate, 500, 30, "BTB rate should be ~5% at normal conditions");
    }

    function test_fullFlow_BTB_lowCR() public view {
        uint256 defaultRate = gov.baseRateDefault();
        uint256 price = PRICE_AT_PEG;
        uint256 cr = CR_60_PERCENT;

        uint256 rate = SigmoidRate.calculateBTBRate(price, cr, defaultRate);

        // At CR = 60%, BTB base rate = 12.5% (3x multiplier), with tolerance
        assertApproxEqAbs(rate, 1250, 20, "BTB rate should be ~12.5% at CR=60%");
    }

    function test_fullFlow_BTB_extremeLowCR() public view {
        uint256 defaultRate = gov.baseRateDefault();
        uint256 price = PRICE_AT_PEG;
        uint256 cr = CR_20_PERCENT;

        uint256 rate = SigmoidRate.calculateBTBRate(price, cr, defaultRate);

        // At CR = 20%, BTB base rate = 20% (max)
        assertEq(rate, 2000, "BTB rate should be 20% at CR=20%");
    }

    // ============ Price Impact Tests ============

    function test_priceImpact_BTD_priceChange() public view {
        // Test that price changes affect rate
        uint256 defaultRate = gov.baseRateDefault();
        uint256 cr = CR_100_PERCENT;

        uint256 lowPriceRate = SigmoidRate.calculateBTDRate(95e16, cr, defaultRate);
        uint256 pegRate = SigmoidRate.calculateBTDRate(PRICE_AT_PEG, cr, defaultRate);
        uint256 highPriceRate = SigmoidRate.calculateBTDRate(105e16, cr, defaultRate);

        // Price change should affect rate (direction depends on implementation)
        assertTrue(
            lowPriceRate != pegRate || highPriceRate != pegRate,
            "Price should affect rate"
        );
        // All rates should be within valid range
        assertGe(lowPriceRate, 200, "Low price rate >= min");
        assertGe(highPriceRate, 200, "High price rate >= min");
        assertLe(lowPriceRate, 1000, "Low price rate <= max");
        assertLe(highPriceRate, 1000, "High price rate <= max");
    }

    function test_priceImpact_BTB_priceChange() public view {
        uint256 defaultRate = gov.baseRateDefault();
        uint256 cr = CR_100_PERCENT;

        uint256 lowPriceRate = SigmoidRate.calculateBTBRate(9e17, cr, defaultRate);
        uint256 pegRate = SigmoidRate.calculateBTBRate(PRICE_AT_PEG, cr, defaultRate);
        uint256 highPriceRate = SigmoidRate.calculateBTBRate(11e17, cr, defaultRate);

        // All rates should be within valid range
        assertGe(lowPriceRate, 200, "Low price rate >= min");
        assertGe(highPriceRate, 200, "High price rate >= min");
        assertLe(lowPriceRate, 2000, "Low price rate <= max");
        assertLe(highPriceRate, 2000, "High price rate <= max");
    }

    // ============ Combined CR and Price Impact Tests ============

    function test_combined_lowCR_lowPrice_BTD() public view {
        uint256 defaultRate = gov.baseRateDefault();
        uint256 cr = CR_60_PERCENT;
        uint256 price = 9e17; // 0.9

        uint256 rate = SigmoidRate.calculateBTDRate(price, cr, defaultRate);

        // Should be within valid range
        assertGe(rate, 200, "Rate should be >= min");
        assertLe(rate, 1000, "Rate should not exceed max (10%)");
    }

    function test_combined_lowCR_lowPrice_BTB() public view {
        uint256 defaultRate = gov.baseRateDefault();
        uint256 cr = CR_60_PERCENT;
        uint256 price = 8e17; // 0.8

        uint256 rate = SigmoidRate.calculateBTBRate(price, cr, defaultRate);

        // Should be within valid range
        assertGe(rate, 200, "Rate should be >= min");
        assertLe(rate, 2000, "Rate should not exceed max (20%)");
    }

    function test_combined_highCR_highPrice() public view {
        uint256 defaultRate = gov.baseRateDefault();
        uint256 cr = CR_150_PERCENT;
        uint256 price = 11e17; // 1.1

        uint256 btdRate = SigmoidRate.calculateBTDRate(price, cr, defaultRate);
        uint256 btbRate = SigmoidRate.calculateBTBRate(price, cr, defaultRate);

        // Both should be within range (may not be at minimum due to Sigmoid)
        assertGe(btdRate, 200, "BTD should be >= min");
        assertLe(btdRate, 1000, "BTD should be <= max");
        assertGe(btbRate, 200, "BTB should be >= min");
        assertLe(btbRate, 2000, "BTB should be <= max");
    }

    // ============ Risk Compensation Tests ============

    function test_BTB_alwaysHigherThanBTD_lowCR() public view {
        uint256 defaultRate = gov.baseRateDefault();
        uint256 price = PRICE_AT_PEG;

        // Test at various low CR levels
        uint256[] memory crLevels = new uint256[](4);
        crLevels[0] = 8e17;  // 80%
        crLevels[1] = 6e17;  // 60%
        crLevels[2] = 4e17;  // 40%
        crLevels[3] = 2e17;  // 20%

        for (uint256 i = 0; i < crLevels.length; i++) {
            uint256 btdRate = SigmoidRate.calculateBTDRate(price, crLevels[i], defaultRate);
            uint256 btbRate = SigmoidRate.calculateBTBRate(price, crLevels[i], defaultRate);

            assertGe(btbRate, btdRate, "BTB should always be >= BTD at low CR");
        }
    }

    // ============ Governance Parameter Sensitivity Tests ============

    function test_governanceSensitivity_lowDefault() public {
        // Set low default rate (1%)
        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, 100);
        uint256 defaultRate = gov.baseRateDefault();

        uint256 btdRate = SigmoidRate.calculateBTDRate(PRICE_AT_PEG, CR_100_PERCENT, defaultRate);

        // Rate should be clamped to min (2%) even though default is 1%
        // Actually at CR=100%, rate = default, but clamped to min
        assertEq(btdRate, 200, "Rate should be clamped to minimum 2%");
    }

    function test_governanceSensitivity_highDefault() public {
        // Set high default rate (10%)
        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, 1000);
        uint256 defaultRate = gov.baseRateDefault();

        uint256 btdRate = SigmoidRate.calculateBTDRate(PRICE_AT_PEG, CR_100_PERCENT, defaultRate);

        // BTD max is 10%, so at peg it should be clamped
        assertEq(btdRate, 1000, "BTD rate should be at max (10%)");
    }

    // ============ Simulation Tests ============

    function test_simulation_rateUpdateCycle() public view {
        uint256 defaultRate = gov.baseRateDefault();

        // Simulate different market conditions and verify rates are always valid
        uint256 rate1 = SigmoidRate.calculateBTDRate(PRICE_AT_PEG, CR_100_PERCENT, defaultRate);
        uint256 rate2 = SigmoidRate.calculateBTDRate(95e16, 8e17, defaultRate);
        uint256 rate3 = SigmoidRate.calculateBTDRate(98e16, 9e17, defaultRate);
        uint256 rate4 = SigmoidRate.calculateBTDRate(PRICE_AT_PEG, CR_100_PERCENT, defaultRate);

        // All rates should be within valid range
        assertGe(rate1, 200, "Rate 1 >= min");
        assertLe(rate1, 1000, "Rate 1 <= max");
        assertGe(rate2, 200, "Rate 2 >= min");
        assertLe(rate2, 1000, "Rate 2 <= max");
        assertGe(rate3, 200, "Rate 3 >= min");
        assertLe(rate3, 1000, "Rate 3 <= max");
        assertGe(rate4, 200, "Rate 4 >= min");
        assertLe(rate4, 1000, "Rate 4 <= max");

        // Same conditions should give same rate
        assertEq(rate1, rate4, "Same conditions should give same rate");
    }

    function test_simulation_btbRiskCompensation() public view {
        uint256 defaultRate = gov.baseRateDefault();

        // CR drops from 100% to 60%
        // BTD goes from 5% to 7.5% (1.5x)
        // BTB goes from 5% to 12.5% (2.5x)

        uint256 btdNormal = SigmoidRate.getBTDBaseRate(CR_100_PERCENT, defaultRate);
        uint256 btdCrisis = SigmoidRate.getBTDBaseRate(CR_60_PERCENT, defaultRate);
        uint256 btdIncrease = (btdCrisis - btdNormal) * 100 / btdNormal;

        uint256 btbNormal = SigmoidRate.getBTBBaseRate(CR_100_PERCENT, defaultRate);
        uint256 btbCrisis = SigmoidRate.getBTBBaseRate(CR_60_PERCENT, defaultRate);
        uint256 btbIncrease = (btbCrisis - btbNormal) * 100 / btbNormal;

        // BTB increase should be significantly higher than BTD
        assertGt(btbIncrease, btdIncrease, "BTB should have higher risk compensation");
        assertEq(btdIncrease, 50, "BTD increase should be 50%");  // 7.5/5 - 1 = 50%
        assertEq(btbIncrease, 150, "BTB increase should be 150%"); // 12.5/5 - 1 = 150%
    }

    // ============ Fuzz Tests ============

    function testFuzz_fullFlow_BTD(uint64 price, uint64 cr, uint16 defaultRate) public pure {
        price = uint64(bound(price, 5e17, 15e17));   // 0.5 to 1.5
        cr = uint64(bound(cr, 1e17, 2e18));          // 10% to 200%
        defaultRate = uint16(bound(defaultRate, 100, 1000)); // 1% to 10%

        uint256 rate = SigmoidRate.calculateBTDRate(price, cr, defaultRate);

        assertGe(rate, 200, "Rate should be >= min (2%)");
        assertLe(rate, 1000, "Rate should be <= max (10%)");
    }

    function testFuzz_fullFlow_BTB(uint64 price, uint64 cr, uint16 defaultRate) public pure {
        price = uint64(bound(price, 3e17, 17e17));   // 0.3 to 1.7
        cr = uint64(bound(cr, 1e17, 2e18));          // 10% to 200%
        defaultRate = uint16(bound(defaultRate, 100, 1000)); // 1% to 10%

        uint256 rate = SigmoidRate.calculateBTBRate(price, cr, defaultRate);

        assertGe(rate, 200, "Rate should be >= min (2%)");
        assertLe(rate, 2000, "Rate should be <= max (20%)");
    }

    function testFuzz_btbHigherThanBtdAtLowCR(uint64 cr, uint16 defaultRate) public pure {
        cr = uint64(bound(cr, 2e17, CR_100_PERCENT - 1)); // 20% to 99.99%
        defaultRate = uint16(bound(defaultRate, 200, 800)); // Use moderate default rates

        // Get base rates (without Sigmoid) to verify the 3x multiplier
        uint256 btdBaseRate = SigmoidRate.getBTDBaseRate(cr, defaultRate);
        uint256 btbBaseRate = SigmoidRate.getBTBBaseRate(cr, defaultRate);

        // BTB base rate should always be >= BTD base rate at low CR
        assertGe(btbBaseRate, btdBaseRate, "BTB base should be >= BTD base at low CR");
    }
}
