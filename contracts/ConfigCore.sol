// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title ConfigCore
 * @notice Immutable configuration core - stores critical system addresses
 * @dev Most addresses are immutable (set at deployment), only contracts with
 *      circular dependencies use storage variables set via setCoreContracts()
 *      Owner should call renounceOwnership() after setup is complete
 */
contract ConfigCore is Ownable {

    // ==================== Core Token Addresses ====================
    // All token addresses are immutable, set at deployment

    address public immutable WBTC;    // Wrapped BTC, Collateral token
    address public immutable BTD;     // Primary stablecoin
    address public immutable BTB;     // Bond token
    address public immutable BRS;     // Governance token
    address public immutable WETH;    // Wrapped ETH
    address public immutable USDC;    // Stablecoin reserve
    address public immutable USDT;    // Stablecoin reserve

    // ==================== Uniswap V2 Pool Addresses ====================
    // All pool addresses are immutable, created before ConfigCore deployment

    address public immutable POOL_WBTC_USDC;    // WBTC-USDC pair
    address public immutable POOL_BTD_USDC;     // BTD-USDC pair
    address public immutable POOL_BTB_BTD;      // BTB-BTD pair
    address public immutable POOL_BRS_BTD;      // BRS-BTD pair

    // ==================== Staking Token Addresses ====================
    // Immutable, deployed before ConfigCore

    address public immutable ST_BTD;            // BTD staking receipt token
    address public immutable ST_BTB;            // BTB staking receipt token

    // ==================== Core Contract Addresses ====================
    // These contracts have circular dependencies with ConfigCore
    // Set once via setCoreContracts(), cannot be changed afterward

    address public TREASURY;          // System asset management
    address public MINTER;            // BTD minting and redemption
    address public PRICE_ORACLE;      // WBTC price data
    address public IDEAL_USD_MANAGER; // IUSD inflation adjustments
    address public INTEREST_POOL;     // BTD/BTB interest distribution
    address public FARMING_POOL;      // BRS liquidity mining

    bool public coreContractsSet;

    /**
     * @notice Constructor - sets all immutable addresses
     * @dev Tokens must be deployed first, then LP pools created, then ConfigCore deployed
     *      Core contracts with circular dependencies are set separately via setCoreContracts()
     */
    constructor(
        // Tokens (7)
        address _wbtc,
        address _btd,
        address _btb,
        address _brs,
        address _weth,
        address _usdc,
        address _usdt,
        // Pools (4)
        address _poolWbtcUsdc,
        address _poolBtdUsdc,
        address _poolBtbBtd,
        address _poolBrsBtd,
        // Staking tokens (2)
        address _stBTD,
        address _stBTB
    ) Ownable(msg.sender) {
        // Validate token addresses
        require(_wbtc != address(0), "Invalid WBTC");
        require(_btd != address(0), "Invalid BTD");
        require(_btb != address(0), "Invalid BTB");
        require(_brs != address(0), "Invalid BRS");
        require(_weth != address(0), "Invalid WETH");
        require(_usdc != address(0), "Invalid USDC");
        require(_usdt != address(0), "Invalid USDT");

        // Validate pool addresses
        require(_poolWbtcUsdc != address(0), "Invalid Pool WBTC/USDC");
        require(_poolBtdUsdc != address(0), "Invalid Pool BTD/USDC");
        require(_poolBtbBtd != address(0), "Invalid Pool BTB/BTD");
        require(_poolBrsBtd != address(0), "Invalid Pool BRS/BTD");

        // Validate staking token addresses
        require(_stBTD != address(0), "Invalid stBTD");
        require(_stBTB != address(0), "Invalid stBTB");

        // Set immutable token addresses
        WBTC = _wbtc;
        BTD = _btd;
        BTB = _btb;
        BRS = _brs;
        WETH = _weth;
        USDC = _usdc;
        USDT = _usdt;

        // Set immutable pool addresses
        POOL_WBTC_USDC = _poolWbtcUsdc;
        POOL_BTD_USDC = _poolBtdUsdc;
        POOL_BTB_BTD = _poolBtbBtd;
        POOL_BRS_BTD = _poolBrsBtd;

        // Set immutable staking token addresses
        ST_BTD = _stBTD;
        ST_BTB = _stBTB;
    }

    /**
     * @notice Sets the 6 core contract addresses with circular dependencies
     * @dev Can only be called once by owner
     *      Governor address is managed by ConfigGov for upgradability
     */
    function setCoreContracts(
        address _treasury,
        address _minter,
        address _priceOracle,
        address _idealUSDManager,
        address _interestPool,
        address _farmingPool
    ) external onlyOwner {
        require(!coreContractsSet, "Core contracts already set");
        require(_treasury != address(0), "Invalid Treasury");
        require(_minter != address(0), "Invalid Minter");
        require(_priceOracle != address(0), "Invalid PriceOracle");
        require(_idealUSDManager != address(0), "Invalid IdealUSDManager");
        require(_interestPool != address(0), "Invalid InterestPool");
        require(_farmingPool != address(0), "Invalid FarmingPool");

        TREASURY = _treasury;
        MINTER = _minter;
        PRICE_ORACLE = _priceOracle;
        IDEAL_USD_MANAGER = _idealUSDManager;
        INTEREST_POOL = _interestPool;
        FARMING_POOL = _farmingPool;
        coreContractsSet = true;
    }

    /**
     * @notice Permanently renounce ownership
     * @dev Can only be called after core contracts are set
     */
    function renounceOwnership() public override onlyOwner {
        require(coreContractsSet, "ConfigCore: core contracts not set");
        super.renounceOwnership();
    }
}
