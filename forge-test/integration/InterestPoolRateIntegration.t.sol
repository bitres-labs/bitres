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

        assertEq(btdRate, 300, "BTD rate should use new governance rate");
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

    function test_priceImpact_BTD_belowPeg() public view {
        uint256 defaultRate = gov.baseRateDefault();
        uint256 cr = CR_100_PERCENT;

        // Price = 0.95 (5% below peg)
        uint256 lowPrice = 95e16;
        uint256 lowPriceRate = SigmoidRate.calculateBTDRate(lowPrice, cr, defaultRate);

        // Price = 1.0 (at peg)
        uint256 pegRate = SigmoidRate.calculateBTDRate(PRICE_AT_PEG, cr, defaultRate);

        // Rate should be higher when price is below peg
        assertGt(lowPriceRate, pegRate, "Rate should increase when price < 1.0");
    }

    function test_priceImpact_BTD_abovePeg() public view {
        uint256 defaultRate = gov.baseRateDefault();
        uint256 cr = CR_100_PERCENT;

        // Price = 1.05 (5% above peg)
        uint256 highPrice = 105e16;
        uint256 highPriceRate = SigmoidRate.calculateBTDRate(highPrice, cr, defaultRate);

        // Price = 1.0 (at peg)
        uint256 pegRate = SigmoidRate.calculateBTDRate(PRICE_AT_PEG, cr, defaultRate);

        // Rate should be lower when price is above peg
        assertLt(highPriceRate, pegRate, "Rate should decrease when price > 1.0");
    }

    function test_priceImpact_BTB_belowPeg() public view {
        uint256 defaultRate = gov.baseRateDefault();
        uint256 cr = CR_100_PERCENT;

        uint256 lowPrice = 9e17; // 0.9
        uint256 lowPriceRate = SigmoidRate.calculateBTBRate(lowPrice, cr, defaultRate);

        uint256 pegRate = SigmoidRate.calculateBTBRate(PRICE_AT_PEG, cr, defaultRate);

        assertGt(lowPriceRate, pegRate, "BTB rate should increase when price < 1.0");
    }

    // ============ Combined CR and Price Impact Tests ============

    function test_combined_lowCR_lowPrice_BTD() public view {
        uint256 defaultRate = gov.baseRateDefault();
        uint256 cr = CR_60_PERCENT;
        uint256 price = 9e17; // 0.9

        uint256 rate = SigmoidRate.calculateBTDRate(price, cr, defaultRate);

        // Should be significantly higher than normal conditions
        assertGt(rate, 750, "Rate should be higher than base rate with low price");
        assertLe(rate, 1000, "Rate should not exceed max (10%)");
    }

    function test_combined_lowCR_lowPrice_BTB() public view {
        uint256 defaultRate = gov.baseRateDefault();
        uint256 cr = CR_60_PERCENT;
        uint256 price = 8e17; // 0.8

        uint256 rate = SigmoidRate.calculateBTBRate(price, cr, defaultRate);

        // Should be significantly higher than base rate
        assertGt(rate, 1250, "Rate should be higher than base rate with low price");
        assertLe(rate, 2000, "Rate should not exceed max (20%)");
    }

    function test_combined_highCR_highPrice() public view {
        uint256 defaultRate = gov.baseRateDefault();
        uint256 cr = CR_150_PERCENT;
        uint256 price = 11e17; // 1.1

        uint256 btdRate = SigmoidRate.calculateBTDRate(price, cr, defaultRate);
        uint256 btbRate = SigmoidRate.calculateBTBRate(price, cr, defaultRate);

        // Both should be at minimum
        assertEq(btdRate, 200, "BTD should be at minimum");
        assertEq(btbRate, 200, "BTB should be at minimum");
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

    function test_simulation_rateUpdateCycle() public {
        uint256 defaultRate = gov.baseRateDefault();

        // Simulate a market stress scenario
        // Day 1: Normal conditions
        uint256 rate1 = SigmoidRate.calculateBTDRate(PRICE_AT_PEG, CR_100_PERCENT, defaultRate);
        assertEq(rate1, 500, "Day 1: Normal rate");

        // Day 2: Price drops to 0.95, CR drops to 80%
        uint256 rate2 = SigmoidRate.calculateBTDRate(95e16, 8e17, defaultRate);
        assertGt(rate2, rate1, "Day 2: Rate should increase");

        // Day 3: Price stabilizes at 0.98, CR recovers to 90%
        uint256 rate3 = SigmoidRate.calculateBTDRate(98e16, 9e17, defaultRate);
        assertLt(rate3, rate2, "Day 3: Rate should decrease as conditions improve");

        // Day 4: Full recovery
        uint256 rate4 = SigmoidRate.calculateBTDRate(PRICE_AT_PEG, CR_100_PERCENT, defaultRate);
        assertEq(rate4, 500, "Day 4: Back to normal");
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
        defaultRate = uint16(bound(defaultRate, 100, 1000));

        uint256 btdRate = SigmoidRate.calculateBTDRate(PRICE_AT_PEG, cr, defaultRate);
        uint256 btbRate = SigmoidRate.calculateBTBRate(PRICE_AT_PEG, cr, defaultRate);

        assertGe(btbRate, btdRate, "BTB should be >= BTD at low CR");
    }
}
