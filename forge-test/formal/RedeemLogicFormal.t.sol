// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/RedeemLogic.sol";

/**
 * @title RedeemLogic Formal Verification Tests
 * @notice Symbolic properties for the BTD redemption calculation library.
 * @dev Symbolic inputs use compact business units, then scale to protocol decimals.
 */
contract RedeemLogicFormalTest is Test {
    function _btd(uint24 wholeTokens) private pure returns (uint256) {
        return uint256(wholeTokens) * 1e18;
    }

    function _price(uint8 thousandUsd) private pure returns (uint256) {
        return uint256(thousandUsd) * 1_000e18;
    }

    function _iusd(uint16 bps) private pure returns (uint256) {
        return uint256(bps) * 1e14;
    }

    function _cr(uint16 bps) private pure returns (uint256) {
        return uint256(bps) * 1e14;
    }

    function _assumeRedeemDomain(uint24 btdTokens, uint8 wbtcPriceKUsd, uint16 iusdBps, uint16 redeemFeeBP)
        private
        pure
    {
        vm.assume(btdTokens >= 100 && btdTokens <= 1_000_000);
        vm.assume(wbtcPriceKUsd >= 10 && wbtcPriceKUsd <= 200);
        vm.assume(iusdBps >= 9_000 && iusdBps <= 11_000);
        vm.assume(redeemFeeBP <= 500);
    }

    function _overInputs(uint24 btdTokens, uint8 wbtcPriceKUsd, uint16 iusdBps, uint16 redeemFeeBP)
        private
        pure
        returns (RedeemLogic.RedeemInputs memory)
    {
        _assumeRedeemDomain(btdTokens, wbtcPriceKUsd, iusdBps, redeemFeeBP);
        return RedeemLogic.RedeemInputs({
            btdAmount: _btd(btdTokens),
            wbtcPrice: _price(wbtcPriceKUsd),
            iusdPrice: _iusd(iusdBps),
            cr: 1.5e18,
            btdPrice: 1e18,
            btbPrice: 0.5e18,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: 0.3e18,
            redeemFeeBP: redeemFeeBP
        });
    }

    function _underInputs(
        uint24 btdTokens,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint16 crBps,
        uint256 btbPrice,
        uint256 minBTBPriceInBTD
    ) private pure returns (RedeemLogic.RedeemInputs memory) {
        vm.assume(btdTokens >= 1_000 && btdTokens <= 100_000);
        vm.assume(wbtcPriceKUsd >= 20 && wbtcPriceKUsd <= 100);
        vm.assume(iusdBps >= 9_500 && iusdBps <= 10_500);
        vm.assume(crBps >= 5_000 && crBps < 10_000);

        return RedeemLogic.RedeemInputs({
            btdAmount: _btd(btdTokens),
            wbtcPrice: _price(wbtcPriceKUsd),
            iusdPrice: _iusd(iusdBps),
            cr: _cr(crBps),
            btdPrice: 1e18,
            btbPrice: btbPrice,
            brsPrice: 0.1e18,
            minBTBPriceInBTD: minBTBPriceInBTD,
            redeemFeeBP: 50
        });
    }

    /// @notice Verify fee is calculated correctly.
    function check_fee_calculation(uint24 btdTokens, uint8 wbtcPriceKUsd, uint16 iusdBps, uint16 redeemFeeBP)
        public
        pure
    {
        RedeemLogic.RedeemOutputs memory result =
            RedeemLogic.evaluate(_overInputs(btdTokens, wbtcPriceKUsd, iusdBps, redeemFeeBP));

        uint256 expectedFee = (_btd(btdTokens) * uint256(redeemFeeBP)) / 10_000;
        assert(result.fee == expectedFee);
    }

    /// @notice Verify fee is zero when feeBP is zero.
    function check_fee_zero_when_feeBP_zero(uint24 btdTokens, uint8 wbtcPriceKUsd, uint16 iusdBps) public pure {
        RedeemLogic.RedeemOutputs memory result =
            RedeemLogic.evaluate(_overInputs(btdTokens, wbtcPriceKUsd, iusdBps, 0));

        assert(result.fee == 0);
    }

    /// @notice Verify no compensation is returned when CR >= 100%.
    function check_no_compensation_overcollateralized(
        uint24 btdTokens,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint16 crBps
    ) public pure {
        vm.assume(crBps >= 10_000 && crBps <= 30_000);

        RedeemLogic.RedeemInputs memory inputs = _overInputs(btdTokens, wbtcPriceKUsd, iusdBps, 50);
        inputs.cr = _cr(crBps);
        RedeemLogic.RedeemOutputs memory result = RedeemLogic.evaluate(inputs);

        assert(result.btbOut == 0);
        assert(result.brsOut == 0);
    }

    /// @notice Verify only WBTC is returned when CR >= 100%.
    function check_overcollateralized_only_wbtc(
        uint24 btdTokens,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint16 redeemFeeBP
    ) public pure {
        RedeemLogic.RedeemOutputs memory result =
            RedeemLogic.evaluate(_overInputs(btdTokens, wbtcPriceKUsd, iusdBps, redeemFeeBP));

        assert(result.wbtcOutNormalized > 0);
        assert(result.btbOut == 0);
        assert(result.brsOut == 0);
    }

    /// @notice Verify BTB is returned when CR < 100% and BTB price >= min price.
    function check_undercollateralized_btb_compensation(
        uint24 btdTokens,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint16 crBps
    ) public pure {
        RedeemLogic.RedeemOutputs memory result =
            RedeemLogic.evaluate(_underInputs(btdTokens, wbtcPriceKUsd, iusdBps, crBps, 0.5e18, 0.3e18));

        assert(result.wbtcOutNormalized > 0);
        assert(result.btbOut > 0);
        assert(result.brsOut == 0);
    }

    /// @notice Verify BRS is returned when BTB price is below the configured minimum.
    function check_undercollateralized_brs_compensation(
        uint24 btdTokens,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint16 crBps
    ) public pure {
        RedeemLogic.RedeemOutputs memory result =
            RedeemLogic.evaluate(_underInputs(btdTokens, wbtcPriceKUsd, iusdBps, crBps, 0.2e18, 0.5e18));

        assert(result.wbtcOutNormalized > 0);
        assert(result.btbOut > 0);
        assert(result.brsOut > 0);
    }

    /// @notice Verify BTB output decreases as CR increases.
    function check_z_btb_inverse_to_cr(
        uint24 btdTokens,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint16 crBps1,
        uint16 crBps2
    ) public pure {
        vm.assume(crBps1 <= crBps2);

        RedeemLogic.RedeemOutputs memory result1 =
            RedeemLogic.evaluate(_underInputs(btdTokens, wbtcPriceKUsd, iusdBps, crBps1, 0.5e18, 0.3e18));
        RedeemLogic.RedeemOutputs memory result2 =
            RedeemLogic.evaluate(_underInputs(btdTokens, wbtcPriceKUsd, iusdBps, crBps2, 0.5e18, 0.3e18));

        assert(result1.btbOut >= result2.btbOut);
    }

    /// @notice Verify fee is monotonic in feeBP.
    function check_z_fee_monotonic_feeBP(
        uint24 btdTokens,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint16 feeBP1,
        uint16 feeBP2
    ) public pure {
        vm.assume(feeBP1 <= feeBP2);
        vm.assume(feeBP2 <= 500);

        RedeemLogic.RedeemOutputs memory result1 =
            RedeemLogic.evaluate(_overInputs(btdTokens, wbtcPriceKUsd, iusdBps, feeBP1));
        RedeemLogic.RedeemOutputs memory result2 =
            RedeemLogic.evaluate(_overInputs(btdTokens, wbtcPriceKUsd, iusdBps, feeBP2));

        assert(result1.fee <= result2.fee);
    }

    /// @notice Verify WBTC output is monotonic in btdAmount.
    function check_z_wbtc_monotonic_btdAmount(uint24 btdTokens1, uint24 btdTokens2, uint8 wbtcPriceKUsd, uint16 iusdBps)
        public
        pure
    {
        vm.assume(btdTokens1 >= 100 && btdTokens1 <= 500_000);
        vm.assume(btdTokens2 >= 100 && btdTokens2 <= 1_000_000);
        vm.assume(btdTokens1 <= btdTokens2);

        RedeemLogic.RedeemOutputs memory result1 =
            RedeemLogic.evaluate(_overInputs(btdTokens1, wbtcPriceKUsd, iusdBps, 50));
        RedeemLogic.RedeemOutputs memory result2 =
            RedeemLogic.evaluate(_overInputs(btdTokens2, wbtcPriceKUsd, iusdBps, 50));

        assert(result1.wbtcOutNormalized <= result2.wbtcOutNormalized);
    }

    /// @notice Verify WBTC output is proportional to CR when under-collateralized.
    function check_z_wbtc_proportional_to_cr(
        uint24 btdTokens,
        uint8 wbtcPriceKUsd,
        uint16 iusdBps,
        uint16 crBps1,
        uint16 crBps2
    ) public pure {
        vm.assume(crBps1 <= crBps2);

        RedeemLogic.RedeemOutputs memory result1 =
            RedeemLogic.evaluate(_underInputs(btdTokens, wbtcPriceKUsd, iusdBps, crBps1, 0.5e18, 0.3e18));
        RedeemLogic.RedeemOutputs memory result2 =
            RedeemLogic.evaluate(_underInputs(btdTokens, wbtcPriceKUsd, iusdBps, crBps2, 0.5e18, 0.3e18));

        assert(result1.wbtcOutNormalized <= result2.wbtcOutNormalized);
    }
}
