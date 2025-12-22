// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./Constants.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title RedeemLogic - BTD Redemption Logic Calculation Library
 * @notice Pure function library: Responsible for amount calculations in BTD redemption flow
 * @dev Implements dual-token redemption mechanism: Returns WBTC when over-collateralized, returns WBTC+BTB+BRS combination when under-collateralized
 */
library RedeemLogic {


    /**
     * @notice Redemption input parameters structure
     * @param btdAmount BTD amount to redeem (18 decimals)
     * @param wbtcPrice WBTC price (18 decimals, unit: USD)
     * @param iusdPrice IUSD price (18 decimals, unit: USD)
     * @param cr Collateral ratio (18 decimals, 1e18 = 100%)
     * @param btdPrice BTD price (18 decimals, unit: USD)
     * @param btbPrice BTB price (18 decimals, unit: USD)
     * @param brsPrice BRS price (18 decimals, unit: USD)
     * @param minBTBPriceInBTD BTB minimum price relative to BTD (18 decimals)
     * @param redeemFeeBP Redemption fee rate (basis points, e.g., 50=0.5%)
     */
    struct RedeemInputs {
        uint256 btdAmount;
        uint256 wbtcPrice;
        uint256 iusdPrice;
        uint256 cr;                  // collateral ratio 1e18
        uint256 btdPrice;
        uint256 btbPrice;
        uint256 brsPrice;
        uint256 minBTBPriceInBTD;    // 18 decimals
        uint256 redeemFeeBP;         // basis points
    }

    /**
     * @notice Redemption output results structure
     * @param wbtcOutNormalized WBTC amount to return (18 decimals normalized)
     * @param btbOut BTB amount to return (18 decimals)
     * @param brsOut BRS amount to return (18 decimals)
     * @param fee Redemption fee (BTD, 18 decimals)
     */
    struct RedeemOutputs {
        uint256 wbtcOutNormalized;   // 18 decimals
        uint256 btbOut;
        uint256 brsOut;
        uint256 fee;                 // redeem fee in BTD
    }

    /**
     * @notice Evaluate redemption operation, calculate amounts of assets to return
     * @dev Redemption logic is divided into two cases:
     *
     *      Fee handling:
     *      - Fee = BTD Amount × Redemption Fee Rate
     *      - Effective Redemption Amount = BTD Amount - Fee
     *      - All asset returns are calculated based on effective redemption amount
     *
     *      Case 1: CR >= 100% (Over-collateralized)
     *      - Return equivalent WBTC
     *      - Formula: WBTC = (Effective Redemption Amount × IUSD Price / WBTC Price)
     *
     *      Case 2: CR < 100% (Under-collateralized)
     *      - WBTC Portion = Effective Redemption Value × CR
     *      - Loss Portion = Effective Redemption Value × (1 - CR)
     *
     *      Loss Compensation Mechanism:
     *      a) If BTB Price >= Minimum Price: Compensate entirely with BTB
     *         BTB Amount = Loss Value / BTB Price
     *
     *      b) If BTB Price < Minimum Price: Compensate with BTB + BRS combination
     *         BTB Amount = Loss Value / Minimum Price (calculated at minimum price)
     *         Extra Loss = Loss Value × (Minimum Price - BTB Price) / Minimum Price
     *         BRS Amount = Extra Loss / BRS Price
     *
     * @param inputs Redemption input parameters
     * @return result Redemption output results
     */
    function evaluate(RedeemInputs memory inputs) internal pure returns (RedeemOutputs memory result) {
        require(inputs.btdAmount > 0, "Invalid amount");
        require(inputs.wbtcPrice > 0 && inputs.iusdPrice > 0, "Invalid price");

        // Calculate fee (deducted from user)
        result.fee = Math.mulDiv(inputs.btdAmount, inputs.redeemFeeBP, Constants.BPS_BASE);

        // Effective redemption amount = User redemption amount - Fee
        uint256 effectiveBTDAmount = inputs.btdAmount - result.fee;

        // Calculate USD value based on effective redemption amount
        uint256 usdValue = Math.mulDiv(effectiveBTDAmount, inputs.iusdPrice, Constants.PRECISION_18);
        require(usdValue >= Constants.MIN_USD_VALUE, "Redeem value too small");

        if (inputs.cr >= Constants.PRECISION_18) {
            result.wbtcOutNormalized = Math.mulDiv(
                usdValue,
                Constants.PRECISION_18,
                inputs.wbtcPrice
            );
            return result;
        }

        require(
            inputs.minBTBPriceInBTD > 0 &&
            inputs.btdPrice > 0 &&
            inputs.btbPrice > 0,
            "Invalid secondary price"
        );

        uint256 wbtcValue = Math.mulDiv(usdValue, inputs.cr, Constants.PRECISION_18);
        result.wbtcOutNormalized = Math.mulDiv(
            wbtcValue,
            Constants.PRECISION_18,
            inputs.wbtcPrice
        );

        uint256 lossValue = usdValue > wbtcValue ? usdValue - wbtcValue : 0;
        if (lossValue == 0) {
            return result;
        }

        uint256 minPriceInUSD = Math.mulDiv(
            inputs.minBTBPriceInBTD,
            inputs.btdPrice,
            Constants.PRECISION_18
        );

        if (inputs.btbPrice >= minPriceInUSD) {
            result.btbOut = Math.mulDiv(lossValue, Constants.PRECISION_18, inputs.btbPrice);
        } else {
            result.btbOut = Math.mulDiv(lossValue, Constants.PRECISION_18, minPriceInUSD);
            require(inputs.brsPrice > 0, "Invalid BRS price");
            uint256 extraLoss = Math.mulDiv(
                lossValue,
                minPriceInUSD - inputs.btbPrice,
                minPriceInUSD
            );
            result.brsOut = Math.mulDiv(extraLoss, Constants.PRECISION_18, inputs.brsPrice);
        }
    }
}
