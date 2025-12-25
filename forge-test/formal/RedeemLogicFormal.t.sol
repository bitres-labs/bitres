// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/RedeemLogic.sol";
import "../../contracts/libraries/Constants.sol";

/**
 * @title RedeemLogic Formal Verification Tests
 * @notice Formal verification tests using Halmos symbolic execution
 * @dev Tests prefixed with "check_" are symbolic tests for Halmos
 */
contract RedeemLogicFormalTest is Test {

    // ============ Over-collateralized (CR >= 100%) Properties ============

    /// @notice Verify only WBTC is returned when CR >= 100%
    function check_overcollateralized_only_wbtc(
        uint64 btdAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint16 redeemFeeBP
    ) public pure {
        vm.assume(btdAmount >= 100e18 && btdAmount <= 1000000e18);
        vm.assume(wbtcPrice >= 10000e18 && wbtcPrice <= 200000e18);
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18);
        vm.assume(redeemFeeBP <= 500);

        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: 1.5e18, // 150% CR - over-collateralized
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: redeemFeeBP
        });

        RedeemLogic.RedeemOutputs memory result = RedeemLogic.evaluate(inputs);

        // Should only get WBTC, no BTB or BRS
        assert(result.wbtcOutNormalized > 0);
        assert(result.btbOut == 0);
        assert(result.brsOut == 0);
    }

    /// @notice Verify fee is calculated correctly
    function check_fee_calculation(
        uint64 btdAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint16 redeemFeeBP
    ) public pure {
        vm.assume(btdAmount >= 100e18 && btdAmount <= 1000000e18);
        vm.assume(wbtcPrice >= 10000e18 && wbtcPrice <= 200000e18);
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18);
        vm.assume(redeemFeeBP <= 500);

        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: 1.5e18,
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: redeemFeeBP
        });

        RedeemLogic.RedeemOutputs memory result = RedeemLogic.evaluate(inputs);

        // Fee should be btdAmount * feeBP / 10000
        uint256 expectedFee = (uint256(btdAmount) * uint256(redeemFeeBP)) / 10000;
        assert(result.fee == expectedFee);
    }

    /// @notice Verify fee is zero when feeBP is zero
    function check_fee_zero_when_feeBP_zero(
        uint64 btdAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice
    ) public pure {
        vm.assume(btdAmount >= 100e18 && btdAmount <= 1000000e18);
        vm.assume(wbtcPrice >= 10000e18 && wbtcPrice <= 200000e18);
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18);

        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: 1.5e18,
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: 0
        });

        RedeemLogic.RedeemOutputs memory result = RedeemLogic.evaluate(inputs);

        assert(result.fee == 0);
    }

    /// @notice Verify fee is monotonic in feeBP
    function check_fee_monotonic_feeBP(
        uint64 btdAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint16 feeBP1,
        uint16 feeBP2
    ) public pure {
        vm.assume(btdAmount >= 100e18 && btdAmount <= 1000000e18);
        vm.assume(wbtcPrice >= 10000e18 && wbtcPrice <= 200000e18);
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18);
        vm.assume(feeBP1 <= feeBP2);
        vm.assume(feeBP2 <= 500);

        RedeemLogic.RedeemInputs memory inputs1 = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: 1.5e18,
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: feeBP1
        });

        RedeemLogic.RedeemInputs memory inputs2 = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: 1.5e18,
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: feeBP2
        });

        RedeemLogic.RedeemOutputs memory result1 = RedeemLogic.evaluate(inputs1);
        RedeemLogic.RedeemOutputs memory result2 = RedeemLogic.evaluate(inputs2);

        assert(result1.fee <= result2.fee);
    }

    // ============ Under-collateralized (CR < 100%) Properties ============

    /// @notice Verify BTB is returned when CR < 100% and BTB price >= min price
    function check_undercollateralized_btb_compensation(
        uint64 btdAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint64 cr
    ) public pure {
        vm.assume(btdAmount >= 1000e18 && btdAmount <= 100000e18);
        vm.assume(wbtcPrice >= 20000e18 && wbtcPrice <= 100000e18);
        vm.assume(iusdPrice >= 0.95e18 && iusdPrice <= 1.05e18);
        vm.assume(cr >= 0.5e18 && cr < 1e18); // 50% to 99%

        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: cr,
            btdPrice: 1e18,
            btbPrice: 0.5e18, // BTB at 50%
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18, // Min price 30%, BTB >= min so no BRS
            redeemFeeBP: 50
        });

        RedeemLogic.RedeemOutputs memory result = RedeemLogic.evaluate(inputs);

        // Should get WBTC + BTB, no BRS
        assert(result.wbtcOutNormalized > 0);
        assert(result.btbOut > 0);
        assert(result.brsOut == 0);
    }

    /// @notice Verify BRS is returned when BTB price < min price
    function check_undercollateralized_brs_compensation(
        uint64 btdAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint64 cr
    ) public pure {
        vm.assume(btdAmount >= 1000e18 && btdAmount <= 100000e18);
        vm.assume(wbtcPrice >= 20000e18 && wbtcPrice <= 100000e18);
        vm.assume(iusdPrice >= 0.95e18 && iusdPrice <= 1.05e18);
        vm.assume(cr >= 0.5e18 && cr < 1e18);

        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: cr,
            btdPrice: 1e18,
            btbPrice: 0.2e18, // BTB at 20%
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.5e18, // Min price 50%, BTB < min so BRS needed
            redeemFeeBP: 50
        });

        RedeemLogic.RedeemOutputs memory result = RedeemLogic.evaluate(inputs);

        // Should get WBTC + BTB + BRS
        assert(result.wbtcOutNormalized > 0);
        assert(result.btbOut > 0);
        assert(result.brsOut > 0);
    }

    /// @notice Verify WBTC output is proportional to CR when under-collateralized
    function check_wbtc_proportional_to_cr(
        uint64 btdAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint64 cr1,
        uint64 cr2
    ) public pure {
        vm.assume(btdAmount >= 1000e18 && btdAmount <= 100000e18);
        vm.assume(wbtcPrice >= 20000e18 && wbtcPrice <= 100000e18);
        vm.assume(iusdPrice >= 0.95e18 && iusdPrice <= 1.05e18);
        vm.assume(cr1 >= 0.5e18 && cr1 < 1e18);
        vm.assume(cr2 >= 0.5e18 && cr2 < 1e18);
        vm.assume(cr1 <= cr2);

        RedeemLogic.RedeemInputs memory inputs1 = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: cr1,
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: 50
        });

        RedeemLogic.RedeemInputs memory inputs2 = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: cr2,
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: 50
        });

        RedeemLogic.RedeemOutputs memory result1 = RedeemLogic.evaluate(inputs1);
        RedeemLogic.RedeemOutputs memory result2 = RedeemLogic.evaluate(inputs2);

        // Higher CR means more WBTC
        assert(result1.wbtcOutNormalized <= result2.wbtcOutNormalized);
    }

    /// @notice Verify BTB output decreases as CR increases
    function check_btb_inverse_to_cr(
        uint64 btdAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint64 cr1,
        uint64 cr2
    ) public pure {
        vm.assume(btdAmount >= 1000e18 && btdAmount <= 100000e18);
        vm.assume(wbtcPrice >= 20000e18 && wbtcPrice <= 100000e18);
        vm.assume(iusdPrice >= 0.95e18 && iusdPrice <= 1.05e18);
        vm.assume(cr1 >= 0.5e18 && cr1 < 1e18);
        vm.assume(cr2 >= 0.5e18 && cr2 < 1e18);
        vm.assume(cr1 <= cr2);

        RedeemLogic.RedeemInputs memory inputs1 = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: cr1,
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: 50
        });

        RedeemLogic.RedeemInputs memory inputs2 = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: cr2,
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: 50
        });

        RedeemLogic.RedeemOutputs memory result1 = RedeemLogic.evaluate(inputs1);
        RedeemLogic.RedeemOutputs memory result2 = RedeemLogic.evaluate(inputs2);

        // Lower CR means more BTB compensation
        assert(result1.btbOut >= result2.btbOut);
    }

    /// @notice Verify no compensation when CR >= 100%
    function check_no_compensation_overcollateralized(
        uint64 btdAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint64 cr
    ) public pure {
        vm.assume(btdAmount >= 100e18 && btdAmount <= 1000000e18);
        vm.assume(wbtcPrice >= 10000e18 && wbtcPrice <= 200000e18);
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18);
        vm.assume(cr >= 1e18 && cr <= 3e18); // 100% to 300%

        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: cr,
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: 50
        });

        RedeemLogic.RedeemOutputs memory result = RedeemLogic.evaluate(inputs);

        assert(result.btbOut == 0);
        assert(result.brsOut == 0);
    }

    /// @notice Verify WBTC output is monotonic in btdAmount
    function check_wbtc_monotonic_btdAmount(
        uint64 btdAmount1,
        uint64 btdAmount2,
        uint64 wbtcPrice,
        uint64 iusdPrice
    ) public pure {
        vm.assume(btdAmount1 >= 100e18 && btdAmount1 <= 500000e18);
        vm.assume(btdAmount2 >= 100e18 && btdAmount2 <= 1000000e18);
        vm.assume(btdAmount1 <= btdAmount2);
        vm.assume(wbtcPrice >= 10000e18 && wbtcPrice <= 200000e18);
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18);

        RedeemLogic.RedeemInputs memory inputs1 = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount1,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: 1.5e18,
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: 50
        });

        RedeemLogic.RedeemInputs memory inputs2 = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount2,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: 1.5e18,
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: 50
        });

        RedeemLogic.RedeemOutputs memory result1 = RedeemLogic.evaluate(inputs1);
        RedeemLogic.RedeemOutputs memory result2 = RedeemLogic.evaluate(inputs2);

        // More BTD redeemed means more WBTC out
        assert(result1.wbtcOutNormalized <= result2.wbtcOutNormalized);
    }
}
