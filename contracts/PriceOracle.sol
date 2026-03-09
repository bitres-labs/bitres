// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable2StepUpgradeable} from "@openzeppelin/contracts-upgradeable/access/Ownable2StepUpgradeable.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {UUPSUpgradeable} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
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

import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol";

/**
 * @title PriceOracle - Bitres System Price Oracle
 * @notice Provides TWAP-protected unified price query service for the entire Bitres system
 * @dev Implements separation of concerns, isolating price query logic from business contracts
 */
contract PriceOracle is Initializable, Ownable2StepUpgradeable, UUPSUpgradeable, IPriceOracle {
    // ============ State Variables ============

    // Core configuration (set in initialize, was immutable)
    ConfigCore public core;
    ConfigGov public gov;
    bytes32 public pythWbtcPriceId;
    bool public useTWAPDefault;

    // Mutable configuration (whitelist restricted)
    IUniswapV2TWAPOracle public twapOracle;
    bool public useTWAP;

    // Governable parameters (strictly restricted)
    uint256 public maxDeviationBps;
    uint256 public lastDeviationUpdate;

    // Safety limit constants
    uint256 public constant MAX_DEVIATION_CEILING = 500;  // Cannot exceed 5%
    uint256 public constant MIN_DEVIATION_FLOOR = 50;     // Cannot be below 0.5%
    uint256 public constant DEVIATION_UPDATE_COOLDOWN = 1 days;

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /**
     * @notice Initialize price oracle
     * @dev Sets core configuration parameters
     */
    function initialize(
        address initialOwner,
        address _core,
        address _gov,
        address _twapOracle,
        bytes32 _pythWbtcPriceId
    ) public initializer {
        require(initialOwner != address(0), "Invalid owner");
        require(_core != address(0), "Invalid core address");
        require(_gov != address(0), "Invalid gov address");
        require(_pythWbtcPriceId != bytes32(0), "Invalid Pyth price id");

        __Ownable_init(initialOwner);
        __Ownable2Step_init();
        __UUPSUpgradeable_init();

        core = ConfigCore(_core);
        gov = ConfigGov(_gov);
        pythWbtcPriceId = _pythWbtcPriceId;
        useTWAPDefault = true;
        useTWAP = true;
        maxDeviationBps = 100; // Default 1%

        if (_twapOracle != address(0)) {
            twapOracle = IUniswapV2TWAPOracle(_twapOracle);
        }
    }

    // ============ UUPS ============

    function _authorizeUpgrade(address) internal override onlyOwner {}

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
        require(newBps >= MIN_DEVIATION_FLOOR, "Deviation too low");
        require(newBps <= MAX_DEVIATION_CEILING, "Deviation too high");
        require(newBps < maxDeviationBps, "Deviation can only tighten");

        if (lastDeviationUpdate > 0) {
            require(
                block.timestamp >= lastDeviationUpdate + DEVIATION_UPDATE_COOLDOWN,
                "Cooldown not met"
            );
        }

        uint256 old = maxDeviationBps;
        maxDeviationBps = newBps;
        lastDeviationUpdate = block.timestamp;

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

    function _updateTWAPForPools(address[] memory pools) internal {
        if (!useTWAP || address(twapOracle) == address(0)) return;
        for (uint256 i = 0; i < pools.length; i++) {
            twapOracle.updateIfNeeded(pools[i]);
        }
    }

    function updateTWAPForWBTC() external {
        address[] memory pools = new address[](1);
        pools[0] = core.POOL_WBTC_USDC();
        _updateTWAPForPools(pools);
    }

    function updateTWAPForBTD() external {
        address[] memory pools = new address[](1);
        pools[0] = core.POOL_BTD_USDC();
        _updateTWAPForPools(pools);
    }

    function updateTWAPForBTB() external {
        address[] memory pools = new address[](2);
        pools[0] = core.POOL_BTB_BTD();
        pools[1] = core.POOL_BTD_USDC();
        _updateTWAPForPools(pools);
    }

    function updateTWAPForBRS() external {
        address[] memory pools = new address[](2);
        pools[0] = core.POOL_BRS_BTD();
        pools[1] = core.POOL_BTD_USDC();
        _updateTWAPForPools(pools);
    }

    function updateTWAPAll() external {
        address[] memory pools = new address[](4);
        pools[0] = core.POOL_WBTC_USDC();
        pools[1] = core.POOL_BTD_USDC();
        pools[2] = core.POOL_BTB_BTD();
        pools[3] = core.POOL_BRS_BTD();
        _updateTWAPForPools(pools);
    }

    // ============ Chainlink Price Queries ============

    function getChainlinkBTCUSD() public view returns (uint256) {
        return _getChainlinkPrice(gov.chainlinkBtcUsd());
    }

    function _getChainlinkPrice(address feedAddress) internal view returns (uint256) {
        return FeedValidation.readAggregator(feedAddress);
    }

    function _getChainlinkWBTCUSD() internal view returns (uint256) {
        uint256 wbtcToBtc = _getChainlinkPrice(gov.chainlinkWbtcBtc());
        uint256 btcToUsd = getChainlinkBTCUSD();
        return Math.mulDiv(wbtcToBtc, btcToUsd, 1e18);
    }

    function _getPythWBTCUSD() internal view returns (uint256) {
        address pythFeed = gov.pythWbtc();
        require(pythFeed != address(0), "Pyth feed not set");
        require(pythWbtcPriceId != bytes32(0), "Pyth price id not set");

        IPyth.Price memory price = IPyth(pythFeed).getPriceUnsafe(pythWbtcPriceId);
        require(price.price > 0, "Invalid Pyth price");

        require(
            block.timestamp - price.publishTime <= PYTH_MAX_STALENESS,
            "Pyth price stale"
        );

        require(
            price.conf * PYTH_MAX_CONF_RATIO <= uint64(price.price),
            "Pyth confidence too wide"
        );

        return _scalePythPrice(price.price, price.expo);
    }

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

    function getPrice(address pool, address base, address quote)
        public view returns (uint256) {
        if (useTWAP && address(twapOracle) != address(0)) {
            return _getPriceTWAP(pool, base, quote);
        }
        return _getPriceSpot(pool, base, quote);
    }

    function getWBTCPrice() public view returns (uint256) {
        uint256 chainlinkPrice = _getChainlinkWBTCUSD();
        uint256 pythPrice = _getPythWBTCUSD();

        require(
            OracleMath.deviationWithin(chainlinkPrice, pythPrice, maxDeviationBps),
            "Chainlink/Pyth price mismatch"
        );

        uint256 referencePrice = (chainlinkPrice + pythPrice) / 2;

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

    function getBTDPrice() public view returns (uint256) {
        address pool = core.POOL_BTD_USDC();
        address base = core.BTD();
        address quote = core.USDC();

        uint256 twapPrice = _getPriceTWAP(pool, base, quote);

        uint256 spotPrice = _getPriceSpot(pool, base, quote);
        require(
            OracleMath.deviationWithin(twapPrice, spotPrice, BTD_TWAP_SPOT_MAX_BPS),
            "BTD: TWAP/spot deviation"
        );

        uint256 iusdPrice = getIUSDPrice();
        uint256 cr = _getCollateralRatio();
        if (cr > 1e18) {
            cr = 1e18;
        }
        uint256 floor = Math.mulDiv(
            Math.mulDiv(cr, iusdPrice, 1e18),
            BTD_FLOOR_MULTIPLIER_BPS,
            10000
        );
        require(twapPrice >= floor, "BTD: price below floor");

        return twapPrice;
    }

    function _getCollateralRatio() internal view returns (uint256) {
        address minter = core.MINTER();
        if (minter == address(0)) {
            return 1e18;
        }
        return IMinter(minter).getCollateralRatio();
    }

    function _getTokenPriceViaBTD(
        address pool,
        address base,
        uint256 twapSpotMaxBps,
        string memory tokenName
    ) internal view returns (uint256) {
        address quote = core.BTD();

        uint256 twapPrice = _getPriceTWAP(pool, base, quote);

        uint256 spotPrice = _getPriceSpot(pool, base, quote);
        require(
            OracleMath.deviationWithin(twapPrice, spotPrice, twapSpotMaxBps),
            string.concat(tokenName, ": TWAP/spot deviation")
        );

        uint256 btdUsdc = getBTDPrice();
        return Math.mulDiv(twapPrice, btdUsdc, 1e18);
    }

    function getBTBPrice() public view returns (uint256) {
        return _getTokenPriceViaBTD(
            core.POOL_BTB_BTD(),
            core.BTB(),
            BTB_TWAP_SPOT_MAX_BPS,
            "BTB"
        );
    }

    function getBRSPrice() public view returns (uint256) {
        return _getTokenPriceViaBTD(
            core.POOL_BRS_BTD(),
            core.BRS(),
            BRS_TWAP_SPOT_MAX_BPS,
            "BRS"
        );
    }

    function _getVaultTokenPrice(
        address vaultAddr,
        uint256 underlyingPrice,
        string memory tokenName
    ) internal view returns (uint256) {
        require(vaultAddr != address(0), string.concat(tokenName, " not configured"));

        IERC4626 vault = IERC4626(vaultAddr);
        uint256 totalShares = vault.totalSupply();

        if (totalShares == 0) {
            return underlyingPrice;
        }

        uint256 totalAssets = vault.totalAssets();
        uint256 assetsPerShare = Math.mulDiv(totalAssets, 1e18, totalShares);

        return Math.mulDiv(assetsPerShare, underlyingPrice, 1e18);
    }

    function getStBTDPrice() public view returns (uint256) {
        return _getVaultTokenPrice(core.ST_BTD(), getBTDPrice(), "stBTD");
    }

    function getStBTBPrice() public view returns (uint256) {
        return _getVaultTokenPrice(core.ST_BTB(), getBTBPrice(), "stBTB");
    }

    function getIUSDPrice() public view returns (uint256) {
        address manager = core.IDEAL_USD_MANAGER();
        require(manager != address(0), "IUSD manager not set");

        uint256 price = IIdealUSDManager(manager).getCurrentIUSD();
        require(price > 0, "Invalid IUSD price");
        return price;
    }

    function getUSDCPrice() public view returns (uint256) {
        return _getStablecoinPrice(gov.chainlinkUsdcUsd());
    }

    function getUSDTPrice() public view returns (uint256) {
        return _getStablecoinPrice(gov.chainlinkUsdtUsd());
    }

    function _getStablecoinPrice(address feedAddress) internal view returns (uint256) {
        uint256 price = FeedValidation.readAggregator(feedAddress);

        uint256 oneDollar = 1e18;
        require(
            OracleMath.deviationWithin(price, oneDollar, STABLECOIN_MAX_DEVIATION_BPS),
            "Stablecoin depeg detected"
        );

        return price;
    }

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

        uint8 baseDecimals = _getTokenDecimals(base);
        uint8 quoteDecimals = _getTokenDecimals(quote);

        if (token0 == base) {
            return twapOracle.getTWAPPrice(pool, baseDecimals, quoteDecimals);
        } else {
            uint256 basePerQuote = twapOracle.getTWAPPrice(pool, quoteDecimals, baseDecimals);
            return OracleMath.inversePrice(basePerQuote);
        }
    }

    // ============ Internal Implementation: Spot Price Queries ============

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

    function _getTokenDecimals(address token) internal view returns (uint8) {
        if (token == core.WBTC()) {
            return 8;
        } else if (token == core.USDC()) {
            return 6;
        } else {
            return 18;
        }
    }

    // ============ Storage Gap ============

    uint256[50] private __gap;
}
