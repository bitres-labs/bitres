// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/ConfigGov.sol";
import "../../contracts/libraries/Constants.sol";

/// @title ConfigGov BASE_RATE_DEFAULT Unit Tests
/// @notice Tests for the BASE_RATE_DEFAULT governance parameter
contract ConfigGovBaseRateTest is Test {
    ConfigGov public gov;
    address public owner;
    address public user;

    // Constants for BASE_RATE_DEFAULT
    uint256 constant DEFAULT_BASE_RATE = 500;  // 5%
    uint256 constant MIN_BASE_RATE = 100;      // 1%
    uint256 constant MAX_BASE_RATE = 1000;     // 10%

    function setUp() public {
        owner = address(this);
        user = address(0x1234);
        gov = new ConfigGov(owner);
    }

    // ============ Default Value Tests ============

    function test_baseRateDefault_initialValue() public view {
        uint256 rate = gov.baseRateDefault();
        assertEq(rate, DEFAULT_BASE_RATE, "Initial base rate should be 500 bps (5%)");
    }

    function test_getParam_baseRateDefault() public view {
        uint256 rate = gov.getParam(ConfigGov.ParamType.BASE_RATE_DEFAULT);
        assertEq(rate, DEFAULT_BASE_RATE, "getParam should return 500 bps");
    }

    // ============ Set Parameter Tests ============

    function test_setParam_baseRateDefault_success() public {
        uint256 newRate = 300; // 3%

        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, newRate);

        assertEq(gov.baseRateDefault(), newRate, "Base rate should be updated");
    }

    function test_setParam_baseRateDefault_minValue() public {
        uint256 minRate = MIN_BASE_RATE; // 1%

        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, minRate);

        assertEq(gov.baseRateDefault(), minRate, "Should accept minimum rate");
    }

    function test_setParam_baseRateDefault_maxValue() public {
        uint256 maxRate = MAX_BASE_RATE; // 10%

        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, maxRate);

        assertEq(gov.baseRateDefault(), maxRate, "Should accept maximum rate");
    }

    function test_setParam_baseRateDefault_revertTooLow() public {
        uint256 tooLow = MIN_BASE_RATE - 1; // 0.99%

        vm.expectRevert("ConfigGov: base rate too low");
        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, tooLow);
    }

    function test_setParam_baseRateDefault_revertTooHigh() public {
        uint256 tooHigh = MAX_BASE_RATE + 1; // 10.01%

        vm.expectRevert("ConfigGov: base rate too high");
        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, tooHigh);
    }

    function test_setParam_baseRateDefault_revertZero() public {
        vm.expectRevert("ConfigGov: base rate too low");
        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, 0);
    }

    // ============ Access Control Tests ============

    function test_setParam_onlyOwner() public {
        vm.prank(user);
        vm.expectRevert(); // OwnableUnauthorizedAccount
        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, 300);
    }

    // ============ Batch Set Tests ============

    function test_setParamsBatch_includesBaseRate() public {
        ConfigGov.ParamType[] memory types = new ConfigGov.ParamType[](2);
        uint256[] memory values = new uint256[](2);

        types[0] = ConfigGov.ParamType.MINT_FEE_BP;
        values[0] = 100; // 1%

        types[1] = ConfigGov.ParamType.BASE_RATE_DEFAULT;
        values[1] = 400; // 4%

        gov.setParamsBatch(types, values);

        assertEq(gov.mintFeeBP(), 100, "Mint fee should be updated");
        assertEq(gov.baseRateDefault(), 400, "Base rate should be updated");
    }

    function test_setParamsBatch_revertOnInvalidBaseRate() public {
        ConfigGov.ParamType[] memory types = new ConfigGov.ParamType[](2);
        uint256[] memory values = new uint256[](2);

        types[0] = ConfigGov.ParamType.MINT_FEE_BP;
        values[0] = 100;

        types[1] = ConfigGov.ParamType.BASE_RATE_DEFAULT;
        values[1] = 2000; // Too high

        vm.expectRevert("ConfigGov: base rate too high");
        gov.setParamsBatch(types, values);
    }

    // ============ Event Tests ============

    function test_setParam_emitsEvent() public {
        vm.expectEmit(true, false, false, true);
        emit ConfigGov.ParamUpdated(ConfigGov.ParamType.BASE_RATE_DEFAULT, 300);

        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, 300);
    }

    // ============ Fuzz Tests ============

    function testFuzz_baseRateDefault_validRange(uint256 rate) public {
        rate = bound(rate, MIN_BASE_RATE, MAX_BASE_RATE);

        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, rate);

        assertEq(gov.baseRateDefault(), rate, "Rate should be set correctly");
    }

    function testFuzz_baseRateDefault_rejectInvalid(uint256 rate) public {
        // Test rates outside valid range
        if (rate < MIN_BASE_RATE) {
            vm.expectRevert("ConfigGov: base rate too low");
            gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, rate);
        } else if (rate > MAX_BASE_RATE) {
            vm.expectRevert("ConfigGov: base rate too high");
            gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, rate);
        }
        // Valid range handled by testFuzz_baseRateDefault_validRange
    }

    // ============ Integration with Other Params Tests ============

    function test_baseRateDefault_independentOfOtherParams() public {
        // Change other params, verify base rate unchanged
        gov.setParam(ConfigGov.ParamType.MINT_FEE_BP, 100);
        gov.setParam(ConfigGov.ParamType.REDEEM_FEE_BP, 100);
        gov.setParam(ConfigGov.ParamType.INTEREST_FEE_BP, 1000);

        assertEq(gov.baseRateDefault(), DEFAULT_BASE_RATE, "Base rate should remain unchanged");
    }

    function test_allParamsIndependent() public {
        // Set all params to non-default values
        gov.setParam(ConfigGov.ParamType.MINT_FEE_BP, 100);
        gov.setParam(ConfigGov.ParamType.REDEEM_FEE_BP, 100);
        gov.setParam(ConfigGov.ParamType.INTEREST_FEE_BP, 1000);
        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, 300);

        // Verify all are set correctly
        assertEq(gov.mintFeeBP(), 100);
        assertEq(gov.redeemFeeBP(), 100);
        assertEq(gov.interestFeeBP(), 1000);
        assertEq(gov.baseRateDefault(), 300);
    }

    // ============ Edge Cases ============

    function test_baseRateDefault_exactMinBoundary() public {
        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, MIN_BASE_RATE);
        assertEq(gov.baseRateDefault(), MIN_BASE_RATE);

        // One below should fail
        vm.expectRevert("ConfigGov: base rate too low");
        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, MIN_BASE_RATE - 1);
    }

    function test_baseRateDefault_exactMaxBoundary() public {
        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, MAX_BASE_RATE);
        assertEq(gov.baseRateDefault(), MAX_BASE_RATE);

        // One above should fail
        vm.expectRevert("ConfigGov: base rate too high");
        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, MAX_BASE_RATE + 1);
    }

    function test_baseRateDefault_multipleUpdates() public {
        // Update multiple times
        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, 200);
        assertEq(gov.baseRateDefault(), 200);

        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, 800);
        assertEq(gov.baseRateDefault(), 800);

        gov.setParam(ConfigGov.ParamType.BASE_RATE_DEFAULT, 500);
        assertEq(gov.baseRateDefault(), 500);
    }
}
