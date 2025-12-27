// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "./Constants.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";

/**
 * @title MintLogic - BTD Minting Logic Calculation Library
 * @notice Pure function library: Calculate mint-related results based on input state
 * @dev Encapsulates core calculation logic for BTD minting, including USD value conversion, fee calculation, etc.
 */
library MintLogic {


    /**
     * @notice Mint input parameters structure
     * @param wbtcAmount WBTC amount (8 decimals)
     * @param wbtcPrice WBTC price (18 decimals, unit: USD)
     * @param iusdPrice IUSD price (18 decimals, unit: USD)
     * @param currentBTDSupply Current BTD total supply (18 decimals)
     * @param feeBP Fee rate (basis points, 100 = 1%)
     */
    struct MintInputs {
        uint256 wbtcAmount;        // 8 decimals
        uint256 wbtcPrice;         // 18 decimals USD
        uint256 iusdPrice;         // 18 decimals USD
        uint256 currentBTDSupply;  // 18 decimals
        uint256 feeBP;             // basis points
    }

    /**
     * @notice Mint output results structure
     * @param usdValue Collateral USD value (18 decimals)
     * @param btdToMint BTD amount to mint for user (after fee deduction, 18 decimals)
     * @param fee Fee (18 decimals)
     * @param btdGross Gross mint amount (before fee, 18 decimals)
     * @param newLiabilityValue New liability USD value (18 decimals)
     * @param normalizedWBTC Normalized WBTC amount (18 decimals)
     */
    struct MintOutputs {
        uint256 usdValue;
        uint256 btdToMint;         // User actually receives (after fee)
        uint256 fee;               // Fee
        uint256 btdGross;          // Gross mint amount (before fee)
        uint256 newLiabilityValue;
        uint256 normalizedWBTC;    // 18 decimals
    }

    /**
     * @notice Evaluate mint operation, calculate all related values
     * @dev Main flow:
     *      1. Validate input parameter validity
     *      2. Convert WBTC to normalized 18 decimals
     *      3. Calculate collateral USD value
     *      4. Calculate gross BTD amount to mint based on IUSD price (before fee)
     *      5. Calculate fee (deducted from gross amount)
     *      6. Calculate actual BTD user receives (after fee)
     *      7. Calculate new liability value
     *
     *      Formulas:
     *      - Normalized WBTC = WBTC Amount × 1e10
     *      - USD Value = (Normalized WBTC × WBTC Price) / 1e18
     *      - Gross BTD = (USD Value × 1e18) / IUSD Price
     *      - Fee = (Gross BTD × Fee Rate) / 10000
     *      - User Receives = Gross BTD - Fee
     *      - New Liability Value = ((Current Supply + Gross BTD) × IUSD Price) / 1e18
     *
     * @param inputs Mint input parameters
     * @return result Mint output results
     */
    function evaluate(MintInputs memory inputs) internal pure returns (MintOutputs memory result) {
        require(inputs.wbtcAmount > 0, "Invalid amount");
        require(inputs.wbtcPrice > 0, "Invalid WBTC price");
        require(inputs.iusdPrice > 0, "Invalid IUSD price");

        result.normalizedWBTC = inputs.wbtcAmount * Constants.SCALE_WBTC_TO_NORM;
        result.usdValue = Math.mulDiv(result.normalizedWBTC, inputs.wbtcPrice, Constants.PRECISION_18);
        require(result.usdValue >= Constants.MIN_USD_VALUE, "Mint value too small");

        // Calculate gross mint amount (before fee)
        result.btdGross = Math.mulDiv(result.usdValue, Constants.PRECISION_18, inputs.iusdPrice);

        // Calculate fee
        result.fee = Math.mulDiv(result.btdGross, inputs.feeBP, Constants.BPS_BASE);

        // User actually receives = Gross - Fee
        result.btdToMint = result.btdGross - result.fee;

        // New liability based on gross mint amount (including fee)
        uint256 newBTDSupply = inputs.currentBTDSupply + result.btdGross;
        result.newLiabilityValue = Math.mulDiv(newBTDSupply, inputs.iusdPrice, Constants.PRECISION_18);
    }
}
