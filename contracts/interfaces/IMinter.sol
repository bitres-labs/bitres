// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title IMinter - Standard interface for Minter contract
 * @notice Defines the core functionality interface for the Minter contract
 */
interface IMinter {
    // --- Minting Operations ---
    /**
     * @notice Mint BTD stablecoin using WBTC
     * @param wbtcAmount Amount of WBTC
     */
    function mintBTD(uint256 wbtcAmount) external;

    // --- Redemption Operations ---
    /**
     * @notice Redeem BTD to receive WBTC, BTB, and BRS based on collateral ratio
     * @param btdAmount Amount of BTD to redeem
     */
    function redeemBTD(uint256 btdAmount) external;

    /**
     * @notice Exchange BTB for BTD at 1:1 ratio (requires CR>100%)
     * @param btbAmount Amount of BTB to exchange
     */
    function redeemBTB(uint256 btbAmount) external;

    // --- Query Functions ---
    // Note: getBTDPrice() and getBTBPrice() have been removed, please call PriceOracle.getBTDPrice() and getBTBPrice() directly

    /**
     * @notice Get system collateral ratio
     * @return Collateral ratio, 18 decimal precision (e.g., 1.5e18 represents 150%)
     */
    function getCollateralRatio() external view returns (uint256);

    /**
     * @notice Get ConfigCore contract address
     * @dev ConfigCore is immutable, cannot be changed after deployment
     * @return ConfigCore contract address
     */
    function configCore() external view returns (address);

    /**
     * @notice Get ConfigGov contract address
     * @dev ConfigGov can be updated via upgradeGov()
     * @return ConfigGov contract address
     */
    function configGov() external view returns (address);

    // --- Calculation Functions ---
    /**
     * @notice Calculate BTD mint amount and fee (without executing actual mint)
     * @param wbtcAmount Input WBTC amount, 8 decimal precision
     * @return btdAmount Mintable BTD amount, 18 decimal precision
     * @return fee Minting fee (denominated in BTD), 18 decimal precision
     */
    function calculateMintAmount(uint256 wbtcAmount) external view returns (uint256 btdAmount, uint256 fee);

    /**
     * @notice Calculate WBTC amount and fee when redeeming BTD (without executing actual redemption)
     * @param btdAmount Input BTD amount, 18 decimal precision
     * @return wbtcAmount Redeemable WBTC amount, 8 decimal precision
     * @return fee Redemption fee (denominated in WBTC), 8 decimal precision
     */
    function calculateBurnAmount(uint256 btdAmount) external view returns (uint256 wbtcAmount, uint256 fee);

    // --- Events ---
    event BTDMinted(address indexed user, uint256 wbtcAmount, uint256 btdAmount, uint256 fee);
    event BTDRedeemed(
        address indexed user,
        uint256 btdAmount,
        uint256 wbtcAmount,
        uint256 btbAmount,
        uint256 brsAmount
    );
    event BTBRedeemed(address indexed user, uint256 btbAmount, uint256 btdAmount);
}
