// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable2Step, Ownable} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import {IERC4626} from "@openzeppelin/contracts/interfaces/IERC4626.sol";
import "./ConfigCore.sol";
import "./ConfigGov.sol";
import "./interfaces/IIdealUSDManager.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IUniswapV2TWAPOracle.sol";
import "./interfaces/IAggregatorV3.sol";
import "./interfaces/IMinter.sol";
import "./libraries/OracleMath.sol";
import "./libraries/FeedValidation.sol";

/// @notice Pyth Price Feed Interface
interface IPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    function getPriceUnsafe(bytes32 id) external view returns (Price memory price);
}

/// @notice Uniswap V2 Pair Interface
interface IUniswapV2Pair {
    function getReserves() external view returns (uint112, uint112, uint32);
    function token0() external view returns (address);
    function token1() external view returns (address);
}

/**
 * @title PriceOracle - Bitres System Price Oracle
 * @notice Provides TWAP-protected unified price query service for the entire Bitres system
 * @dev Implements separation of concerns, isolating price query logic from business contracts
 */
contract PriceOracle is Ownable2Step, IPriceOracle {
    // ============ State Variables ============

    // Immutable core configuration (fixed at deployment)
    ConfigCore public immutable core;
    ConfigGov public immutable gov;
    bytes32 public immutable pythWbtcPriceId;
    bool public immutable useTWAPDefault;

    // Mutable configuration (whitelist restricted)
    IUniswapV2TWAPOracle public twapOracle;
    bool public useTWAP;

    // Governable parameters (strictly restricted)
    uint256 public maxDeviationBps = 100; // Default 1%
    uint256 public lastDeviationUpdate;

    // Safety limit constants
    uint256 public constant MAX_DEVIATION_CEILING = 500;  // Cannot exceed 5%
    uint256 public constant MIN_DEVIATION_FLOOR = 50;     // Cannot be below 0.5%
    uint256 public constant DEVIATION_UPDATE_COOLDOWN = 1 days;
    uint256 public constant GOV_COOLDOWN = 1 days;

    // Pyth price safety parameters
    uint256 public constant PYTH_MAX_STALENESS = 60;      // Maximum staleness: 60 seconds
    uint64 public constant PYTH_MAX_CONF_RATIO = 100;     // Maximum confidence ratio: 1% (conf/price < 1%)

    // Stablecoin depeg threshold (1% = 100 basis points)
    uint256 public constant STABLECOIN_MAX_DEVIATION_BPS = 100;

    // ============ Token Price Guardrails ============
    // TWAP vs Spot deviation thresholds (basis points)
    uint256 public constant BTD_TWAP_SPOT_MAX_BPS = 500;   // 5% - BTD is stablecoin, tighter bound
    uint256 public constant BTB_TWAP_SPOT_MAX_BPS = 1000;  // 10% - BTB is more volatile
    uint256 public constant BRS_TWAP_SPOT_MAX_BPS = 2000;  // 20% - BRS is equity token, most volatile

    // BTD price floor multiplier (90% = 9000 basis points)
    uint256 public constant BTD_FLOOR_MULTIPLIER_BPS = 9000;

    /// @notice Maximum deviation update event
    /// @param oldBps Old deviation value (basis points)
    /// @param newBps New deviation value (basis points)
    event MaxDeviationUpdated(uint256 oldBps, uint256 newBps);

    // ============ Initialization ============

    /**
     * @notice Constructor
     * @dev Initializes price oracle, fixes core configuration parameters
     */
    constructor(
        address initialOwner,                  // Contract owner address, cannot be zero address
        address _core,                         // ConfigCore contract address, cannot be zero address
        address _gov,                          // ConfigGov contract address, cannot be zero address
        address _twapOracle,                   // TWAP Oracle address, can be zero address (set later)
        bytes32 _pythWbtcPriceId               // Pyth WBTC price ID, cannot be zero
    ) Ownable(initialOwner) {
        require(initialOwner != address(0), "Invalid owner");
        require(_core != address(0), "Invalid core address");
        require(_gov != address(0), "Invalid gov address");
        require(_pythWbtcPriceId != bytes32(0), "Invalid Pyth price id");

        core = ConfigCore(_core);
        gov = ConfigGov(_gov);
        pythWbtcPriceId = _pythWbtcPriceId;
        useTWAPDefault = true;
        useTWAP = true;

        if (_twapOracle != address(0)) {
            twapOracle = IUniswapV2TWAPOracle(_twapOracle);
        }
    }

    // ============ TWAP Management ============

    /**
     * @notice Sets TWAP Oracle address
     * @dev Only owner can call, used to update TWAP Oracle contract address
     * @param _twapOracle New TWAP Oracle address
     */
    function setTWAPOracle(address _twapOracle) external onlyOwner {
        address oldOracle = address(twapOracle);
        twapOracle = IUniswapV2TWAPOracle(_twapOracle);
        emit TWAPOracleUpdated(oldOracle, _twapOracle);
    }

    /**
     * @notice Toggles TWAP mode switch
     * @dev Only owner can call, used to enable or disable TWAP price protection
     * @param _useTWAP true to enable TWAP, false to use spot price
     */
    function setUseTWAP(bool _useTWAP) external onlyOwner {
        useTWAP = _useTWAP;
        emit TWAPModeChanged(_useTWAP);
    }

    // Removed: setPythWbtcPriceId() - pythWbtcPriceId is now immutable
    //
    // Refactoring notes:
    // - Pyth configuration parameters are now fixed as immutable in constructor
    // - These parameters cannot be modified after deployment, following weak governance principle
    // - WBTC price uses dual-source validation: Chainlink + Pyth must agree within 1%
    // - Redstone removed: Two reliable sources (Chainlink + Pyth) are sufficient

    /**
     * @notice Sets maximum price deviation value (basis points)
     * @dev Only owner can call, with strict safety restrictions:
     *      1. Boundary check: 0.5% <= newBps <= 5%
     *      2. One-way adjustment: can only tighten, not loosen
     *      3. Cooldown period: at least 1 day between adjustments
     *      4. Event logging: records all changes
     * @param newBps New deviation value (basis points, e.g., 100 = 1%)
     */
    function setMaxDeviationBps(uint256 newBps) external onlyOwner {
        // 1. Boundary check
        require(newBps >= MIN_DEVIATION_FLOOR, "Deviation too low");
        require(newBps <= MAX_DEVIATION_CEILING, "Deviation too high");

        // 2. One-way adjustment (can only be stricter)
        require(newBps < maxDeviationBps, "Deviation can only tighten");

        // 3. Cooldown period check
        if (lastDeviationUpdate > 0) {
            require(
                block.timestamp >= lastDeviationUpdate + DEVIATION_UPDATE_COOLDOWN,
                "Cooldown not met"
            );
        }

        uint256 old = maxDeviationBps;
        maxDeviationBps = newBps;
        lastDeviationUpdate = block.timestamp;

        // 4. Event logging
        emit MaxDeviationUpdated(old, newBps);
    }

    /**
     * @notice Checks if TWAP is enabled
     * @dev Checks both TWAP switch and whether Oracle address is set
     * @return true if TWAP is enabled and available
     */
    function isTWAPEnabled() external view returns (bool) {
        return useTWAP && address(twapOracle) != address(0);
    }

    /**
     * @notice Gets TWAP Oracle contract address
     * @dev Returns currently configured TWAP Oracle address
     * @return TWAP Oracle contract address
     */
    function getTWAPOracle() external view returns (address) {
        return address(twapOracle);
    }

    // ============ TWAP Update Functions ============

    /**
     * @notice Update TWAP for WBTC price query (WBTC/USDC pair)
     * @dev Call before getWBTCPrice() if TWAP might be stale
     */
    function updateTWAPForWBTC() external {
        if (useTWAP && address(twapOracle) != address(0)) {
            twapOracle.updateIfNeeded(core.POOL_WBTC_USDC());
        }
    }

    /**
     * @notice Update TWAP for BTD price query (BTD/USDC pair)
     * @dev Call before getBTDPrice() if TWAP might be stale
     */
    function updateTWAPForBTD() external {
        if (useTWAP && address(twapOracle) != address(0)) {
            twapOracle.updateIfNeeded(core.POOL_BTD_USDC());
        }
    }

    /**
     * @notice Update TWAP for BTB price query (BTB/BTD + BTD/USDC pairs)
     * @dev Call before getBTBPrice() if TWAP might be stale
     */
    function updateTWAPForBTB() external {
        if (useTWAP && address(twapOracle) != address(0)) {
            twapOracle.updateIfNeeded(core.POOL_BTB_BTD());
            twapOracle.updateIfNeeded(core.POOL_BTD_USDC());
        }
    }

    /**
     * @notice Update TWAP for BRS price query (BRS/BTD + BTD/USDC pairs)
     * @dev Call before getBRSPrice() if TWAP might be stale
     */
    function updateTWAPForBRS() external {
        if (useTWAP && address(twapOracle) != address(0)) {
            twapOracle.updateIfNeeded(core.POOL_BRS_BTD());
            twapOracle.updateIfNeeded(core.POOL_BTD_USDC());
        }
    }

    /**
     * @notice Update TWAP for all pairs (use when multiple prices needed)
     * @dev Updates all 4 pairs: WBTC/USDC, BTD/USDC, BTB/BTD, BRS/BTD
     */
    function updateTWAPAll() external {
        if (useTWAP && address(twapOracle) != address(0)) {
            twapOracle.updateIfNeeded(core.POOL_WBTC_USDC());
            twapOracle.updateIfNeeded(core.POOL_BTD_USDC());
            twapOracle.updateIfNeeded(core.POOL_BTB_BTD());
            twapOracle.updateIfNeeded(core.POOL_BRS_BTD());
        }
    }

    // ============ Chainlink Price Queries ============

    /**
     * @notice Gets Chainlink BTC/USD price
     * @dev Reads BTC price from Chainlink aggregator, 18 decimals
     * @return BTC price (18 decimal USD)
     */
    function getChainlinkBTCUSD() public view returns (uint256) {
        return _getChainlinkPrice(gov.chainlinkBtcUsd());
    }

    /**
     * @notice Internal function to read price from Chainlink aggregator
     * @dev Uses FeedValidation library for security validation
     * @param feedAddress Chainlink price feed address
     * @return Normalized price (18 decimals)
     */
    function _getChainlinkPrice(address feedAddress) internal view returns (uint256) {
        return FeedValidation.readAggregator(feedAddress);
    }

    /**
     * @notice Gets WBTC/USD price via Chainlink
     * @dev Calculates by multiplying WBTC/BTC and BTC/USD from two price feeds
     * @return WBTC price (18 decimal USD)
     */
    function _getChainlinkWBTCUSD() internal view returns (uint256) {
        uint256 wbtcToBtc = _getChainlinkPrice(gov.chainlinkWbtcBtc());
        uint256 btcToUsd = getChainlinkBTCUSD();
        return Math.mulDiv(wbtcToBtc, btcToUsd, 1e18);
    }

    /**
     * @notice Gets WBTC/USD price via Pyth
     * @dev Reads price from Pyth network and normalizes to 18 decimals
     * @return WBTC price (18 decimal USD)
     */
    function _getPythWBTCUSD() internal view returns (uint256) {
        address pythFeed = gov.pythWbtc();
        require(pythFeed != address(0), "Pyth feed not set");
        require(pythWbtcPriceId != bytes32(0), "Pyth price id not set");

        IPyth.Price memory price = IPyth(pythFeed).getPriceUnsafe(pythWbtcPriceId);
        require(price.price > 0, "Invalid Pyth price");

        // Check publishTime freshness (prevent stale prices)
        require(
            block.timestamp - price.publishTime <= PYTH_MAX_STALENESS,
            "Pyth price stale"
        );

        // Check confidence level (conf should be small relative to price)
        // conf/price < 1% means price uncertainty is acceptable
        require(
            price.conf * 100 <= uint64(price.price),
            "Pyth confidence too wide"
        );

        return _scalePythPrice(price.price, price.expo);
    }

    /**
     * @notice Converts Pyth price format to standard 18 decimals
     * @dev Handles Pyth-specific price and exponent format
     * @param price Pyth raw price value
     * @param expo Pyth price exponent
     * @return Normalized price (18 decimals)
     */
    function _scalePythPrice(int64 price, int32 expo) internal pure returns (uint256) {
        require(price > 0, "Invalid Pyth value");
        int32 exponent = expo + 18;
        require(exponent > -80 && exponent < 80, "Pyth exponent out of bounds");
        uint256 base = uint256(uint64(price));

        if (exponent >= 0) {
            return base * (10 ** uint32(uint32(exponent)));
        }

        uint32 absExp = uint32(uint32(-exponent));
        return base / (10 ** absExp);
    }

    // ============ Core Price Queries ============

    /**
     * @notice Gets token price from Uniswap V2 pool
     * @dev Chooses TWAP price or spot price based on TWAP switch
     * @param pool Uniswap V2 pool address
     * @param base Base token address
     * @param quote Quote token address
     * @return Price (18 decimals, representing how much quote per base)
     */
    function getPrice(address pool, address base, address quote)
        public view returns (uint256) {
        // Use TWAP (if enabled and available)
        if (useTWAP && address(twapOracle) != address(0)) {
            return _getPriceTWAP(pool, base, quote);
        }
        return _getPriceSpot(pool, base, quote);
    }

    /**
     * @notice Gets WBTC/USD price (dual-source validation)
     * @dev Requires Chainlink and Pyth prices to be consistent (within 1%), then validates against Uniswap TWAP
     * @dev Safety check: All three sources must agree within deviation threshold, otherwise reverts
     * @return WBTC price (18 decimal USD)
     */
    function getWBTCPrice() public view returns (uint256) {
        uint256 chainlinkPrice = _getChainlinkWBTCUSD();
        uint256 pythPrice = _getPythWBTCUSD();

        // Step 1: Chainlink and Pyth must agree within 1%
        require(
            OracleMath.deviationWithin(chainlinkPrice, pythPrice, maxDeviationBps),
            "Chainlink/Pyth price mismatch"
        );

        // Step 2: Use average as reference price
        uint256 referencePrice = (chainlinkPrice + pythPrice) / 2;

        // Step 3: Validate Uniswap TWAP against reference
        uint256 uniPrice = getPrice(
            core.POOL_WBTC_USDC(),
            core.WBTC(),
            core.USDC()
        );

        require(
            OracleMath.deviationWithin(uniPrice, referencePrice, maxDeviationBps),
            "Uniswap/Oracle price mismatch"
        );

        return uniPrice;
    }

    /**
     * @notice Gets BTD/USD actual market price with guardrails
     * @dev Reads price from Uniswap BTD/USDC pool with safety checks:
     *      1. TWAP vs Spot deviation must be within 5%
     *      2. Price floor: TWAP >= CR * IUSD * 0.9
     * @return BTD price (18 decimal USD)
     */
    function getBTDPrice() public view returns (uint256) {
        address pool = core.POOL_BTD_USDC();
        address base = core.BTD();
        address quote = core.USDC();

        // Get TWAP price (primary)
        uint256 twapPrice = _getPriceTWAP(pool, base, quote);

        // Guardrail 1: Check TWAP vs Spot deviation
        uint256 spotPrice = _getPriceSpot(pool, base, quote);
        require(
            OracleMath.deviationWithin(twapPrice, spotPrice, BTD_TWAP_SPOT_MAX_BPS),
            "BTD: TWAP/spot deviation"
        );

        // Guardrail 2: Price floor = CR * IUSD * 0.9
        uint256 iusdPrice = getIUSDPrice();
        uint256 cr = _getCollateralRatio();
        // Cap CR at 100% for floor calculation
        if (cr > 1e18) {
            cr = 1e18;
        }
        // floor = CR * IUSD * 0.9
        uint256 floor = Math.mulDiv(
            Math.mulDiv(cr, iusdPrice, 1e18),
            BTD_FLOOR_MULTIPLIER_BPS,
            10000
        );
        require(twapPrice >= floor, "BTD: price below floor");

        return twapPrice;
    }

    /**
     * @notice Internal helper to get collateral ratio from Minter
     * @dev Returns 1e18 (100%) if Minter not available
     * @return Collateral ratio (18 decimals, 1e18 = 100%)
     */
    function _getCollateralRatio() internal view returns (uint256) {
        address minter = core.MINTER();
        if (minter == address(0)) {
            return 1e18; // Default to 100% if Minter not set
        }
        return IMinter(minter).getCollateralRatio();
    }

    /**
     * @notice Gets BTB/USD price with guardrails
     * @dev Calculates via BTB/BTD and BTD/USDC two pools: BTB price = (BTB/BTD price) x (BTD/USD price)
     *      Guardrail: BTB/BTD TWAP vs Spot deviation must be within 10%
     * @return BTB price (18 decimal USD)
     */
    function getBTBPrice() public view returns (uint256) {
        address pool = core.POOL_BTB_BTD();
        address base = core.BTB();
        address quote = core.BTD();

        // Get TWAP price for BTB/BTD
        uint256 btbBtdTwap = _getPriceTWAP(pool, base, quote);

        // Guardrail: Check TWAP vs Spot deviation
        uint256 btbBtdSpot = _getPriceSpot(pool, base, quote);
        require(
            OracleMath.deviationWithin(btbBtdTwap, btbBtdSpot, BTB_TWAP_SPOT_MAX_BPS),
            "BTB: TWAP/spot deviation"
        );

        // BTB/USD = BTB/BTD * BTD/USD
        uint256 btdUsdc = getBTDPrice();  // Already has guardrails
        uint256 price = Math.mulDiv(btbBtdTwap, btdUsdc, 1e18);

        // Return actual price (no limit)
        // Price capping is handled by Minter contract:
        // - If BTB price < minPrice, calculate BTB compensation at minPrice, difference compensated with BRS
        return price;
    }

    /**
     * @notice Gets BRS/USD price with guardrails
     * @dev Calculates via BRS/BTD and BTD/USDC two pools: BRS price = (BRS/BTD price) x (BTD/USD price)
     *      Guardrail: BRS/BTD TWAP vs Spot deviation must be within 20%
     * @return BRS price (18 decimal USD)
     */
    function getBRSPrice() public view returns (uint256) {
        address pool = core.POOL_BRS_BTD();
        address base = core.BRS();
        address quote = core.BTD();

        // Get TWAP price for BRS/BTD
        uint256 brsBtdTwap = _getPriceTWAP(pool, base, quote);

        // Guardrail: Check TWAP vs Spot deviation
        uint256 brsBtdSpot = _getPriceSpot(pool, base, quote);
        require(
            OracleMath.deviationWithin(brsBtdTwap, brsBtdSpot, BRS_TWAP_SPOT_MAX_BPS),
            "BRS: TWAP/spot deviation"
        );

        // BRS/USD = BRS/BTD * BTD/USD
        uint256 btdUsdc = getBTDPrice();  // Already has guardrails
        uint256 price = Math.mulDiv(brsBtdTwap, btdUsdc, 1e18);

        return price;
    }

    /**
     * @notice Gets stBTD price (BTD share price including accumulated interest)
     * @dev Uses ERC4626 formula: (totalAssets / totalSupply) x BTD price
     * @return stBTD price (18 decimal USD)
     */
    function getStBTDPrice() public view returns (uint256) {
        address stBTDAddr = core.ST_BTD();
        require(stBTDAddr != address(0), "stBTD not configured");

        IERC4626 stBTDVault = IERC4626(stBTDAddr);
        uint256 totalShares = stBTDVault.totalSupply();

        // Initial state: no deposits yet, 1:1 pegged to BTD
        if (totalShares == 0) {
            return getBTDPrice();
        }

        // Get total underlying assets (includes accumulated interest)
        uint256 totalAssets = stBTDVault.totalAssets();

        // Assets per share (18 decimals)
        // assetsPerShare = totalAssets / totalShares
        uint256 assetsPerShare = Math.mulDiv(totalAssets, 1e18, totalShares);

        // stBTD price = assets per share x BTD price
        uint256 btdPrice = getBTDPrice();
        return Math.mulDiv(assetsPerShare, btdPrice, 1e18);
    }

    /**
     * @notice Gets stBTB price (BTB share price including accumulated interest)
     * @dev Uses ERC4626 formula: (totalAssets / totalSupply) x BTB price
     * @return stBTB price (18 decimal USD)
     */
    function getStBTBPrice() public view returns (uint256) {
        address stBTBAddr = core.ST_BTB();
        require(stBTBAddr != address(0), "stBTB not configured");

        IERC4626 stBTBVault = IERC4626(stBTBAddr);
        uint256 totalShares = stBTBVault.totalSupply();

        // Initial state: no deposits yet, 1:1 pegged to BTB
        if (totalShares == 0) {
            return getBTBPrice();
        }

        // Get total underlying assets (includes accumulated interest)
        uint256 totalAssets = stBTBVault.totalAssets();

        // Assets per share (18 decimals)
        // assetsPerShare = totalAssets / totalShares
        uint256 assetsPerShare = Math.mulDiv(totalAssets, 1e18, totalShares);

        // stBTB price = assets per share x BTB price
        uint256 btbPrice = getBTBPrice();
        return Math.mulDiv(assetsPerShare, btbPrice, 1e18);
    }

    /**
     * @notice Gets IUSD (Ideal USD) price
     * @dev Queries from IdealUSDManager contract, IUSD adjusts with inflation
     * @return IUSD price (18 decimals)
     */
    function getIUSDPrice() public view returns (uint256) {
        address manager = core.IDEAL_USD_MANAGER();
        require(manager != address(0), "IUSD manager not set");

        uint256 price = IIdealUSDManager(manager).getCurrentIUSD();
        require(price > 0, "Invalid IUSD price");
        return price;
    }

    /**
     * @notice Gets USDC price from Chainlink with depeg protection
     * @dev Reads from Chainlink USDC/USD feed and validates within 1% of $1
     *      Reverts if price deviates more than 1% from $1 (depeg protection)
     * @return USDC price (18 decimals)
     */
    function getUSDCPrice() public view returns (uint256) {
        return _getStablecoinPrice(gov.chainlinkUsdcUsd());
    }

    /**
     * @notice Gets USDT price from Chainlink with depeg protection
     * @dev Reads from Chainlink USDT/USD feed and validates within 1% of $1
     *      Reverts if price deviates more than 1% from $1 (depeg protection)
     * @return USDT price (18 decimals)
     */
    function getUSDTPrice() public view returns (uint256) {
        return _getStablecoinPrice(gov.chainlinkUsdtUsd());
    }

    /**
     * @notice Internal function to get stablecoin price with depeg validation
     * @dev Reads from Chainlink and validates price is within 1% of $1
     * @param feedAddress Chainlink price feed address
     * @return Stablecoin price (18 decimals)
     */
    function _getStablecoinPrice(address feedAddress) internal view returns (uint256) {
        uint256 price = FeedValidation.readAggregator(feedAddress);

        // Validate price is within 1% of $1 (0.99 to 1.01)
        uint256 oneDollar = 1e18;
        require(
            OracleMath.deviationWithin(price, oneDollar, STABLECOIN_MAX_DEVIATION_BPS),
            "Stablecoin depeg detected"
        );

        return price;
    }

    /**
     * @notice Universal price query function (returns USD price based on token address)
     * @dev Supports price queries for all major tokens in the system, including stablecoins, equity tokens, interest-bearing tokens
     * @param token Token contract address
     * @return Price (18 decimal USD)
     */
    function getPrice(address token) public view returns (uint256) {
        if (token == core.WBTC()) return getWBTCPrice();
        if (token == core.BTD()) return getBTDPrice();
        if (token == core.BTB()) return getBTBPrice();
        if (token == core.BRS()) return getBRSPrice();
        if (token == core.ST_BTD()) return getStBTDPrice();
        if (token == core.ST_BTB()) return getStBTBPrice();
        if (token == core.USDC()) return getUSDCPrice();
        if (token == core.USDT()) return getUSDTPrice();

        revert("Price not available for this token");
    }

    // ============ Internal Implementation: TWAP Price Queries ============

    /**
     * @notice Gets TWAP price (time-weighted average price)
     * @dev Reads 30-minute time-weighted average price from TWAP Oracle, prevents flash loan attacks
     * @param pool Uniswap V2 pool address
     * @param base Base token address
     * @param quote Quote token address
     * @return Price (18 decimals, quote per base)
     */
    function _getPriceTWAP(address pool, address base, address quote)
        internal view returns (uint256) {
        require(address(twapOracle) != address(0), "TWAP oracle not set");
        require(twapOracle.isTWAPReady(pool), "TWAP not ready");

        IUniswapV2Pair pair = IUniswapV2Pair(pool);
        address token0 = pair.token0();
        address token1 = pair.token1();

        require(
            (token0 == base && token1 == quote) ||
                (token0 == quote && token1 == base),
            "Invalid base/quote for pool"
        );

        // Determine token decimals
        uint8 baseDecimals = _getTokenDecimals(base);
        uint8 quoteDecimals = _getTokenDecimals(quote);

        // TWAP price0 = token1/token0 (quote per base when token0==base)
        // getTWAPPrice returns token1/token0 normalized to 18 decimals
        if (token0 == base) {
            // token0 = base, token1 = quote
            // getTWAPPrice returns: token1/token0 = quote/base (exactly what we want)
            return twapOracle.getTWAPPrice(pool, baseDecimals, quoteDecimals);
        } else {
            // token0 = quote, token1 = base
            // getTWAPPrice returns: token1/token0 = base/quote (need to invert)
            uint256 basePerQuote = twapOracle.getTWAPPrice(pool, quoteDecimals, baseDecimals);
            return OracleMath.inversePrice(basePerQuote);
        }
    }

    // ============ Internal Implementation: Spot Price Queries ============

    /**
     * @notice Gets spot price (based on current pool reserves)
     * @dev Vulnerable to flash loan attacks, only for testing environment or when TWAP unavailable
     * @param pool Uniswap V2 pool address
     * @param base Base token address
     * @param quote Quote token address
     * @return Price (18 decimals)
     */
    function _getPriceSpot(address pool, address base, address quote)
        internal view returns (uint256) {
        IUniswapV2Pair pair = IUniswapV2Pair(pool);
        (uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
        address token0 = pair.token0();
        address token1 = pair.token1();

        require(
            (token0 == base && token1 == quote) ||
                (token0 == quote && token1 == base),
            "Invalid base/quote for pool"
        );

        uint256 reserveBase = (token0 == base) ? uint256(reserve0) : uint256(reserve1);
        uint256 reserveQuote = (token0 == base) ? uint256(reserve1) : uint256(reserve0);

        uint8 baseDecimals = _getTokenDecimals(base);
        uint8 quoteDecimals = _getTokenDecimals(quote);
        return OracleMath.spotPrice(reserveBase, reserveQuote, baseDecimals, quoteDecimals);
    }

    // ============ Helper Functions ============

    /**
     * @notice Internal helper function to get token decimals
     * @dev WBTC: 8, USDC: 6, others: 18
     * @param token Token address
     * @return Token decimals
     */
    function _getTokenDecimals(address token) internal view returns (uint8) {
        if (token == core.WBTC()) {
            return 8;
        } else if (token == core.USDC()) {
            return 6;
        } else {
            return 18;
        }
    }
}
