// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/MintLogic.sol";
import "../../contracts/libraries/Constants.sol";

/**
 * @title MintLogic Formal Verification Tests
 * @notice Formal verification tests using Halmos symbolic execution
 * @dev Tests prefixed with "check_" are symbolic tests for Halmos
 */
contract MintLogicFormalTest is Test {

    // ============ Output Properties ============

    /// @notice Verify btdToMint + fee equals btdGross
    function check_btdToMint_plus_fee_equals_gross(
        uint64 wbtcAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint64 currentSupply,
        uint16 feeBP
    ) public pure {
        // Bounds to avoid overflow and meet minimums
        vm.assume(wbtcAmount >= 1e5 && wbtcAmount <= 100e8); // 0.001 to 100 BTC
        vm.assume(wbtcPrice >= 10000e18 && wbtcPrice <= 200000e18); // $10k to $200k
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18); // 0.9 to 1.1 USD
        vm.assume(feeBP <= 1000); // max 10% fee

        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            currentBTDSupply: currentSupply,
            feeBP: feeBP
        });

        MintLogic.MintOutputs memory result = MintLogic.evaluate(inputs);

        assert(result.btdToMint + result.fee == result.btdGross);
    }

    /// @notice Verify btdToMint is always less than or equal to btdGross
    function check_btdToMint_le_btdGross(
        uint64 wbtcAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint64 currentSupply,
        uint16 feeBP
    ) public pure {
        vm.assume(wbtcAmount >= 1e5 && wbtcAmount <= 100e8);
        vm.assume(wbtcPrice >= 10000e18 && wbtcPrice <= 200000e18);
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18);
        vm.assume(feeBP <= 1000);

        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            currentBTDSupply: currentSupply,
            feeBP: feeBP
        });

        MintLogic.MintOutputs memory result = MintLogic.evaluate(inputs);

        assert(result.btdToMint <= result.btdGross);
    }

    /// @notice Verify fee is zero when feeBP is zero
    function check_fee_zero_when_feeBP_zero(
        uint64 wbtcAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint64 currentSupply
    ) public pure {
        vm.assume(wbtcAmount >= 1e5 && wbtcAmount <= 100e8);
        vm.assume(wbtcPrice >= 10000e18 && wbtcPrice <= 200000e18);
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18);

        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            currentBTDSupply: currentSupply,
            feeBP: 0
        });

        MintLogic.MintOutputs memory result = MintLogic.evaluate(inputs);

        assert(result.fee == 0);
        assert(result.btdToMint == result.btdGross);
    }

    /// @notice Verify btdGross is monotonic in wbtcAmount
    function check_btdGross_monotonic_wbtcAmount(
        uint64 wbtcAmount1,
        uint64 wbtcAmount2,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint64 currentSupply,
        uint16 feeBP
    ) public pure {
        vm.assume(wbtcAmount1 >= 1e5 && wbtcAmount1 <= 50e8);
        vm.assume(wbtcAmount2 >= 1e5 && wbtcAmount2 <= 100e8);
        vm.assume(wbtcAmount1 <= wbtcAmount2);
        vm.assume(wbtcPrice >= 10000e18 && wbtcPrice <= 200000e18);
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18);
        vm.assume(feeBP <= 1000);

        MintLogic.MintInputs memory inputs1 = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount1,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            currentBTDSupply: currentSupply,
            feeBP: feeBP
        });

        MintLogic.MintInputs memory inputs2 = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount2,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            currentBTDSupply: currentSupply,
            feeBP: feeBP
        });

        MintLogic.MintOutputs memory result1 = MintLogic.evaluate(inputs1);
        MintLogic.MintOutputs memory result2 = MintLogic.evaluate(inputs2);

        assert(result1.btdGross <= result2.btdGross);
    }

    /// @notice Verify btdGross is monotonic in wbtcPrice
    function check_btdGross_monotonic_wbtcPrice(
        uint64 wbtcAmount,
        uint64 wbtcPrice1,
        uint64 wbtcPrice2,
        uint64 iusdPrice,
        uint64 currentSupply,
        uint16 feeBP
    ) public pure {
        vm.assume(wbtcAmount >= 1e5 && wbtcAmount <= 100e8);
        vm.assume(wbtcPrice1 >= 10000e18 && wbtcPrice1 <= 100000e18);
        vm.assume(wbtcPrice2 >= 10000e18 && wbtcPrice2 <= 200000e18);
        vm.assume(wbtcPrice1 <= wbtcPrice2);
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18);
        vm.assume(feeBP <= 1000);

        MintLogic.MintInputs memory inputs1 = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: wbtcPrice1,
            iusdPrice: iusdPrice,
            currentBTDSupply: currentSupply,
            feeBP: feeBP
        });

        MintLogic.MintInputs memory inputs2 = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: wbtcPrice2,
            iusdPrice: iusdPrice,
            currentBTDSupply: currentSupply,
            feeBP: feeBP
        });

        MintLogic.MintOutputs memory result1 = MintLogic.evaluate(inputs1);
        MintLogic.MintOutputs memory result2 = MintLogic.evaluate(inputs2);

        assert(result1.btdGross <= result2.btdGross);
    }

    /// @notice Verify usdValue is positive when wbtcAmount and wbtcPrice are positive
    function check_usdValue_positive(
        uint64 wbtcAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint64 currentSupply,
        uint16 feeBP
    ) public pure {
        vm.assume(wbtcAmount >= 1e5 && wbtcAmount <= 100e8);
        vm.assume(wbtcPrice >= 10000e18 && wbtcPrice <= 200000e18);
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18);
        vm.assume(feeBP <= 1000);

        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            currentBTDSupply: currentSupply,
            feeBP: feeBP
        });

        MintLogic.MintOutputs memory result = MintLogic.evaluate(inputs);

        assert(result.usdValue > 0);
    }

    /// @notice Verify normalizedWBTC equals wbtcAmount * SCALE_WBTC_TO_NORM
    function check_normalizedWBTC_correct(
        uint64 wbtcAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint64 currentSupply,
        uint16 feeBP
    ) public pure {
        vm.assume(wbtcAmount >= 1e5 && wbtcAmount <= 100e8);
        vm.assume(wbtcPrice >= 10000e18 && wbtcPrice <= 200000e18);
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18);
        vm.assume(feeBP <= 1000);

        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            currentBTDSupply: currentSupply,
            feeBP: feeBP
        });

        MintLogic.MintOutputs memory result = MintLogic.evaluate(inputs);

        assert(result.normalizedWBTC == wbtcAmount * Constants.SCALE_WBTC_TO_NORM);
    }

    /// @notice Verify fee is monotonic in feeBP
    function check_fee_monotonic_feeBP(
        uint64 wbtcAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint64 currentSupply,
        uint16 feeBP1,
        uint16 feeBP2
    ) public pure {
        vm.assume(wbtcAmount >= 1e5 && wbtcAmount <= 100e8);
        vm.assume(wbtcPrice >= 10000e18 && wbtcPrice <= 200000e18);
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18);
        vm.assume(feeBP1 <= feeBP2);
        vm.assume(feeBP2 <= 1000);

        MintLogic.MintInputs memory inputs1 = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            currentBTDSupply: currentSupply,
            feeBP: feeBP1
        });

        MintLogic.MintInputs memory inputs2 = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            currentBTDSupply: currentSupply,
            feeBP: feeBP2
        });

        MintLogic.MintOutputs memory result1 = MintLogic.evaluate(inputs1);
        MintLogic.MintOutputs memory result2 = MintLogic.evaluate(inputs2);

        assert(result1.fee <= result2.fee);
    }

    /// @notice Verify newLiabilityValue is always >= usdValue
    function check_newLiabilityValue_ge_usdValue(
        uint64 wbtcAmount,
        uint64 wbtcPrice,
        uint64 iusdPrice,
        uint64 currentSupply,
        uint16 feeBP
    ) public pure {
        vm.assume(wbtcAmount >= 1e5 && wbtcAmount <= 100e8);
        vm.assume(wbtcPrice >= 10000e18 && wbtcPrice <= 200000e18);
        vm.assume(iusdPrice >= 0.9e18 && iusdPrice <= 1.1e18);
        vm.assume(feeBP <= 1000);

        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            currentBTDSupply: currentSupply,
            feeBP: feeBP
        });

        MintLogic.MintOutputs memory result = MintLogic.evaluate(inputs);

        // New liability should account for new minted BTD
        // Since IUSD price ~= 1 USD, newLiabilityValue ~= currentSupply + btdGross
        assert(result.newLiabilityValue >= result.usdValue);
    }
}
