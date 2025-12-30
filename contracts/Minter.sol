// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.4.0
pragma solidity ^0.8.30;

import "@openzeppelin/contracts/access/Ownable.sol";
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
contract Minter is ReentrancyGuard, Ownable, Pausable, IMinter {
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

    // ============ Rate Limiting ============

    // ============ Constants ============

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

    // ============ Price Queries (delegated to PriceOracle) ============

    // ============ Precision Conversion Helpers ============

    /**
     * @notice Convert WBTC amount (8 decimals) to normalized amount (18 decimals)
     * @dev Uses precomputed constant, ~8 gas (vs Math.mulDiv's 250 gas)
     * @param wbtcAmount WBTC amount (8 decimals)
     * @return Normalized amount (18 decimals)
     */
    function _wbtcToNormalized(uint256 wbtcAmount) internal pure returns (uint256) {
        return wbtcAmount * Constants.SCALE_WBTC_TO_NORM;
    }

    /**
     * @notice Convert normalized amount (18 decimals) back to WBTC amount (8 decimals)
     * @dev Uses precomputed constant, ~8 gas
     * @param normalizedAmount Normalized amount (18 decimals)
     * @return WBTC amount (8 decimals)
     */
    function _wbtcFromNormalized(uint256 normalizedAmount) internal pure returns (uint256) {
        return normalizedAmount / Constants.SCALE_WBTC_TO_NORM;
    }


    // ============ Max Value Limit Checks ============

    /**
     * @notice Check WBTC operation amount limits (anti-hack protection)
     * @dev Validates WBTC amount within safe range: min 154 satoshi, max 10,000 BTC
     * @param wbtcAmount WBTC amount (8 decimals)
     */
    function _checkWBTCAmount(uint256 wbtcAmount) internal pure {
        require(wbtcAmount >= Constants.MIN_BTC_AMOUNT, "Amount below minimum BTC");
        require(wbtcAmount <= Constants.MAX_WBTC_AMOUNT, "Amount exceeds max WBTC");
    }

    /**
     * @notice Check BTD/BTB 18-decimal stablecoin operation amount limits (anti-hack protection)
     * @dev Validates amount within safe range: min 0.001 token, max 1 billion tokens
     * @param amount Stablecoin amount (18 decimals)
     */
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

    /**
     * @notice Update TWAP for WBTC price if needed
     * @dev Ensures TWAP is fresh before querying price
     */
    function _updateTWAPForWBTC() internal {
        _getPriceOracle().updateTWAPForWBTC();
    }

    /**
     * @notice Update TWAP for all prices if needed
     * @dev Ensures all TWAPs are fresh before querying prices
     */
    function _updateTWAPAll() internal {
        _getPriceOracle().updateTWAPAll();
    }

    /**
     * @notice Try to update IUSD if enough time has passed (lazy update)
     * @dev Called during mint/redeem operations to keep IUSD fresh
     * @dev Silently fails if update conditions not met or PCE feed unavailable
     */
    function _tryUpdateIUSD() internal {
        address manager = core.IDEAL_USD_MANAGER();
        if (manager != address(0)) {
            try IIdealUSDManager(manager).tryUpdateIUSD() {} catch {}
        }
    }

    /**
     * @notice Get WBTC/USD price (internal use)
     * @dev Queries from PriceOracle contract, price in 18-decimal USD
     * @dev For external calls use priceOracle.getWBTCPrice() directly
     * @return WBTC price (18-decimal USD)
     */
    function getWBTCPrice() internal view returns (uint256) {
        return _getPriceOracle().getWBTCPrice();
    }

    /**
     * @notice Get BTD/USD actual market price (internal use)
     * @dev Queries Uniswap market price from PriceOracle contract, price in 18-decimal USD
     * @dev For external calls use priceOracle.getBTDPrice() directly
     * @return BTD price (18-decimal USD)
     */
    function getBTDPrice() internal view returns (uint256) {
        return _getPriceOracle().getBTDPrice();
    }

    /**
     * @notice Get BTB/USD price (internal use)
     * @dev Queries from PriceOracle, calculated via BTB/BTD and BTD/USDC pools, price in 18-decimal USD
     * @dev For external calls use priceOracle.getBTBPrice() directly
     * @return BTB price (18-decimal USD)
     */
    function getBTBPrice() internal view returns (uint256) {
        return _getPriceOracle().getBTBPrice();
    }

    /**
     * @notice Get BRS/USD price (internal use)
     * @dev Queries from PriceOracle, calculated via BRS/BTD and BTD/USDC pools, price in 18-decimal USD
     * @dev For external calls use priceOracle.getBRSPrice() directly
     * @return BRS price (18-decimal USD)
     */
    function getBRSPrice() internal view returns (uint256) {
        return _getPriceOracle().getBRSPrice();
    }

    /**
     * @notice Get IUSD (Ideal USD) price (internal use)
     * @dev Queries from IdealUSDManager contract, IUSD adjusts with inflation, price in 18 decimals
     * @dev For external calls use priceOracle.getIUSDPrice() directly
     * @return IUSD price (18 decimals)
     */
    function getIUSDPrice() internal view returns (uint256) {
        return _getPriceOracle().getIUSDPrice();
    }

    // ============ Collateral and Liabilities ============

    /**
     * @notice Get WBTC balance in Treasury contract
     * @dev Queries actual WBTC holdings in Treasury, 8 decimals
     * @return WBTC balance (8 decimals)
     */
    function totalWBTC() public view returns (uint256) {
        (uint256 wbtcBalance, , ) = ITreasury(core.TREASURY())
            .getBalances();
        return wbtcBalance;
    }

    /**
     * @notice Get BTD token total supply
     * @dev Queries BTD contract totalSupply, 18 decimals
     * @return BTD total supply (18 decimals)
     */
    function totalBTD() public view returns (uint256) {
        return IMintableERC20(core.BTD()).totalSupply();
    }

    /**
     * @notice Get BTD equivalent amount from stBTD
     * @dev Uses ERC4626 totalAssets() to get total BTD locked in stBTD pool
     * @return stBTD equivalent BTD amount (18 decimals)
     */
    function totalStBTDEquivalent() public view returns (uint256) {
        address stBTD = core.ST_BTD();
        if (stBTD == address(0)) {
            return 0;
        }
        // ERC4626 totalAssets() returns underlying assets locked in pool
        return IERC4626(stBTD).totalAssets();
    }

    /**
     * @notice Get system Collateral Ratio
     * @dev CR = (WBTC amount * WBTC price) / (BTD equivalent total * IUSD price), 18 decimals
     *      BTD equivalent total = BTD supply + stBTD equivalent BTD amount
     *      CR=100% equals 1e18, CR>100% means overcollateralized, CR<100% means undercollateralized
     * @return Collateral ratio (18 decimals, 1e18=100%)
     */
    function getCollateralRatio() public view override returns (uint256) {
        return CollateralMath.collateralRatio(
            totalWBTC(),
            getWBTCPrice(),
            totalBTD(),
            totalStBTDEquivalent(),
            getIUSDPrice()
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

        RedeemLogic.RedeemInputs memory redeemInputs = RedeemLogic.RedeemInputs({
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
            redeemInputs.btdPrice = getBTDPrice();
            redeemInputs.btbPrice = getBTBPrice();
            redeemInputs.brsPrice = getBRSPrice();
            redeemInputs.minBTBPriceInBTD = gov.minBTBPrice();
        }

        RedeemLogic.RedeemOutputs memory redeemOutputs = RedeemLogic.evaluate(redeemInputs);
        wbtcAmount = _wbtcFromNormalized(redeemOutputs.wbtcOutNormalized);
        fee = redeemOutputs.fee;
        return (wbtcAmount, fee);
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

    // ============ Mint BTD ============

    /**
     * @notice Deposit WBTC to mint BTD
     * @dev User must approve Minter first, flow: User->Minter->Treasury, mints BTD and fee
     * @dev Security: reentrancy guard, pause protection, amount limit checks
     * @param wbtcAmount WBTC amount to deposit (8 decimals)
     */
    function mintBTD(uint256 wbtcAmount) external nonReentrant whenNotPaused {
        // Update TWAP for WBTC price (only if needed, saves gas if recently updated)
        _updateTWAPForWBTC();
        // Try to update IUSD if enough time has passed (lazy update)
        _tryUpdateIUSD();

        // Deposit limit check: BTC min/max amount
        _checkWBTCAmount(wbtcAmount);

        MintLogic.MintInputs memory inputs = MintLogic.MintInputs({
            wbtcAmount: wbtcAmount,
            wbtcPrice: getWBTCPrice(),
            iusdPrice: getIUSDPrice(),
            currentBTDSupply: totalBTD(),
            feeBP: gov.mintFeeBP()
        });
        MintLogic.MintOutputs memory outputs = MintLogic.evaluate(inputs);

        // Security: Minter receives WBTC first, then transfers to Treasury
        // Step 1: User transfers WBTC to Minter (user needs to approve Minter)
        IERC20(core.WBTC()).safeTransferFrom(msg.sender, address(this), wbtcAmount);

        // Step 2: Minter approves Treasury (if not enough allowance)
        IERC20 wbtc = IERC20(core.WBTC());
        address treasuryAddr = core.TREASURY();
        if (wbtc.allowance(address(this), treasuryAddr) < wbtcAmount) {
            wbtc.forceApprove(treasuryAddr, type(uint256).max);
        }

        // Step 3: Treasury transfers from Minter
        ITreasury(treasuryAddr).depositWBTC(wbtcAmount);

        // Mint BTD: user gets net amount, fee goes to Treasury
        IMintableERC20 btdToken = IMintableERC20(core.BTD());
        btdToken.mint(msg.sender, outputs.btdToMint);  // User gets amount after fee
        if (outputs.fee > 0) {
            btdToken.mint(treasuryAddr, outputs.fee);  // Treasury gets fee
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
        // Update TWAP for all prices (WBTC always needed, BTD/BTB/BRS needed when CR<100%)
        _updateTWAPAll();
        // Try to update IUSD if enough time has passed (lazy update)
        _tryUpdateIUSD();

        require(btdAmount > 0, "Invalid amount");
        require(
            IMintableERC20(core.BTD()).balanceOf(account) >= btdAmount,
            "Not enough BTD"
        );

        // Withdrawal limit check: BTD is stablecoin
        _checkStablecoinAmount(btdAmount);

        uint256 wbtcPrice = getWBTCPrice();
        uint256 iusdPrice = getIUSDPrice();
        uint256 cr = _getCRWithPrice(wbtcPrice, iusdPrice);

        RedeemLogic.RedeemInputs memory redeemInputs = RedeemLogic.RedeemInputs({
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
            redeemInputs.btdPrice = getBTDPrice();
            redeemInputs.btbPrice = getBTBPrice();
            redeemInputs.brsPrice = getBRSPrice();
            redeemInputs.minBTBPriceInBTD = gov.minBTBPrice();
        }

        RedeemLogic.RedeemOutputs memory redeemOutputs = RedeemLogic.evaluate(redeemInputs);

        // Burn all user's BTD (including fee)
        IMintableERC20(core.BTD()).burnFrom(account, btdAmount);

        // If there's redemption fee, mint to Treasury
        if (redeemOutputs.fee > 0) {
            IMintableERC20(core.BTD()).mint(core.TREASURY(), redeemOutputs.fee);
        }

        uint256 wbtcOut = _wbtcFromNormalized(redeemOutputs.wbtcOutNormalized);
        if (wbtcOut > 0) {
            _checkWBTCAmount(wbtcOut);
            ITreasury(core.TREASURY()).withdrawWBTC(wbtcOut);
            IERC20(core.WBTC()).safeTransfer(account, wbtcOut);
        }

        if (redeemOutputs.brsOut > 0) {
            ITreasury(core.TREASURY()).compensate(account, redeemOutputs.brsOut);
        }

        if (redeemOutputs.btbOut > 0) {
            IMintableERC20(core.BTB()).mint(account, redeemOutputs.btbOut);
        }

        emit BTDRedeemed(account, btdAmount, wbtcOut, redeemOutputs.btbOut, redeemOutputs.brsOut);

        // Note: fee is collected by burning user's BTD and minting back to Treasury
        // The effective BTD removed from circulation is (btdAmount - fee)
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
     * @param account Redeemer address
     * @param btbAmount BTB amount (18 decimals)
     */
    function _validateRedeemBTBRequest(address account, uint256 btbAmount) internal view {
        _checkStablecoinAmount(btbAmount);
        require(
            IMintableERC20(core.BTB()).balanceOf(account) >= btbAmount,
            "Not enough BTB"
        );
    }

    /**
     * @notice Internal BTB redemption implementation
     * @dev Checks CR>=100%, redemption value meets minimum, doesn't exceed max redeemable, then burns BTB and mints BTD
     * @param account Redeemer address
     * @param btbAmount BTB amount (18 decimals)
     */
    function _redeemBTB(address account, uint256 btbAmount) internal {
        // Update TWAP for WBTC price (needed for CR calculation)
        _updateTWAPForWBTC();
        // Try to update IUSD if enough time has passed (lazy update)
        _tryUpdateIUSD();

        // Get all prices at once (gas saving)
        uint256 wbtcPrice = getWBTCPrice();
        uint256 iusdPrice = getIUSDPrice();
        uint256 cr = _getCRWithPrice(wbtcPrice, iusdPrice);
        require(cr >= 1e18, "CR<100%, BTB not redeemable");

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
     * @return _totalBTD BTD total supply (18 decimals)
     * @return _totalWBTC WBTC balance in Treasury (8 decimals)
     * @return _collateralRatio Collateral ratio (18 decimals, 1e18=100%)
     * @return _wbtcPrice WBTC price (18-decimal USD)
     * @return _btbPrice BTB price (18-decimal USD)
     * @return _brsPrice BRS price (18-decimal USD)
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
        _totalBTD = totalBTD();
        _totalWBTC = totalWBTC();
        _collateralRatio = getCollateralRatio();
        _wbtcPrice = getWBTCPrice();
        _btbPrice = getBTBPrice();
        _brsPrice = getBRSPrice();
    }
}
