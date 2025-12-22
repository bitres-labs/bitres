// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/utils/math/Math.sol";
import "./Constants.sol";

/**
 * @title CollateralMath - Collateral Value and Liability Calculation Library
 * @notice Pure function library for centralized management of collateral value, liability, and quota calculations
 * @dev Provides calculation functions for core financial metrics such as collateral ratio and redeemable quota
 */
library CollateralMath {

    /**
     * @notice Calculate the USD value of collateral
     * @dev Formula: Value = (WBTC Balance × WBTC Price) / 1e8
     * @param wbtcBalance WBTC balance (8 decimals)
     * @param wbtcPrice WBTC price (18 decimals, unit: USD)
     * @return Collateral USD value (18 decimals)
     */
    function collateralValue(uint256 wbtcBalance, uint256 wbtcPrice) internal pure returns (uint256) {
        if (wbtcBalance == 0 || wbtcPrice == 0) {
            return 0;
        }
        return Math.mulDiv(wbtcBalance, wbtcPrice, Constants.PRECISION_8);
    }

    /**
     * @notice Calculate the USD value of liability
     * @dev Formula: Value = (Total BTD Equivalent × IUSD Price) / 1e18
     *      Total BTD Equivalent = BTD Supply + stBTD converted to BTD amount
     * @param btdSupply BTD total supply (18 decimals)
     * @param stBTDEquivalent stBTD converted to BTD amount (18 decimals)
     * @param iusdPrice IUSD price (18 decimals, unit: USD)
     * @return Liability USD value (18 decimals)
     */
    function liabilityValue(uint256 btdSupply, uint256 stBTDEquivalent, uint256 iusdPrice) internal pure returns (uint256) {
        uint256 totalBTD = btdSupply + stBTDEquivalent;
        if (totalBTD == 0 || iusdPrice == 0) {
            return 0;
        }
        return Math.mulDiv(totalBTD, iusdPrice, Constants.PRECISION_18);
    }

    /**
     * @notice Calculate Collateral Ratio (CR)
     * @dev Formula: CR = (Collateral Value / Liability Value) × 1e18
     *      Total BTD Equivalent = BTD Supply + stBTD converted to BTD amount
     *      - CR = 1e18 (100%) indicates fully collateralized
     *      - CR > 1e18 indicates over-collateralized
     *      - CR < 1e18 indicates under-collateralized
     *      - Returns 1e18 when position is empty
     * @param wbtcBalance WBTC balance (8 decimals)
     * @param wbtcPrice WBTC price (18 decimals)
     * @param btdSupply BTD total supply (18 decimals)
     * @param stBTDEquivalent stBTD converted to BTD amount (18 decimals)
     * @param iusdPrice IUSD price (18 decimals)
     * @return Collateral ratio (18 decimals, 1e18 = 100%)
     */
    function collateralRatio(
        uint256 wbtcBalance,
        uint256 wbtcPrice,
        uint256 btdSupply,
        uint256 stBTDEquivalent,
        uint256 iusdPrice
    ) internal pure returns (uint256) {
        uint256 totalBTD = btdSupply + stBTDEquivalent;
        if (wbtcBalance == 0 || totalBTD == 0) {
            return Constants.PRECISION_18;
        }

        uint256 colValue = collateralValue(wbtcBalance, wbtcPrice);
        uint256 liabValue = liabilityValue(btdSupply, stBTDEquivalent, iusdPrice);
        require(colValue >= Constants.MIN_USD_VALUE, "Collateral value too small");
        require(liabValue >= Constants.MIN_USD_VALUE, "Liability value too small");
        return Math.mulDiv(colValue, Constants.PRECISION_18, liabValue);
    }

    /**
     * @notice Calculate maximum redeemable USD value
     * @dev Formula: Max Redeemable = max(Collateral Value - Liability Value, 0)
     *      - Only has redemption capacity when over-collateralized
     *      - Returns 0 when under-collateralized
     * @param collateralValue_ Collateral USD value (18 decimals)
     * @param liabilityValue_ Liability USD value (18 decimals)
     * @return Maximum redeemable USD value (18 decimals)
     */
    function maxRedeemableUSD(uint256 collateralValue_, uint256 liabilityValue_) internal pure returns (uint256) {
        return collateralValue_ > liabilityValue_ ? collateralValue_ - liabilityValue_ : 0;
    }

    /**
     * @notice Calculate maximum redeemable BTD amount
     * @dev Formula: Max Redeemable BTD = (Max Redeemable USD × 1e18) / IUSD Price
     *      - First calculate USD value redemption capacity
     *      - Then convert to BTD amount
     * @param collateralValue_ Collateral USD value (18 decimals)
     * @param liabilityValue_ Liability USD value (18 decimals)
     * @param iusdPrice IUSD price (18 decimals)
     * @return Maximum redeemable BTD amount (18 decimals)
     */
    function maxRedeemableBTD(
        uint256 collateralValue_,
        uint256 liabilityValue_,
        uint256 iusdPrice
    ) internal pure returns (uint256) {
        uint256 usd = maxRedeemableUSD(collateralValue_, liabilityValue_);
        if (usd == 0 || iusdPrice == 0) {
            return 0;
        }
        return Math.mulDiv(usd, Constants.PRECISION_18, iusdPrice);
    }
}
