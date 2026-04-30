// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/MintLogic.sol";
import "../../contracts/libraries/Constants.sol";

/**
 * @title MintLogic Formal Verification Tests
 * @notice Symbolic properties for the BTD minting calculation library.
 * @dev Symbolic inputs use compact business units, then scale to protocol decimals.
 */
contract MintLogicFormalTest is Test {
    uint32 private constant MAX_WBTC_MILLI_BTC = 100_000; // 100 BTC
    uint32 private constant MAX_SUPPLY_TOKENS = 1_000_000_000;

    function _wbtcAmount(uint32 milliBtc) private pure returns (uint256) {
        return uint256(milliBtc) * 1e5; // 0.001 BTC = 100000 WBTC satoshis
    }

    function _price(uint8 thousandUsd) private pure returns (uint256) {
        return uint256(thousandUsd) * 1_000e18;
    }

    function _iusd(uint16 bps) private pure returns (uint256) {
        return uint256(bps) * 1e14;
    }

    function _supply(uint32 wholeTokens) private pure returns (uint256) {
        return uint256(wholeTokens) * 1e18;
    }

    function _assumeMintDomain(
        uint32 wbtcMilliBtc,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint32 currentSupplyTokens,
        uint16 feeBP
    ) private pure {
        vm.assume(wbtcMilliBtc > 0 && wbtcMilliBtc <= MAX_WBTC_MILLI_BTC);
        vm.assume(wbtcPriceKUsd >= 10 && wbtcPriceKUsd <= 200);
        vm.assume(iusdBps >= 9_000 && iusdBps <= 11_000);
        vm.assume(currentSupplyTokens <= MAX_SUPPLY_TOKENS);
        vm.assume(feeBP <= 1_000);
    }

    function _inputs(uint32 wbtcMilliBtc, uint8 wbtcPriceKUsd, uint16 iusdBps, uint32 currentSupplyTokens, uint16 feeBP)
        private
        pure
        returns (MintLogic.MintInputs memory)
    {
        _assumeMintDomain(wbtcMilliBtc, wbtcPriceKUsd, iusdBps, currentSupplyTokens, feeBP);
        return MintLogic.MintInputs({
            wbtcAmount: _wbtcAmount(wbtcMilliBtc),
            wbtcPrice: _price(wbtcPriceKUsd),
            iusdPrice: _iusd(iusdBps),
            currentBTDSupply: _supply(currentSupplyTokens),
            feeBP: feeBP
        });
    }

    /// @notice Verify fee is zero when feeBP is zero.
    function check_fee_zero_when_feeBP_zero(
        uint32 wbtcMilliBtc,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint32 currentSupplyTokens
    ) public pure {
        MintLogic.MintOutputs memory result =
            MintLogic.evaluate(_inputs(wbtcMilliBtc, wbtcPriceKUsd, iusdBps, currentSupplyTokens, 0));

        assert(result.fee == 0);
        assert(result.btdToMint == result.btdGross);
    }

    /// @notice Verify exact mint accounting at the IUSD peg with zero fee.
    function check_z_atPeg_zeroFee_exactAccounting(
        uint32 wbtcMilliBtc,
        uint8 wbtcPriceKUsd,
        uint32 currentSupplyTokens
    ) public pure {
        MintLogic.MintOutputs memory result =
            MintLogic.evaluate(_inputs(wbtcMilliBtc, wbtcPriceKUsd, 10_000, currentSupplyTokens, 0));

        assert(result.btdGross == result.usdValue);
        assert(result.btdToMint == result.usdValue);
        assert(result.fee == 0);
        assert(result.newLiabilityValue == _supply(currentSupplyTokens) + result.usdValue);
    }

    /// @notice Verify protocol fee cap leaves at least 90% of gross mint amount for the user.
    function check_z_fee_cap_keeps_user_mint_above_90_percent(
        uint32 wbtcMilliBtc,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint32 currentSupplyTokens,
        uint16 feeBP
    ) public pure {
        MintLogic.MintOutputs memory result = MintLogic.evaluate(
            _inputs(wbtcMilliBtc, wbtcPriceKUsd, iusdBps, currentSupplyTokens, feeBP)
        );

        assert(result.fee <= result.btdGross / 10);
        assert(result.btdToMint >= result.btdGross - (result.btdGross / 10));
    }

    /// @notice Verify normalizedWBTC equals wbtcAmount * SCALE_WBTC_TO_NORM.
    function check_normalizedWBTC_correct(
        uint32 wbtcMilliBtc,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint32 currentSupplyTokens,
        uint16 feeBP
    ) public pure {
        MintLogic.MintOutputs memory result = MintLogic.evaluate(
            _inputs(wbtcMilliBtc, wbtcPriceKUsd, iusdBps, currentSupplyTokens, feeBP)
        );

        assert(result.normalizedWBTC == _wbtcAmount(wbtcMilliBtc) * Constants.SCALE_WBTC_TO_NORM);
    }

    /// @notice Verify usdValue is positive when WBTC amount and price are positive.
    function check_usdValue_positive(
        uint32 wbtcMilliBtc,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint32 currentSupplyTokens,
        uint16 feeBP
    ) public pure {
        MintLogic.MintOutputs memory result = MintLogic.evaluate(
            _inputs(wbtcMilliBtc, wbtcPriceKUsd, iusdBps, currentSupplyTokens, feeBP)
        );

        assert(result.usdValue > 0);
    }

    /// @notice Verify new liability value covers the minted collateral value up to one wei of rounding.
    function check_z_newLiabilityValue_ge_usdValue_minus_rounding(
        uint32 wbtcMilliBtc,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint32 currentSupplyTokens,
        uint16 feeBP
    ) public pure {
        MintLogic.MintOutputs memory result = MintLogic.evaluate(
            _inputs(wbtcMilliBtc, wbtcPriceKUsd, iusdBps, currentSupplyTokens, feeBP)
        );

        assert(result.newLiabilityValue + 1 >= result.usdValue);
    }

    /// @notice Verify btdToMint is always less than or equal to btdGross.
    function check_z_btdToMint_le_btdGross(
        uint32 wbtcMilliBtc,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint32 currentSupplyTokens,
        uint16 feeBP
    ) public pure {
        MintLogic.MintOutputs memory result = MintLogic.evaluate(
            _inputs(wbtcMilliBtc, wbtcPriceKUsd, iusdBps, currentSupplyTokens, feeBP)
        );

        assert(result.btdToMint <= result.btdGross);
    }

    /// @notice Verify btdToMint + fee equals btdGross.
    function check_z_btdToMint_plus_fee_equals_gross(
        uint32 wbtcMilliBtc,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint32 currentSupplyTokens,
        uint16 feeBP
    ) public pure {
        MintLogic.MintOutputs memory result = MintLogic.evaluate(
            _inputs(wbtcMilliBtc, wbtcPriceKUsd, iusdBps, currentSupplyTokens, feeBP)
        );

        assert(result.btdToMint + result.fee == result.btdGross);
    }

    /// @notice Verify btdGross is monotonic in wbtcAmount.
    function check_z_btdGross_monotonic_wbtcAmount(
        uint32 wbtcMilliBtc1,
        uint32 wbtcMilliBtc2,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint32 currentSupplyTokens,
        uint16 feeBP
    ) public pure {
        vm.assume(wbtcMilliBtc1 > 0 && wbtcMilliBtc1 <= 50_000);
        vm.assume(wbtcMilliBtc2 > 0 && wbtcMilliBtc2 <= MAX_WBTC_MILLI_BTC);
        vm.assume(wbtcMilliBtc1 <= wbtcMilliBtc2);

        MintLogic.MintOutputs memory result1 =
            MintLogic.evaluate(_inputs(wbtcMilliBtc1, wbtcPriceKUsd, iusdBps, currentSupplyTokens, feeBP));
        MintLogic.MintOutputs memory result2 =
            MintLogic.evaluate(_inputs(wbtcMilliBtc2, wbtcPriceKUsd, iusdBps, currentSupplyTokens, feeBP));

        assert(result1.btdGross <= result2.btdGross);
    }

    /// @notice Verify btdGross is monotonic in wbtcPrice.
    function check_z_btdGross_monotonic_wbtcPrice(
        uint32 wbtcMilliBtc,
        uint8 wbtcPriceKUsd1,
        uint8 wbtcPriceKUsd2,
        uint16 iusdBps,
        uint32 currentSupplyTokens,
        uint16 feeBP
    ) public pure {
        vm.assume(wbtcPriceKUsd1 >= 10 && wbtcPriceKUsd1 <= 100);
        vm.assume(wbtcPriceKUsd2 >= 10 && wbtcPriceKUsd2 <= 200);
        vm.assume(wbtcPriceKUsd1 <= wbtcPriceKUsd2);

        MintLogic.MintOutputs memory result1 =
            MintLogic.evaluate(_inputs(wbtcMilliBtc, wbtcPriceKUsd1, iusdBps, currentSupplyTokens, feeBP));
        MintLogic.MintOutputs memory result2 =
            MintLogic.evaluate(_inputs(wbtcMilliBtc, wbtcPriceKUsd2, iusdBps, currentSupplyTokens, feeBP));

        assert(result1.btdGross <= result2.btdGross);
    }

    /// @notice Verify fee is monotonic in feeBP.
    function check_z_fee_monotonic_feeBP(
        uint32 wbtcMilliBtc,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint32 currentSupplyTokens,
        uint16 feeBP1,
        uint16 feeBP2
    ) public pure {
        vm.assume(feeBP1 <= feeBP2);
        vm.assume(feeBP2 <= 1_000);

        MintLogic.MintOutputs memory result1 =
            MintLogic.evaluate(_inputs(wbtcMilliBtc, wbtcPriceKUsd, iusdBps, currentSupplyTokens, feeBP1));
        MintLogic.MintOutputs memory result2 =
            MintLogic.evaluate(_inputs(wbtcMilliBtc, wbtcPriceKUsd, iusdBps, currentSupplyTokens, feeBP2));

        assert(result1.fee <= result2.fee);
    }
}
