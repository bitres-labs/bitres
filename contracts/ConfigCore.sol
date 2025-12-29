// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/**
 * @title ConfigCore
 * @notice Immutable configuration core - stores critical system addresses
 * @dev Cannot be changed after deployment, ensuring system core architecture stability
 * @dev All core addresses are set once via constructor and permanently fixed
 */
contract ConfigCore {
    // ==================== Deployer Access Control ====================

    /// @notice Deployer address - only this address can call setCoreContracts and setPeripheralContracts
    /// @dev Set in constructor, cannot be changed after deployment
    address public immutable deployer;

    /// @notice Modifier to restrict access to deployer only
    modifier onlyDeployer() {
        require(msg.sender == deployer, "ConfigCore: caller is not deployer");
        _;
    }

    // ==================== Core Token Addresses (immutable) ====================

    /// @notice WBTC token address - used for collateral to mint BTD
    /// @dev Cannot be changed after deployment
    address public immutable WBTC;

    /// @notice BTD stablecoin address - primary stablecoin
    /// @dev Cannot be changed after deployment
    address public immutable BTD;

    /// @notice BTB bond token address - redemption bonds
    /// @dev Cannot be changed after deployment
    address public immutable BTB;

    /// @notice BRS governance token address - governance token
    /// @dev Cannot be changed after deployment
    address public immutable BRS;

    /// @notice WETH token address - Wrapped ETH
    /// @dev Cannot be changed after deployment
    address public immutable WETH;

    /// @notice USDC token address - stablecoin reserve
    /// @dev Cannot be changed after deployment
    address public immutable USDC;

    /// @notice USDT token address - stablecoin reserve
    /// @dev Cannot be changed after deployment
    address public immutable USDT;

    // ==================== Core Contract Addresses (storage - deferred binding) ====================
    // These 5 contracts have circular dependencies with ConfigCore, so they use storage and are set via setCoreContracts()

    /// @notice Treasury contract address - manages system assets
    /// @dev Set once via setCoreContracts() and cannot be changed afterward
    address public TREASURY;

    /// @notice Minter contract address - handles BTD minting and redemption
    /// @dev Set once via setCoreContracts() and cannot be changed afterward
    address public MINTER;

    /// @notice Price oracle address - provides WBTC price data
    /// @dev Set once via setCoreContracts() and cannot be changed afterward
    address public PRICE_ORACLE;

    /// @notice IUSD manager address - manages Ideal USD inflation adjustments
    /// @dev Set once via setCoreContracts() and cannot be changed afterward
    address public IDEAL_USD_MANAGER;

    /// @notice Interest pool address - manages BTD and BTB interest distribution
    /// @dev Set once via setCoreContracts() and cannot be changed afterward
    address public INTEREST_POOL;

    /// @notice Flag indicating whether core contracts have been set
    /// @dev Ensures setCoreContracts() can only be called once
    bool public coreContractsSet;

    /// @notice Flag indicating whether peripheral contracts have been set
    /// @dev Ensures setPeripheralContracts() can only be called once
    bool public peripheralContractsSet;

    // ==================== Price Oracle Data Source Addresses (immutable) ====================

    /// @notice Chainlink BTC/USD price feed address
    /// @dev Cannot be changed after deployment
    address public immutable CHAINLINK_BTC_USD;

    /// @notice Chainlink WBTC/BTC price feed address
    /// @dev Cannot be changed after deployment
    address public immutable CHAINLINK_WBTC_BTC;

    /// @notice Pyth WBTC price feed address
    /// @dev Cannot be changed after deployment
    address public immutable PYTH_WBTC;

    /// @notice Redstone WBTC price feed address
    /// @dev Cannot be changed after deployment
    address public immutable REDSTONE_WBTC;

    /// @notice Chainlink USDC/USD price feed address
    /// @dev Cannot be changed after deployment, used for stablecoin depeg detection
    address public immutable CHAINLINK_USDC_USD;

    /// @notice Chainlink USDT/USD price feed address
    /// @dev Cannot be changed after deployment, used for stablecoin depeg detection
    address public immutable CHAINLINK_USDT_USD;

    // ==================== Core Pool Addresses (deferred binding) ====================

    /// @notice Staking router address - handles staking operation routing
    /// @dev Set once via setPeripheralContracts() and cannot be changed afterward
    address public STAKING_ROUTER;

    /// @notice Farming pool address - BRS liquidity mining
    /// @dev Set once via setPeripheralContracts() and cannot be changed afterward
    address public FARMING_POOL;

    /// @notice stBTD token address - BTD staking receipt
    /// @dev Set once via setPeripheralContracts() and cannot be changed afterward
    address public ST_BTD;

    /// @notice stBTB token address - BTB staking receipt
    /// @dev Set once via setPeripheralContracts() and cannot be changed afterward
    address public ST_BTB;

    /// @notice Governor contract address - DAO governance
    /// @dev Set once via setPeripheralContracts() and cannot be changed afterward
    address public GOVERNOR;

    /// @notice TWAP oracle address - time-weighted average price oracle
    /// @dev Set once via setPeripheralContracts() and cannot be changed afterward
    address public TWAP_ORACLE;

    // ==================== Uniswap V2 Pool Addresses (deferred binding) ====================

    /// @notice WBTC-USDC Uniswap V2 pair address
    /// @dev Set once via setPeripheralContracts() and cannot be changed afterward
    address public POOL_WBTC_USDC;

    /// @notice BTD-USDC Uniswap V2 pair address
    /// @dev Set once via setPeripheralContracts() and cannot be changed afterward
    address public POOL_BTD_USDC;

    /// @notice BTB-BTD Uniswap V2 pair address
    /// @dev Set once via setPeripheralContracts() and cannot be changed afterward
    address public POOL_BTB_BTD;

    /// @notice BRS-BTD Uniswap V2 pair address
    /// @dev Set once via setPeripheralContracts() and cannot be changed afterward
    address public POOL_BRS_BTD;

    /**
     * @notice Constructor - sets all non-circular-dependency addresses
     * @dev The 5 core contracts with circular dependencies are set separately via setCoreContracts()
     * @dev The deployer (msg.sender) is recorded and only they can call setCoreContracts/setPeripheralContracts
     */
    constructor(
        address _wbtc,                 // WBTC token address
        address _btd,                  // BTD stablecoin address
        address _btb,                  // BTB bond token address
        address _brs,                  // BRS governance token address
        address _weth,                 // WETH token address
        address _usdc,                 // USDC token address
        address _usdt,                 // USDT token address
        address _chainlinkBtcUsd,      // Chainlink BTC/USD price feed address
        address _chainlinkWbtcBtc,     // Chainlink WBTC/BTC price feed address
        address _pythWbtc,             // Pyth WBTC price feed address
        address _redstoneWbtc,         // Redstone WBTC price feed address
        address _chainlinkUsdcUsd,     // Chainlink USDC/USD price feed address
        address _chainlinkUsdtUsd      // Chainlink USDT/USD price feed address
    ) {
        require(_wbtc != address(0), "Invalid WBTC");
        require(_btd != address(0), "Invalid BTD");
        require(_btb != address(0), "Invalid BTB");
        require(_brs != address(0), "Invalid BRS");
        require(_weth != address(0), "Invalid WETH");
        require(_usdc != address(0), "Invalid USDC");
        require(_usdt != address(0), "Invalid USDT");
        require(_chainlinkBtcUsd != address(0), "Invalid Chainlink BTC/USD");
        require(_chainlinkWbtcBtc != address(0), "Invalid Chainlink WBTC/BTC");
        require(_pythWbtc != address(0), "Invalid Pyth WBTC");
        require(_redstoneWbtc != address(0), "Invalid Redstone WBTC");
        require(_chainlinkUsdcUsd != address(0), "Invalid Chainlink USDC/USD");
        require(_chainlinkUsdtUsd != address(0), "Invalid Chainlink USDT/USD");

        deployer = msg.sender;
        WBTC = _wbtc;
        BTD = _btd;
        BTB = _btb;
        BRS = _brs;
        WETH = _weth;
        USDC = _usdc;
        USDT = _usdt;
        CHAINLINK_BTC_USD = _chainlinkBtcUsd;
        CHAINLINK_WBTC_BTC = _chainlinkWbtcBtc;
        PYTH_WBTC = _pythWbtc;
        REDSTONE_WBTC = _redstoneWbtc;
        CHAINLINK_USDC_USD = _chainlinkUsdcUsd;
        CHAINLINK_USDT_USD = _chainlinkUsdtUsd;
    }

    /**
     * @notice Sets the 5 core contract addresses with circular dependencies
     * @dev Can only be called once by deployer, permanently locked after deployment
     * @param _treasury Treasury contract address
     * @param _minter Minter contract address
     * @param _priceOracle Price oracle address
     * @param _idealUSDManager IUSD manager address
     * @param _interestPool Interest pool address
     */
    function setCoreContracts(
        address _treasury,
        address _minter,
        address _priceOracle,
        address _idealUSDManager,
        address _interestPool
    ) external onlyDeployer {
        require(!coreContractsSet, "Core contracts already set");
        require(_treasury != address(0), "Invalid Treasury");
        require(_minter != address(0), "Invalid Minter");
        require(_priceOracle != address(0), "Invalid PriceOracle");
        require(_idealUSDManager != address(0), "Invalid IdealUSDManager");
        require(_interestPool != address(0), "Invalid InterestPool");

        TREASURY = _treasury;
        MINTER = _minter;
        PRICE_ORACLE = _priceOracle;
        IDEAL_USD_MANAGER = _idealUSDManager;
        INTEREST_POOL = _interestPool;
        coreContractsSet = true;
    }

    /**
     * @notice Sets peripheral contracts and pools with circular dependencies
     * @dev Can only be called once by deployer, permanently locked after deployment
     */
    function setPeripheralContracts(
        address _stakingRouter,
        address _farmingPool,
        address _stBTD,
        address _stBTB,
        address _governor,
        address _twapOracle,
        address _poolWbtcUsdc,
        address _poolBtdUsdc,
        address _poolBtbBtd,
        address _poolBrsBtd
    ) external onlyDeployer {
        require(!peripheralContractsSet, "Peripheral contracts already set");
        require(_stakingRouter != address(0), "Invalid StakingRouter");
        require(_farmingPool != address(0), "Invalid FarmingPool");
        require(_stBTD != address(0), "Invalid stBTD");
        require(_stBTB != address(0), "Invalid stBTB");
        require(_governor != address(0), "Invalid Governor");
        require(_twapOracle != address(0), "Invalid TWAPOracle");
        require(_poolWbtcUsdc != address(0), "Invalid Pool WBTC/USDC");
        require(_poolBtdUsdc != address(0), "Invalid Pool BTD/USDC");
        require(_poolBtbBtd != address(0), "Invalid Pool BTB/BTD");
        require(_poolBrsBtd != address(0), "Invalid Pool BRS/BTD");

        STAKING_ROUTER = _stakingRouter;
        FARMING_POOL = _farmingPool;
        ST_BTD = _stBTD;
        ST_BTB = _stBTB;
        GOVERNOR = _governor;
        TWAP_ORACLE = _twapOracle;
        POOL_WBTC_USDC = _poolWbtcUsdc;
        POOL_BTD_USDC = _poolBtdUsdc;
        POOL_BTB_BTD = _poolBtbBtd;
        POOL_BRS_BTD = _poolBrsBtd;
        peripheralContractsSet = true;
    }
}
