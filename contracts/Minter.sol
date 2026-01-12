// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC20Permit} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Permit.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "./ConfigCore.sol";
import "./ConfigGov.sol";
import "./interfaces/ITreasury.sol";
import "./interfaces/IMintableERC20.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IMinter.sol";
import "./interfaces/IIdealUSDManager.sol";
import "./libraries/Constants.sol";
import "./libraries/MintLogic.sol";
import "./libraries/RedeemLogic.sol";
import "./libraries/CollateralMath.sol";

/**
 * @title Minter - BTD Stablecoin Minting and Redemption Contract
 * @notice Handles BTD minting and redemption business logic
 * @dev Price queries delegated to PriceOracle contract, this contract focuses on business logic
 */
contract Minter is ReentrancyGuard, Ownable2Step, Pausable, IMinter {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    ConfigCore public immutable core;
    ConfigGov public gov; // Global config contract - internal to maintain storage layout

    /**
     * @notice Get ConfigCore contract address
     * @dev ConfigCore is immutable, cannot be changed after deployment
     * @return ConfigCore contract address
     */
    function configCore() external view returns (address) {
        return address(core);
    }

    /**
     * @notice Get ConfigGov contract address
     * @dev ConfigGov can be updated via setConfigGov()
     * @return ConfigGov contract address
     */
    function configGov() external view returns (address) {
        return address(gov);
    }

    // ============ Events ============

    /// @notice ConfigGov address update event
    /// @param oldConfigGov Old ConfigGov address
    /// @param newConfigGov New ConfigGov address
    event ConfigGovUpdated(address indexed oldConfigGov, address indexed newConfigGov);

    // ============ Initialization ============

    /**
     * @notice Constructor
     * @dev Initializes contract owner and Config addresses, both cannot be zero address
     */
    constructor(
        address initialOwner,  // Contract owner address
        address _core, address _gov     // Config contract addresses
    ) Ownable(initialOwner) {
        require(initialOwner != address(0), "Invalid owner");
        require(_core != address(0), "Invalid core");
        require(_gov != address(0), "Invalid gov");
        core = ConfigCore(_core);
        gov = ConfigGov(_gov);
    }

    // ============ Admin Functions ============

    /**
     * @notice Pause all write operations
     * @dev Only owner can call, after pause all nonReentrant whenNotPaused functions will be blocked
     */
    function pause() external onlyOwner { _pause(); }

    function unpause() external onlyOwner { _unpause(); }

    /**
     * @notice Upgrade governance contract
     * @dev Only owner can call, core address ConfigCore cannot be changed
     * @dev ConfigCore is immutable, never changeable after deployment
     * @dev ConfigGov is upgradeable for adjusting governable parameters (fees, limits, etc.)
     * @param newGov New ConfigGov contract address
     */
    function upgradeGov(address newGov) external onlyOwner {
        require(newGov != address(0), "Invalid gov");
        address oldGov = address(gov);
        gov = ConfigGov(newGov);
        emit ConfigGovUpdated(oldGov, newGov);
    }

    // ============ Precision Conversion Helpers ============

    /// @notice Convert WBTC (8 decimals) to normalized (18 decimals)
    function _wbtcToNormalized(uint256 wbtcAmount) internal pure returns (uint256) {
        return wbtcAmount * Constants.SCALE_WBTC_TO_NORM;
    }

    /// @notice Convert normalized (18 decimals) to WBTC (8 decimals)
    function _wbtcFromNormalized(uint256 normalizedAmount) internal pure returns (uint256) {
        return normalizedAmount / Constants.SCALE_WBTC_TO_NORM;
    }

    // ============ Amount Validation ============

    /// @notice Validate WBTC amount within safe bounds (1 satoshi to 10,000 BTC)
    function _checkWBTCAmount(uint256 wbtcAmount) internal pure {
        require(wbtcAmount >= Constants.MIN_BTC_AMOUNT, "Amount below minimum BTC");
        require(wbtcAmount <= Constants.MAX_WBTC_AMOUNT, "Amount exceeds max WBTC");
    }

    /// @notice Validate stablecoin amount within safe bounds (0.001 to 1 billion)
    function _checkStablecoinAmount(uint256 amount) internal pure {
        require(amount >= Constants.MIN_STABLECOIN_18_AMOUNT, "Amount below minimum");
        require(amount <= Constants.MAX_STABLECOIN_18_AMOUNT, "Amount exceeds max");
    }

    // ============ Price Query Functions ============

    /**
     * @notice Get price oracle contract
     * @return PriceOracle contract instance
     */
    function _getPriceOracle() internal view returns (IPriceOracle) {
        address oracle = core.PRICE_ORACLE();
        require(oracle != address(0), "PriceOracle not set");
        return IPriceOracle(oracle);
    }

    /// @notice Update TWAP for WBTC price if needed
    function _updateTWAPForWBTC() internal {
        _getPriceOracle().updateTWAPForWBTC();
    }

    /// @notice Update TWAP for all prices if needed
    function _updateTWAPAll() internal {
        _getPriceOracle().updateTWAPAll();
    }

    /// @notice Try to update IUSD if enough time has passed (lazy update, silently fails if unavailable)
    function _tryUpdateIUSD() internal {
        address manager = core.IDEAL_USD_MANAGER();
        if (manager != address(0)) {
            try IIdealUSDManager(manager).tryUpdateIUSD() {} catch {}
        }
    }

    /// @notice Get WBTC/USD price from oracle (18 decimals)
    function getWBTCPrice() internal view returns (uint256) {
        return _getPriceOracle().getWBTCPrice();
    }

    /// @notice Get BTD/USD market price from oracle (18 decimals)
    function getBTDPrice() internal view returns (uint256) {
        return _getPriceOracle().getBTDPrice();
    }

    /// @notice Get BTB/USD price from oracle (18 decimals)
    function getBTBPrice() internal view returns (uint256) {
        return _getPriceOracle().getBTBPrice();
    }

    /// @notice Get BRS/USD price from oracle (18 decimals)
    function getBRSPrice() internal view returns (uint256) {
        return _getPriceOracle().getBRSPrice();
    }

    /// @notice Get IUSD (inflation-adjusted USD) price from oracle (18 decimals)
    function getIUSDPrice() internal view returns (uint256) {
        return _getPriceOracle().getIUSDPrice();
    }

    // ============ Collateral and Liabilities ============

    /// @notice Get WBTC balance in Treasury (8 decimals)
    function totalWBTC() public view returns (uint256) {
        (uint256 wbtcBalance, , ) = ITreasury(core.TREASURY()).getBalances();
        return wbtcBalance;
    }

    /// @notice Get BTD total supply (18 decimals)
    function totalBTD() public view returns (uint256) {
        return IMintableERC20(core.BTD()).totalSupply();
    }

    /// @notice Get BTD equivalent from stBTD vault (18 decimals)
    function totalStBTDEquivalent() public view returns (uint256) {
        address stBTD = core.ST_BTD();
        return stBTD == address(0) ? 0 : IERC4626(stBTD).totalAssets();
    }

    /**
     * @notice Get system Collateral Ratio (1e18 = 100%)
     * @dev CR = (WBTC value) / (BTD + stBTD equivalent) * IUSD price
     */
    function getCollateralRatio() public view override returns (uint256) {
        return CollateralMath.collateralRatio(
            totalWBTC(), getWBTCPrice(), totalBTD(), totalStBTDEquivalent(), getIUSDPrice()
        );
    }

    /**
     * @notice Calculate BTD output amount and fee when minting (read-only preview)
     * @dev Uses MintLogic library, does not modify state, can be used for frontend preview
     * @param wbtcAmount WBTC amount to deposit (8 decimals)
     * @return btdAmount BTD amount user will receive (after fee, 18 decimals)
     * @return fee Minting fee (BTD, 18 decimals), deducted from user
     */
    function calculateMintAmount(uint256 wbtcAmount) external view override returns (uint256 btdAmount, uint256 fee) {
        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: getWBTCPrice(),
            iusdPrice: getIUSDPrice(),
            currentBTDSupply: totalBTD(),
            feeBP: gov.mintFeeBP()
        });
        MintLogic.MintOutputs memory outputs = MintLogic.evaluate(inputs);
        return (outputs.btdToMint, outputs.fee);
    }

    /**
     * @notice Calculate output amount and fee when redeeming BTD (read-only preview)
     * @dev Calculates WBTC output and redemption fee based on BTD amount and current prices
     * @param btdAmount BTD amount to burn (18 decimals)
     * @return wbtcAmount WBTC amount user will receive (8 decimals)
     * @return fee Redemption fee (BTD, 18 decimals), deducted from user
     */
    function calculateBurnAmount(uint256 btdAmount) external view override returns (uint256 wbtcAmount, uint256 fee) {
        uint256 wbtcPrice = getWBTCPrice();
        uint256 iusdPrice = getIUSDPrice();
        uint256 cr = _getCRWithPrice(wbtcPrice, iusdPrice);

        RedeemLogic.RedeemInputs memory inputs = _buildRedeemInputs(btdAmount, wbtcPrice, iusdPrice, cr);
        RedeemLogic.RedeemOutputs memory outputs = RedeemLogic.evaluate(inputs);

        return (_wbtcFromNormalized(outputs.wbtcOutNormalized), outputs.fee);
    }

    /**
     * @notice Calculate CR with pre-fetched prices (gas optimization)
     * @dev Avoids repeated oracle calls
     */
    function _getCRWithPrice(uint256 wbtcPrice, uint256 iusdPrice) private view returns (uint256) {
        return CollateralMath.collateralRatio(
            totalWBTC(),
            wbtcPrice,
            totalBTD(),
            totalStBTDEquivalent(),
            iusdPrice
        );
    }

    /**
     * @notice Build RedeemInputs struct with current prices
     * @dev Consolidates common redemption input preparation logic
     * @param btdAmount BTD amount to redeem (18 decimals)
     * @param wbtcPrice Current WBTC price (18 decimals)
     * @param iusdPrice Current IUSD price (18 decimals)
     * @param cr Current collateral ratio (18 decimals)
     * @return Populated RedeemInputs struct
     */
    function _buildRedeemInputs(
        uint256 btdAmount,
        uint256 wbtcPrice,
        uint256 iusdPrice,
        uint256 cr
    ) private view returns (RedeemLogic.RedeemInputs memory) {
        RedeemLogic.RedeemInputs memory inputs = RedeemLogic.RedeemInputs({
            btdAmount: btdAmount,
            wbtcPrice: wbtcPrice,
            iusdPrice: iusdPrice,
            cr: cr,
            btdPrice: 0,
            btbPrice: 0,
            brsPrice: 0,
            minBTBPriceInBTD: 0,
            redeemFeeBP: gov.redeemFeeBP()
        });

        // Only fetch additional prices when undercollateralized
        if (cr < Constants.PRECISION_18) {
            inputs.btdPrice = getBTDPrice();
            inputs.btbPrice = getBTBPrice();
            inputs.brsPrice = getBRSPrice();
            inputs.minBTBPriceInBTD = gov.minBTBPrice();
        }

        return inputs;
    }

    // ============ Mint BTD ============

    /**
     * @notice Deposit WBTC to mint BTD
     * @dev User must approve Minter first. Flow: User -> Minter -> Treasury
     * @param wbtcAmount WBTC amount to deposit (8 decimals)
     */
    function mintBTD(uint256 wbtcAmount) external nonReentrant whenNotPaused {
        _updateTWAPForWBTC();
        _tryUpdateIUSD();
        _checkWBTCAmount(wbtcAmount);

        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: getWBTCPrice(),
            iusdPrice: getIUSDPrice(),
            currentBTDSupply: totalBTD(),
            feeBP: gov.mintFeeBP()
        });
        MintLogic.MintOutputs memory outputs = MintLogic.evaluate(inputs);

        // Transfer WBTC: User -> Minter -> Treasury
        IERC20 wbtc = IERC20(core.WBTC());
        address treasuryAddr = core.TREASURY();
        wbtc.safeTransferFrom(msg.sender, address(this), wbtcAmount);
        if (wbtc.allowance(address(this), treasuryAddr) < wbtcAmount) {
            wbtc.forceApprove(treasuryAddr, type(uint256).max);
        }
        ITreasury(treasuryAddr).depositWBTC(wbtcAmount);

        // Mint BTD: user receives net amount, Treasury receives fee
        IMintableERC20 btdToken = IMintableERC20(core.BTD());
        btdToken.mint(msg.sender, outputs.btdToMint);
        if (outputs.fee > 0) {
            btdToken.mint(treasuryAddr, outputs.fee);
        }

        emit BTDMinted(msg.sender, wbtcAmount, outputs.btdToMint, outputs.fee);
    }

    // ============ Redeem BTD ============

    /**
     * @notice Redeem BTD for WBTC
     * @dev CR>=100%: all WBTC; CR<100%: partial WBTC + BTB + BRS compensation
     * @dev Security: reentrancy guard, pause protection, amount limit checks
     * @param btdAmount BTD amount to burn (18 decimals)
     */
    function redeemBTD(uint256 btdAmount) external nonReentrant whenNotPaused {
        _redeemBTD(msg.sender, btdAmount);
    }

    /**
     * @notice Redeem BTD using EIP-2612 permit signature (no pre-approval needed)
     * @dev User signs authorization for one-tx redemption, CR<100% gets BTB/BRS compensation
     * @dev Security: reentrancy guard, pause protection, amount limit checks, signature validation
     * @param btdAmount BTD amount to burn (18 decimals)
     * @param deadline Permit signature deadline timestamp (seconds)
     * @param v ECDSA signature parameter v (27 or 28)
     * @param r ECDSA signature parameter r (32 bytes)
     * @param s ECDSA signature parameter s (32 bytes)
     */
    function redeemBTDWithPermit(
        uint256 btdAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused {
        IERC20Permit(core.BTD()).permit(
            msg.sender,
            address(this),
            btdAmount,
            deadline,
            v,
            r,
            s
        );

        _redeemBTD(msg.sender, btdAmount);
    }

    /**
     * @notice Internal BTD redemption implementation
     * @dev Decides redemption method based on CR: CR>=100% all WBTC, CR<100% mixed compensation
     * @param account Redeemer address
     * @param btdAmount BTD amount to burn (18 decimals)
     */
    function _redeemBTD(address account, uint256 btdAmount) internal {
        _updateTWAPAll();
        _tryUpdateIUSD();

        require(btdAmount > 0, "Invalid amount");
        require(IMintableERC20(core.BTD()).balanceOf(account) >= btdAmount, "Not enough BTD");
        _checkStablecoinAmount(btdAmount);

        uint256 wbtcPrice = getWBTCPrice();
        uint256 iusdPrice = getIUSDPrice();
        uint256 cr = _getCRWithPrice(wbtcPrice, iusdPrice);

        RedeemLogic.RedeemInputs memory inputs = _buildRedeemInputs(btdAmount, wbtcPrice, iusdPrice, cr);
        RedeemLogic.RedeemOutputs memory outputs = RedeemLogic.evaluate(inputs);

        // Burn user's BTD, mint fee to Treasury if applicable
        IMintableERC20(core.BTD()).burnFrom(account, btdAmount);
        if (outputs.fee > 0) {
            IMintableERC20(core.BTD()).mint(core.TREASURY(), outputs.fee);
        }

        // Transfer WBTC to user
        uint256 wbtcOut = _wbtcFromNormalized(outputs.wbtcOutNormalized);
        if (wbtcOut > 0) {
            _checkWBTCAmount(wbtcOut);
            ITreasury(core.TREASURY()).withdrawWBTC(wbtcOut);
            IERC20(core.WBTC()).safeTransfer(account, wbtcOut);
        }

        // Compensate with BRS/BTB when undercollateralized
        if (outputs.brsOut > 0) {
            ITreasury(core.TREASURY()).compensate(account, outputs.brsOut);
        }
        if (outputs.btbOut > 0) {
            IMintableERC20(core.BTB()).mint(account, outputs.btbOut);
        }

        emit BTDRedeemed(account, btdAmount, wbtcOut, outputs.btbOut, outputs.brsOut);
    }

    // ============ Redeem BTB ============

    /**
     * @notice Redeem BTB for BTD
     * @dev Only allowed when CR>=100%, burns BTB and mints equal BTD
     * @dev Security: reentrancy guard, pause protection, CR check, max redeemable check
     * @param btbAmount BTB amount to burn (18 decimals)
     */
    function redeemBTB(uint256 btbAmount) external nonReentrant whenNotPaused {
        _validateRedeemBTBRequest(msg.sender, btbAmount);
        _redeemBTB(msg.sender, btbAmount);
    }

    /**
     * @notice Redeem BTB using EIP-2612 permit signature (no pre-approval needed)
     * @dev User signs for one-tx BTB redemption, only available when CR>=100%
     * @dev Security: reentrancy guard, pause protection, CR check, signature validation
     * @param btbAmount BTB amount to burn (18 decimals)
     * @param deadline Permit signature deadline timestamp (seconds)
     * @param v ECDSA signature parameter v (27 or 28)
     * @param r ECDSA signature parameter r (32 bytes)
     * @param s ECDSA signature parameter s (32 bytes)
     */
    function redeemBTBWithPermit(
        uint256 btbAmount,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused {
        _validateRedeemBTBRequest(msg.sender, btbAmount);

        IERC20Permit(core.BTB()).permit(
            msg.sender,
            address(this),
            btbAmount,
            deadline,
            v,
            r,
            s
        );

        _redeemBTB(msg.sender, btbAmount);
    }

    /**
     * @notice Validate BTB redemption request
     * @dev Checks amount range and user balance
     */
    function _validateRedeemBTBRequest(address account, uint256 btbAmount) internal view {
        _checkStablecoinAmount(btbAmount);
        require(IMintableERC20(core.BTB()).balanceOf(account) >= btbAmount, "Not enough BTB");
    }

    /**
     * @notice Internal BTB redemption implementation
     * @dev Requires CR>=100%, burns BTB and mints equal BTD
     */
    function _redeemBTB(address account, uint256 btbAmount) internal {
        _updateTWAPForWBTC();
        _tryUpdateIUSD();

        uint256 wbtcPrice = getWBTCPrice();
        uint256 iusdPrice = getIUSDPrice();
        uint256 cr = _getCRWithPrice(wbtcPrice, iusdPrice);
        require(cr >= Constants.PRECISION_18, "CR<100%, BTB not redeemable");

        uint256 collateralValue = CollateralMath.collateralValue(totalWBTC(), wbtcPrice);
        uint256 liabilityValue = CollateralMath.liabilityValue(totalBTD(), totalStBTDEquivalent(), iusdPrice);
        uint256 maxRedeemableBTD = CollateralMath.maxRedeemableBTD(collateralValue, liabilityValue, iusdPrice);
        require(btbAmount <= maxRedeemableBTD, "Exceeds max redeemable");

        // Burn BTB, mint equal BTD
        IMintableERC20(core.BTB()).burnFrom(account, btbAmount);
        IMintableERC20(core.BTD()).mint(account, btbAmount);

        emit BTBRedeemed(account, btbAmount, btbAmount);
    }

    // ============ System State Queries ============

    /**
     * @notice Get overall system status information
     * @dev Returns all key metrics at once for frontend display
     */
    function getSystemInfo()
        external
        view
        returns (
            uint256 _totalBTD,
            uint256 _totalWBTC,
            uint256 _collateralRatio,
            uint256 _wbtcPrice,
            uint256 _btbPrice,
            uint256 _brsPrice
        )
    {
        return (totalBTD(), totalWBTC(), getCollateralRatio(), getWBTCPrice(), getBTBPrice(), getBRSPrice());
    }
}
