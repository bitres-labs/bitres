// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/SigmoidRate.sol";
import "../../contracts/libraries/Constants.sol";

/// @title SigmoidRate Unit Tests
/// @notice Tests for the CR-based base rate calculation logic
contract SigmoidRateUnitTest is Test {
    using SigmoidRate for *;

    // Constants from SigmoidRate
    uint256 constant BTD_R_MAX_BPS = 1000;  // 10%
    uint256 constant BTB_R_MAX_BPS = 2000;  // 20%
    uint256 constant R_MIN_BPS = 200;       // 2%
    uint256 constant R_DEFAULT_BPS = 500;   // 5%
    uint256 constant CR_THRESHOLD = 1e18;   // 100%
    uint256 constant CR_UPPER = 15e17;      // 150%
    uint256 constant CR_MIN = 2e17;         // 20%
    uint256 constant PRECISION = 1e18;

    // ============ BTD Base Rate Tests ============

    function test_BTDBaseRate_atCR100() public pure {
        // At CR = 100%, base rate should be default (5%)
        uint256 cr = 1e18; // 100%
        uint256 rate = SigmoidRate.getBTDBaseRate(cr, R_DEFAULT_BPS);
        assertEq(rate, R_DEFAULT_BPS, "BTD base rate at CR=100% should be 5%");
    }

    function test_BTDBaseRate_atCR150() public pure {
        // At CR >= 150%, base rate should be minimum (2%)
        uint256 cr = 15e17; // 150%
        uint256 rate = SigmoidRate.getBTDBaseRate(cr, R_DEFAULT_BPS);
        assertEq(rate, R_MIN_BPS, "BTD base rate at CR=150% should be 2%");
    }

    function test_BTDBaseRate_atCR200() public pure {
        // At CR = 200% (above upper), base rate should still be minimum (2%)
        uint256 cr = 2e18; // 200%
        uint256 rate = SigmoidRate.getBTDBaseRate(cr, R_DEFAULT_BPS);
        assertEq(rate, R_MIN_BPS, "BTD base rate at CR=200% should be 2%");
    }

    function test_BTDBaseRate_atCR20() public pure {
        // At CR = 20%, deltaCR = (1-0.2)/0.8 = 1.0, rate = 5% * 2 = 10%
        uint256 cr = 2e17; // 20%
        uint256 rate = SigmoidRate.getBTDBaseRate(cr, R_DEFAULT_BPS);
        assertEq(rate, BTD_R_MAX_BPS, "BTD base rate at CR=20% should be 10%");
    }

    function test_BTDBaseRate_atCR60() public pure {
        // At CR = 60%, deltaCR = (1-0.6)/0.8 = 0.5, rate = 5% * 1.5 = 7.5%
        uint256 cr = 6e17; // 60%
        uint256 rate = SigmoidRate.getBTDBaseRate(cr, R_DEFAULT_BPS);
        assertEq(rate, 750, "BTD base rate at CR=60% should be 7.5% (750 bps)");
    }

    function test_BTDBaseRate_atCR125() public pure {
        // At CR = 125%, deltaCR = -0.6 * 0.25/0.5 = -0.3, rate = 5% * 0.7 = 3.5%
        uint256 cr = 125e16; // 125%
        uint256 rate = SigmoidRate.getBTDBaseRate(cr, R_DEFAULT_BPS);
        assertEq(rate, 350, "BTD base rate at CR=125% should be 3.5% (350 bps)");
    }

    function test_BTDBaseRate_belowCR20() public pure {
        // At CR < 20%, rate should be capped at max (10%)
        uint256 cr = 1e17; // 10%
        uint256 rate = SigmoidRate.getBTDBaseRate(cr, R_DEFAULT_BPS);
        assertEq(rate, BTD_R_MAX_BPS, "BTD base rate at CR=10% should be max 10%");
    }

    // ============ BTB Base Rate Tests ============

    function test_BTBBaseRate_atCR100() public pure {
        // At CR = 100%, base rate should be default (5%)
        uint256 cr = 1e18; // 100%
        uint256 rate = SigmoidRate.getBTBBaseRate(cr, R_DEFAULT_BPS);
        assertEq(rate, R_DEFAULT_BPS, "BTB base rate at CR=100% should be 5%");
    }

    function test_BTBBaseRate_atCR150() public pure {
        // At CR >= 150%, base rate should be minimum (2%)
        uint256 cr = 15e17; // 150%
        uint256 rate = SigmoidRate.getBTBBaseRate(cr, R_DEFAULT_BPS);
        assertEq(rate, R_MIN_BPS, "BTB base rate at CR=150% should be 2%");
    }

    function test_BTBBaseRate_atCR20() public pure {
        // At CR = 20%, deltaCR = 3 * (1-0.2)/0.8 = 3.0, rate = 5% * 4 = 20%
        uint256 cr = 2e17; // 20%
        uint256 rate = SigmoidRate.getBTBBaseRate(cr, R_DEFAULT_BPS);
        assertEq(rate, BTB_R_MAX_BPS, "BTB base rate at CR=20% should be 20%");
    }

    function test_BTBBaseRate_atCR60() public pure {
        // At CR = 60%, deltaCR = 3 * (1-0.6)/0.8 = 1.5, rate = 5% * 2.5 = 12.5%
        uint256 cr = 6e17; // 60%
        uint256 rate = SigmoidRate.getBTBBaseRate(cr, R_DEFAULT_BPS);
        assertEq(rate, 1250, "BTB base rate at CR=60% should be 12.5% (1250 bps)");
    }

    function test_BTBBaseRate_atCR80() public pure {
        // At CR = 80%, deltaCR = 3 * (1-0.8)/0.8 = 0.75, rate = 5% * 1.75 = 8.75%
        uint256 cr = 8e17; // 80%
        uint256 rate = SigmoidRate.getBTBBaseRate(cr, R_DEFAULT_BPS);
        assertEq(rate, 875, "BTB base rate at CR=80% should be 8.75% (875 bps)");
    }

    function test_BTBBaseRate_belowCR20() public pure {
        // At CR < 20%, rate should be capped at max (20%)
        uint256 cr = 1e17; // 10%
        uint256 rate = SigmoidRate.getBTBBaseRate(cr, R_DEFAULT_BPS);
        assertEq(rate, BTB_R_MAX_BPS, "BTB base rate at CR=10% should be max 20%");
    }

    // ============ BTD vs BTB Comparison Tests ============

    function test_BTB_higherThanBTD_whenCRLow() public pure {
        // BTB should always have higher rate than BTD when CR < 100%
        uint256 cr = 6e17; // 60%
        uint256 btdRate = SigmoidRate.getBTDBaseRate(cr, R_DEFAULT_BPS);
        uint256 btbRate = SigmoidRate.getBTBBaseRate(cr, R_DEFAULT_BPS);
        assertGt(btbRate, btdRate, "BTB rate should be higher than BTD at low CR");
    }

    function test_BTB_equalToBTD_whenCR100() public pure {
        // At CR = 100%, both should be default
        uint256 cr = 1e18;
        uint256 btdRate = SigmoidRate.getBTDBaseRate(cr, R_DEFAULT_BPS);
        uint256 btbRate = SigmoidRate.getBTBBaseRate(cr, R_DEFAULT_BPS);
        assertEq(btdRate, btbRate, "BTD and BTB should be equal at CR=100%");
    }

    function test_BTB_equalToBTD_whenCRHigh() public pure {
        // At CR >= 150%, both should be minimum (2%)
        uint256 cr = 15e17;
        uint256 btdRate = SigmoidRate.getBTDBaseRate(cr, R_DEFAULT_BPS);
        uint256 btbRate = SigmoidRate.getBTBBaseRate(cr, R_DEFAULT_BPS);
        assertEq(btdRate, btbRate, "BTD and BTB should be equal at CR>=150%");
        assertEq(btdRate, R_MIN_BPS, "Both should be at minimum 2%");
    }

    // ============ Full Rate Calculation Tests (with Sigmoid) ============

    function test_calculateBTDRate_atPeg() public pure {
        // At price = 1.0 and CR = 100%, rate should be close to base rate (5%)
        uint256 price = 1e18; // 1.0
        uint256 cr = 1e18;    // 100%
        uint256 rate = SigmoidRate.calculateBTDRate(price, cr, R_DEFAULT_BPS);
        // Due to numerical precision in Sigmoid, allow small tolerance
        assertApproxEqAbs(rate, R_DEFAULT_BPS, 10, "BTD rate at peg should be ~5%");
    }

    function test_calculateBTDRate_priceMonotonicity() public pure {
        // Rate should change monotonically with price
        uint256 cr = 1e18;
        uint256 rate90 = SigmoidRate.calculateBTDRate(90e16, cr, R_DEFAULT_BPS);
        uint256 rate95 = SigmoidRate.calculateBTDRate(95e16, cr, R_DEFAULT_BPS);
        uint256 rate100 = SigmoidRate.calculateBTDRate(100e16, cr, R_DEFAULT_BPS);
        uint256 rate105 = SigmoidRate.calculateBTDRate(105e16, cr, R_DEFAULT_BPS);
        uint256 rate110 = SigmoidRate.calculateBTDRate(110e16, cr, R_DEFAULT_BPS);

        // Verify monotonicity in some direction (implementation may invert)
        bool increasing = rate90 < rate110;
        if (increasing) {
            assertLe(rate90, rate95, "Rate should be monotonic");
            assertLe(rate100, rate105, "Rate should be monotonic");
        } else {
            assertGe(rate90, rate95, "Rate should be monotonic");
            assertGe(rate100, rate105, "Rate should be monotonic");
        }
    }

    function test_calculateBTDRate_boundedRange() public pure {
        // Rate should always be within [2%, 10%]
        uint256 cr = 1e18;
        uint256[] memory prices = new uint256[](5);
        prices[0] = 5e17;  // 0.5
        prices[1] = 8e17;  // 0.8
        prices[2] = 1e18;  // 1.0
        prices[3] = 12e17; // 1.2
        prices[4] = 15e17; // 1.5

        for (uint i = 0; i < prices.length; i++) {
            uint256 rate = SigmoidRate.calculateBTDRate(prices[i], cr, R_DEFAULT_BPS);
            assertGe(rate, R_MIN_BPS, "Rate should be >= min");
            assertLe(rate, BTD_R_MAX_BPS, "Rate should be <= max");
        }
    }

    function test_calculateBTBRate_atPeg() public pure {
        // At price = 1.0 and CR = 100%, rate should be close to base rate (5%)
        uint256 price = 1e18;
        uint256 cr = 1e18;
        uint256 rate = SigmoidRate.calculateBTBRate(price, cr, R_DEFAULT_BPS);
        // Allow tolerance for numerical precision
        assertApproxEqAbs(rate, R_DEFAULT_BPS, 30, "BTB rate at peg should be ~5%");
    }

    function test_calculateBTBRate_lowCR() public pure {
        // At price = 1.0 but CR = 60%, base rate is 12.5%
        uint256 price = 1e18;
        uint256 cr = 6e17; // 60%
        uint256 rate = SigmoidRate.calculateBTBRate(price, cr, R_DEFAULT_BPS);
        // At peg, rate should be close to base rate with tolerance
        assertApproxEqAbs(rate, 1250, 20, "BTB rate at peg with CR=60% should be ~12.5%");
    }

    function test_calculateBTBRate_extremeLowCRAndPrice() public pure {
        // At price = 0.5 and CR = 20%, rate should be at max (20%)
        uint256 price = 5e17; // 0.5
        uint256 cr = 2e17;    // 20%
        uint256 rate = SigmoidRate.calculateBTBRate(price, cr, R_DEFAULT_BPS);
        assertGt(rate, 1900, "BTB rate at extreme conditions should be near max");
        assertLe(rate, BTB_R_MAX_BPS, "BTB rate should not exceed max");
    }

    // ============ Rate Clamping Tests ============

    function test_rateClamp_BTD_neverBelowMin() public pure {
        // Even with very high CR and price, rate should not go below 2%
        uint256 price = 12e17; // 1.2
        uint256 cr = 2e18;     // 200%
        uint256 rate = SigmoidRate.calculateBTDRate(price, cr, R_DEFAULT_BPS);
        assertGe(rate, R_MIN_BPS, "BTD rate should never go below 2%");
    }

    function test_rateClamp_BTD_neverAboveMax() public pure {
        // Even with very low CR and price, rate should not exceed 10%
        uint256 price = 5e17; // 0.5
        uint256 cr = 1e17;    // 10%
        uint256 rate = SigmoidRate.calculateBTDRate(price, cr, R_DEFAULT_BPS);
        assertLe(rate, BTD_R_MAX_BPS, "BTD rate should never exceed 10%");
    }

    function test_rateClamp_BTB_neverBelowMin() public pure {
        uint256 price = 15e17; // 1.5
        uint256 cr = 2e18;     // 200%
        uint256 rate = SigmoidRate.calculateBTBRate(price, cr, R_DEFAULT_BPS);
        assertGe(rate, R_MIN_BPS, "BTB rate should never go below 2%");
    }

    function test_rateClamp_BTB_neverAboveMax() public pure {
        uint256 price = 3e17; // 0.3
        uint256 cr = 1e17;    // 10%
        uint256 rate = SigmoidRate.calculateBTBRate(price, cr, R_DEFAULT_BPS);
        assertLe(rate, BTB_R_MAX_BPS, "BTB rate should never exceed 20%");
    }

    // ============ Custom Default Rate Tests ============

    function test_customDefaultRate_BTD() public pure {
        // Test with different default rate (300 bps = 3%)
        uint256 customDefault = 300;
        uint256 cr = 1e18; // 100%
        uint256 rate = SigmoidRate.getBTDBaseRate(cr, customDefault);
        assertEq(rate, customDefault, "Should use custom default rate");
    }

    function test_customDefaultRate_BTB() public pure {
        uint256 customDefault = 300;
        uint256 cr = 1e18;
        uint256 rate = SigmoidRate.getBTBBaseRate(cr, customDefault);
        assertEq(rate, customDefault, "Should use custom default rate");
    }

    // ============ Fuzz Tests ============

    function testFuzz_BTDBaseRate_monotonic(uint64 cr1, uint64 cr2) public pure {
        // Higher CR should result in lower or equal base rate
        cr1 = uint64(bound(cr1, CR_MIN, CR_UPPER));
        cr2 = uint64(bound(cr2, cr1, CR_UPPER));

        uint256 rate1 = SigmoidRate.getBTDBaseRate(cr1, R_DEFAULT_BPS);
        uint256 rate2 = SigmoidRate.getBTDBaseRate(cr2, R_DEFAULT_BPS);

        assertGe(rate1, rate2, "Higher CR should have lower or equal rate");
    }

    function testFuzz_BTBBaseRate_monotonic(uint64 cr1, uint64 cr2) public pure {
        cr1 = uint64(bound(cr1, CR_MIN, CR_UPPER));
        cr2 = uint64(bound(cr2, cr1, CR_UPPER));

        uint256 rate1 = SigmoidRate.getBTBBaseRate(cr1, R_DEFAULT_BPS);
        uint256 rate2 = SigmoidRate.getBTBBaseRate(cr2, R_DEFAULT_BPS);

        assertGe(rate1, rate2, "Higher CR should have lower or equal rate");
    }

    function testFuzz_BTDRate_bounded(uint64 price, uint64 cr) public pure {
        price = uint64(bound(price, 5e17, 15e17)); // 0.5 to 1.5
        cr = uint64(bound(cr, 1e17, 2e18));        // 10% to 200%

        uint256 rate = SigmoidRate.calculateBTDRate(price, cr, R_DEFAULT_BPS);

        assertGe(rate, R_MIN_BPS, "Rate should be >= min");
        assertLe(rate, BTD_R_MAX_BPS, "Rate should be <= max");
    }

    function testFuzz_BTBRate_bounded(uint64 price, uint64 cr) public pure {
        price = uint64(bound(price, 3e17, 17e17)); // 0.3 to 1.7
        cr = uint64(bound(cr, 1e17, 2e18));

        uint256 rate = SigmoidRate.calculateBTBRate(price, cr, R_DEFAULT_BPS);

        assertGe(rate, R_MIN_BPS, "Rate should be >= min");
        assertLe(rate, BTB_R_MAX_BPS, "Rate should be <= max");
    }

    function testFuzz_BTB_higherThanBTD_lowCR(uint64 cr) public pure {
        // For CR < 100%, BTB should always be >= BTD
        cr = uint64(bound(cr, CR_MIN, CR_THRESHOLD - 1));

        uint256 btdRate = SigmoidRate.getBTDBaseRate(cr, R_DEFAULT_BPS);
        uint256 btbRate = SigmoidRate.getBTBBaseRate(cr, R_DEFAULT_BPS);

        assertGe(btbRate, btdRate, "BTB should be >= BTD when CR < 100%");
    }

    // ============ Edge Case Tests ============

    function test_zeroDefaultRate() public pure {
        // With zero default rate, base rate should still clamp to min
        uint256 cr = 1e18;
        uint256 btdRate = SigmoidRate.getBTDBaseRate(cr, 0);
        uint256 btbRate = SigmoidRate.getBTBBaseRate(cr, 0);

        assertEq(btdRate, R_MIN_BPS, "Should clamp to min rate");
        assertEq(btbRate, R_MIN_BPS, "Should clamp to min rate");
    }

    function test_veryHighDefaultRate() public pure {
        // With very high default rate, should clamp to max
        uint256 cr = 1e18;
        uint256 highDefault = 5000; // 50%
        uint256 btdRate = SigmoidRate.getBTDBaseRate(cr, highDefault);
        uint256 btbRate = SigmoidRate.getBTBBaseRate(cr, highDefault);

        assertEq(btdRate, BTD_R_MAX_BPS, "Should clamp to BTD max rate");
        assertEq(btbRate, BTB_R_MAX_BPS, "Should clamp to BTB max rate");
    }

    function test_zeroCR() public pure {
        // CR = 0 should give max rate
        uint256 cr = 0;
        uint256 btdRate = SigmoidRate.getBTDBaseRate(cr, R_DEFAULT_BPS);
        uint256 btbRate = SigmoidRate.getBTBBaseRate(cr, R_DEFAULT_BPS);

        assertEq(btdRate, BTD_R_MAX_BPS, "BTD at CR=0 should be max");
        assertEq(btbRate, BTB_R_MAX_BPS, "BTB at CR=0 should be max");
    }
}
