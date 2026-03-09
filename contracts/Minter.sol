// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.30;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {PausableUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
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
contract Minter is Initializable, Ownable2StepUpgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable, UUPSUpgradeable, IMinter {
    using SafeERC20 for IERC20;

    // ============ State Variables ============

    ConfigCore public core;
    ConfigGov public gov;

    /**
     * @notice Get ConfigCore contract address
     * @return ConfigCore contract address
     */
    function configCore() external view returns (address) {
        return address(core);
    }

    /**
     * @notice Get ConfigGov contract address
     * @return ConfigGov contract address
     */
    function configGov() external view returns (address) {
        return address(gov);
    }

    // ============ Events ============

    /// @notice ConfigGov address update event
    event ConfigGovUpdated(address indexed oldConfigGov, address indexed newConfigGov);

    // ============ Initialization ============

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize Minter
     * @dev Sets contract owner and Config addresses
     */
    function initialize(
        address initialOwner,
        address _core,
        address _gov
    ) public initializer {
        require(initialOwner != address(0), "Invalid owner");
        require(_core != address(0), "Invalid core");
        require(_gov != address(0), "Invalid gov");

        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        core = ConfigCore(_core);
        gov = ConfigGov(_gov);
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address) internal override onlyOwner {}

    // ============ Admin Functions ============

    function pause() external onlyOwner { _pause(); }

    function unpause() external onlyOwner { _unpause(); }

    /**
     * @notice Upgrade governance contract
     * @param newGov New ConfigGov contract address
     */
    function upgradeGov(address newGov) external onlyOwner {
        require(newGov != address(0), "Invalid gov");
        address oldGov = address(gov);
        gov = ConfigGov(newGov);
        emit ConfigGovUpdated(oldGov, newGov);
    }

    // ============ Precision Conversion Helpers ============

    function _wbtcToNormalized(uint256 wbtcAmount) internal pure returns (uint256) {
        return wbtcAmount * Constants.SCALE_WBTC_TO_NORM;
    }

    function _wbtcFromNormalized(uint256 normalizedAmount) internal pure returns (uint256) {
        return normalizedAmount / Constants.SCALE_WBTC_TO_NORM;
    }

    // ============ Amount Validation ============

    function _checkWBTCAmount(uint256 wbtcAmount) internal pure {
        require(wbtcAmount >= Constants.MIN_BTC_AMOUNT, "Amount below minimum BTC");
        require(wbtcAmount <= Constants.MAX_WBTC_AMOUNT, "Amount exceeds max WBTC");
    }

    function _checkStablecoinAmount(uint256 amount) internal pure {
        require(amount >= Constants.MIN_STABLECOIN_18_AMOUNT, "Amount below minimum");
        require(amount <= Constants.MAX_STABLECOIN_18_AMOUNT, "Amount exceeds max");
    }

    // ============ Price Query Functions ============

    function _getPriceOracle() internal view returns (IPriceOracle) {
        address oracle = core.PRICE_ORACLE();
        require(oracle != address(0), "PriceOracle not set");
        return IPriceOracle(oracle);
    }

    function _updateTWAPForWBTC() internal {
        _getPriceOracle().updateTWAPForWBTC();
    }

    function _updateTWAPAll() internal {
        _getPriceOracle().updateTWAPAll();
    }

    function _tryUpdateIUSD() internal {
        address manager = core.IDEAL_USD_MANAGER();
        if (manager != address(0)) {
            try IIdealUSDManager(manager).tryUpdateIUSD() {} catch {}
        }
    }

    function getWBTCPrice() internal view returns (uint256) {
        return _getPriceOracle().getWBTCPrice();
    }

    function getBTDPrice() internal view returns (uint256) {
        return _getPriceOracle().getBTDPrice();
    }

    function getBTBPrice() internal view returns (uint256) {
        return _getPriceOracle().getBTBPrice();
    }

    function getBRSPrice() internal view returns (uint256) {
        return _getPriceOracle().getBRSPrice();
    }

    function getIUSDPrice() internal view returns (uint256) {
        return _getPriceOracle().getIUSDPrice();
    }

    // ============ Collateral and Liabilities ============

    function totalWBTC() public view returns (uint256) {
        (uint256 wbtcBalance, , ) = ITreasury(core.TREASURY()).getBalances();
        return wbtcBalance;
    }

    function totalBTD() public view returns (uint256) {
        return IMintableERC20(core.BTD()).totalSupply();
    }

    function totalStBTDEquivalent() public view returns (uint256) {
        address stBTD = core.ST_BTD();
        return stBTD == address(0) ? 0 : IERC4626(stBTD).totalAssets();
    }

    function getCollateralRatio() public view override returns (uint256) {
        return CollateralMath.collateralRatio(
            totalWBTC(), getWBTCPrice(), totalBTD(), totalStBTDEquivalent(), getIUSDPrice()
        );
    }

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

    function calculateBurnAmount(uint256 btdAmount) external view override returns (uint256 wbtcAmount, uint256 fee) {
        uint256 wbtcPrice = getWBTCPrice();
        uint256 iusdPrice = getIUSDPrice();
        uint256 cr = _getCRWithPrice(wbtcPrice, iusdPrice);

        RedeemLogic.RedeemInputs memory inputs = _buildRedeemInputs(btdAmount, wbtcPrice, iusdPrice, cr);
        RedeemLogic.RedeemOutputs memory outputs = RedeemLogic.evaluate(inputs);

        return (_wbtcFromNormalized(outputs.wbtcOutNormalized), outputs.fee);
    }

    function _getCRWithPrice(uint256 wbtcPrice, uint256 iusdPrice) private view returns (uint256) {
        return CollateralMath.collateralRatio(
            totalWBTC(),
            wbtcPrice,
            totalBTD(),
            totalStBTDEquivalent(),
            iusdPrice
        );
    }

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

        if (cr < Constants.PRECISION_18) {
            inputs.btdPrice = getBTDPrice();
            inputs.btbPrice = getBTBPrice();
            inputs.brsPrice = getBRSPrice();
            inputs.minBTBPriceInBTD = gov.minBTBPrice();
        }

        return inputs;
    }

    // ============ Mint BTD ============

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

        IERC20 wbtc = IERC20(core.WBTC());
        address treasuryAddr = core.TREASURY();
        wbtc.safeTransferFrom(msg.sender, address(this), wbtcAmount);
        if (wbtc.allowance(address(this), treasuryAddr) < wbtcAmount) {
            wbtc.forceApprove(treasuryAddr, type(uint256).max);
        }
        ITreasury(treasuryAddr).depositWBTC(wbtcAmount);

        IMintableERC20 btdToken = IMintableERC20(core.BTD());
        btdToken.mint(msg.sender, outputs.btdToMint);
        if (outputs.fee > 0) {
            btdToken.mint(treasuryAddr, outputs.fee);
        }

        emit BTDMinted(msg.sender, wbtcAmount, outputs.btdToMint, outputs.fee);
    }

    // ============ Redeem BTD ============

    function redeemBTD(uint256 btdAmount) external nonReentrant whenNotPaused {
        _redeemBTD(msg.sender, btdAmount);
    }

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

        IMintableERC20(core.BTD()).burnFrom(account, btdAmount);
        if (outputs.fee > 0) {
            IMintableERC20(core.BTD()).mint(core.TREASURY(), outputs.fee);
        }

        uint256 wbtcOut = _wbtcFromNormalized(outputs.wbtcOutNormalized);
        if (wbtcOut > 0) {
            _checkWBTCAmount(wbtcOut);
            ITreasury(core.TREASURY()).withdrawWBTC(wbtcOut);
            IERC20(core.WBTC()).safeTransfer(account, wbtcOut);
        }

        if (outputs.brsOut > 0) {
            ITreasury(core.TREASURY()).compensate(account, outputs.brsOut);
        }
        if (outputs.btbOut > 0) {
            IMintableERC20(core.BTB()).mint(account, outputs.btbOut);
        }

        emit BTDRedeemed(account, btdAmount, wbtcOut, outputs.btbOut, outputs.brsOut);
    }

    // ============ Redeem BTB ============

    function redeemBTB(uint256 btbAmount) external nonReentrant whenNotPaused {
        _validateRedeemBTBRequest(msg.sender, btbAmount);
        _redeemBTB(msg.sender, btbAmount);
    }

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

    function _validateRedeemBTBRequest(address account, uint256 btbAmount) internal view {
        _checkStablecoinAmount(btbAmount);
        require(IMintableERC20(core.BTB()).balanceOf(account) >= btbAmount, "Not enough BTB");
    }

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

        IMintableERC20(core.BTB()).burnFrom(account, btbAmount);
        IMintableERC20(core.BTD()).mint(account, btbAmount);

        emit BTBRedeemed(account, btbAmount, btbAmount);
    }

    // ============ System State Queries ============

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

    // ============ Storage Gap ============

    uint256[50] private __gap;
}
