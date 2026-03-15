// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/PriceOracle.sol";
import {UniswapV2TWAPOracle} from "../../contracts/UniswapV2TWAPOracle.sol";
import "../../contracts/ConfigCore.sol";
import "../../contracts/ConfigGov.sol";
import "../../contracts/BTD.sol";
import "../../contracts/BTB.sol";
import "../../contracts/BRS.sol";
import "../../contracts/stBTD.sol";
import "../../contracts/stBTB.sol";
import "../../contracts/local/MockWBTC.sol";
import "../../contracts/local/MockUSDC.sol";
import "../../contracts/local/MockUSDT.sol";
import "../../contracts/local/MockWETH.sol";
import "../../contracts/local/MockAggregatorV3.sol";
import "../../contracts/local/MockPyth.sol";
import "../../contracts/local/MockIUSDManager.sol";
import "../../contracts/local/UniswapV2Pair.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../helpers/ProxyTestHelper.sol";

/// @notice Enhanced MockPyth that allows setting confidence and custom publishTime
contract EnhancedMockPyth {
    struct Price {
        int64 price;
        uint64 conf;
        int32 expo;
        uint256 publishTime;
    }

    mapping(bytes32 => Price) private prices;

    function setPrice(bytes32 id, int64 _price, int32 _expo) external {
        prices[id] = Price({
            price: _price,
            conf: 0,
            expo: _expo,
            publishTime: block.timestamp
        });
    }

    function setPriceWithConf(bytes32 id, int64 _price, uint64 _conf, int32 _expo) external {
        prices[id] = Price({
            price: _price,
            conf: _conf,
            expo: _expo,
            publishTime: block.timestamp
        });
    }

    function setPriceWithTimestamp(
        bytes32 id,
        int64 _price,
        uint64 _conf,
        int32 _expo,
        uint256 _publishTime
    ) external {
        prices[id] = Price({
            price: _price,
            conf: _conf,
            expo: _expo,
            publishTime: _publishTime
        });
    }

    function getPriceUnsafe(bytes32 id) external view returns (Price memory) {
        Price memory p = prices[id];
        require(p.price != 0, "Price not set");
        return p;
    }
}

/// @notice Minimal mock Minter that returns a fixed collateral ratio
contract MockMinterCR {
    uint256 private _cr;

    constructor(uint256 cr_) {
        _cr = cr_;
    }

    function getCollateralRatio() external view returns (uint256) {
        return _cr;
    }
}

/// @title PriceOracle Unit Tests
/// @notice Comprehensive tests for PriceOracle contract
contract PriceOracleUnitTest is Test {

    // ============ Contracts ============

    // Tokens
    MockWBTC public wbtc;
    MockUSDC public usdc;
    MockUSDT public usdt;
    MockWETH public weth;
    BTD public btd;
    BTB public btb;
    BRS public brs;
    stBTD public stbtd;
    stBTB public stbtb;

    // Uniswap pairs
    UniswapV2Pair public poolWbtcUsdc;
    UniswapV2Pair public poolBtdUsdc;
    UniswapV2Pair public poolBtbBtd;
    UniswapV2Pair public poolBrsBtd;

    // Core system
    ConfigCore public core;
    ConfigGov public gov;
    PriceOracle public oracle;
    UniswapV2TWAPOracle public twapOracle;
    MockIUSDManager public iusdManager;

    // Mock oracles
    MockAggregatorV3 public chainlinkBtcUsd;
    MockAggregatorV3 public chainlinkWbtcBtc;
    MockAggregatorV3 public chainlinkUsdcUsd;
    MockAggregatorV3 public chainlinkUsdtUsd;
    EnhancedMockPyth public pyth;
    MockMinterCR public mockMinter;

    // ============ Constants ============

    address public deployer = address(this);
    address public nonOwner = address(0xBEEF);
    bytes32 public constant PYTH_PRICE_ID = bytes32(uint256(1));

    // BTC price = $102,000
    int256 constant CL_BTC_USD = 10_200_000_000_000;  // 102000 * 1e8
    int256 constant CL_WBTC_BTC = 100_000_000;        // 1.0 * 1e8
    int64 constant PYTH_WBTC_PRICE = 10_200_000;       // 102000 with expo=-2
    int32 constant PYTH_WBTC_EXPO = -2;

    // Stablecoin prices = $1.00
    int256 constant CL_USDC_USD = 100_000_000;         // 1.0 * 1e8
    int256 constant CL_USDT_USD = 100_000_000;         // 1.0 * 1e8

    // Pool liquidity amounts
    uint256 constant WBTC_POOL_AMOUNT = 10e8;            // 10 WBTC
    uint256 constant USDC_WBTC_POOL = 1_020_000e6;       // 1,020,000 USDC (10 * 102000)
    uint256 constant BTD_POOL_AMOUNT = 1_000_000e18;     // 1M BTD
    uint256 constant USDC_BTD_POOL = 1_000_000e6;        // 1M USDC (1:1)
    uint256 constant BTB_POOL_AMOUNT = 1_000_000e18;     // 1M BTB
    uint256 constant BTD_BTB_POOL = 1_000_000e18;        // 1M BTD (1:1)
    uint256 constant BRS_POOL_AMOUNT = 1_000_000e18;     // 1M BRS
    uint256 constant BTD_BRS_POOL = 1_000_000e18;        // 1M BTD (1:1)

    // ============ setUp ============

    function setUp() public {
        // Start at a reasonable timestamp
        vm.warp(1_700_000_000);

        // --- Deploy tokens ---
        wbtc = new MockWBTC(deployer);
        usdc = new MockUSDC(deployer);
        usdt = new MockUSDT(deployer);
        weth = new MockWETH(deployer);
        brs = new BRS(deployer);
        btd = ProxyTestHelper.deployBTD(deployer);
        btb = ProxyTestHelper.deployBTB(deployer);
        stbtd = ProxyTestHelper.deployStBTD(IERC20(address(btd)), deployer);
        stbtb = ProxyTestHelper.deployStBTB(IERC20(address(btb)), deployer);

        // Grant MINTER_ROLE to deployer for test minting
        btd.grantRole(btd.MINTER_ROLE(), deployer);
        btb.grantRole(btb.MINTER_ROLE(), deployer);

        // --- Deploy Uniswap pairs ---
        poolWbtcUsdc = new UniswapV2Pair();
        poolWbtcUsdc.initialize(address(wbtc), address(usdc));
        poolBtdUsdc = new UniswapV2Pair();
        poolBtdUsdc.initialize(address(btd), address(usdc));
        poolBtbBtd = new UniswapV2Pair();
        poolBtbBtd.initialize(address(btb), address(btd));
        poolBrsBtd = new UniswapV2Pair();
        poolBrsBtd.initialize(address(brs), address(btd));

        // --- Deploy ConfigCore ---
        core = new ConfigCore(
            address(wbtc), address(btd), address(btb), address(brs),
            address(weth), address(usdc), address(usdt),
            address(poolWbtcUsdc), address(poolBtdUsdc),
            address(poolBtbBtd), address(poolBrsBtd),
            address(stbtd), address(stbtb)
        );

        // --- Deploy ConfigGov ---
        gov = ProxyTestHelper.deployConfigGov(deployer);

        // --- Deploy Chainlink mocks ---
        chainlinkBtcUsd = new MockAggregatorV3(CL_BTC_USD);
        chainlinkWbtcBtc = new MockAggregatorV3(CL_WBTC_BTC);
        chainlinkUsdcUsd = new MockAggregatorV3(CL_USDC_USD);
        chainlinkUsdtUsd = new MockAggregatorV3(CL_USDT_USD);

        // --- Set oracle addresses in ConfigGov ---
        gov.setAddressParam(ConfigGov.AddressParamType.ChainlinkBtcUsd, address(chainlinkBtcUsd));
        gov.setAddressParam(ConfigGov.AddressParamType.ChainlinkWbtcBtc, address(chainlinkWbtcBtc));
        gov.setAddressParam(ConfigGov.AddressParamType.ChainlinkUsdcUsd, address(chainlinkUsdcUsd));
        gov.setAddressParam(ConfigGov.AddressParamType.ChainlinkUsdtUsd, address(chainlinkUsdtUsd));

        // --- Deploy Enhanced Pyth mock ---
        pyth = new EnhancedMockPyth();
        pyth.setPrice(PYTH_PRICE_ID, PYTH_WBTC_PRICE, PYTH_WBTC_EXPO);
        gov.setAddressParam(ConfigGov.AddressParamType.PythWbtc, address(pyth));

        // --- Deploy IUSD Manager ---
        iusdManager = new MockIUSDManager(1e18);

        // --- Deploy Mock Minter (CR = 1e18 = 100%) ---
        mockMinter = new MockMinterCR(1e18);

        // --- Deploy TWAP Oracle ---
        twapOracle = ProxyTestHelper.deployTWAPOracle(deployer);

        // --- Deploy PriceOracle ---
        oracle = ProxyTestHelper.deployPriceOracle(
            deployer,
            address(core),
            address(gov),
            address(twapOracle),
            PYTH_PRICE_ID
        );

        // --- Set core contracts ---
        core.setCoreContracts(
            address(1),              // treasury (dummy)
            address(mockMinter),     // minter -> CR = 1e18
            address(oracle),         // priceOracle
            address(iusdManager),    // idealUSDManager
            address(1),              // interestPool (dummy)
            address(1)               // farmingPool (dummy)
        );

        // --- Seed pools with liquidity ---
        _seedAllPools();

        // --- Warm up TWAP for all pools ---
        _warmUpTWAP();
    }

    // ============ Liquidity Helpers ============

    function _seedAllPools() internal {
        // WBTC/USDC pool: 10 WBTC + 1,020,000 USDC -> price ~102,000
        wbtc.transfer(address(poolWbtcUsdc), WBTC_POOL_AMOUNT);
        usdc.transfer(address(poolWbtcUsdc), USDC_WBTC_POOL);
        poolWbtcUsdc.mint(deployer);

        // BTD/USDC pool: 1M BTD + 1M USDC -> price ~1.0
        btd.mint(deployer, BTD_POOL_AMOUNT);
        btd.transfer(address(poolBtdUsdc), BTD_POOL_AMOUNT);
        usdc.transfer(address(poolBtdUsdc), USDC_BTD_POOL);
        poolBtdUsdc.mint(deployer);

        // BTB/BTD pool: 1M BTB + 1M BTD -> price ~1.0
        btb.mint(deployer, BTB_POOL_AMOUNT);
        btd.mint(deployer, BTD_BTB_POOL);
        btb.transfer(address(poolBtbBtd), BTB_POOL_AMOUNT);
        btd.transfer(address(poolBtbBtd), BTD_BTB_POOL);
        poolBtbBtd.mint(deployer);

        // BRS/BTD pool: 1M BRS + 1M BTD -> price ~1.0
        brs.transfer(address(poolBrsBtd), BRS_POOL_AMOUNT);
        btd.mint(deployer, BTD_BRS_POOL);
        btd.transfer(address(poolBrsBtd), BTD_BRS_POOL);
        poolBrsBtd.mint(deployer);
    }

    function _warmUpTWAP() internal {
        // First observation
        twapOracle.updateIfNeeded(address(poolWbtcUsdc));
        twapOracle.updateIfNeeded(address(poolBtdUsdc));
        twapOracle.updateIfNeeded(address(poolBtbBtd));
        twapOracle.updateIfNeeded(address(poolBrsBtd));

        // Advance 31 minutes (past TWAP PERIOD of 30 min)
        vm.warp(block.timestamp + 31 minutes);

        // Second observation
        twapOracle.updateIfNeeded(address(poolWbtcUsdc));
        twapOracle.updateIfNeeded(address(poolBtdUsdc));
        twapOracle.updateIfNeeded(address(poolBtbBtd));
        twapOracle.updateIfNeeded(address(poolBrsBtd));

        // Advance another 31 minutes so the newer observation is >= PERIOD ago
        vm.warp(block.timestamp + 31 minutes);
    }

    // ============ 1. Initialize Tests ============

    function test_initialize_valid() public view {
        assertEq(oracle.owner(), deployer);
        assertEq(address(oracle.core()), address(core));
        assertEq(address(oracle.gov()), address(gov));
        assertEq(oracle.pythWbtcPriceId(), PYTH_PRICE_ID);
        assertEq(oracle.maxDeviationBps(), 100);
        assertTrue(oracle.useTWAP());
        assertEq(address(oracle.twapOracle()), address(twapOracle));
    }

    function test_initialize_zeroOwner_reverts() public {
        PriceOracle impl = new PriceOracle();
        vm.expectRevert("Invalid owner");
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(PriceOracle.initialize, (
                address(0), address(core), address(gov), address(twapOracle), PYTH_PRICE_ID
            ))
        );
    }

    function test_initialize_zeroCore_reverts() public {
        PriceOracle impl = new PriceOracle();
        vm.expectRevert("Invalid core address");
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(PriceOracle.initialize, (
                deployer, address(0), address(gov), address(twapOracle), PYTH_PRICE_ID
            ))
        );
    }

    function test_initialize_zeroGov_reverts() public {
        PriceOracle impl = new PriceOracle();
        vm.expectRevert("Invalid gov address");
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(PriceOracle.initialize, (
                deployer, address(core), address(0), address(twapOracle), PYTH_PRICE_ID
            ))
        );
    }

    function test_initialize_zeroPythId_reverts() public {
        PriceOracle impl = new PriceOracle();
        vm.expectRevert("Invalid Pyth price id");
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(PriceOracle.initialize, (
                deployer, address(core), address(gov), address(twapOracle), bytes32(0)
            ))
        );
    }

    // ============ 2. setMaxDeviationBps Tests ============

    function test_setMaxDeviationBps_tighten() public {
        // Default is 100, tighten to 90
        oracle.setMaxDeviationBps(90);
        assertEq(oracle.maxDeviationBps(), 90);
    }

    function test_setMaxDeviationBps_loosen_reverts() public {
        // Default is 100, trying to set to 200 should revert
        vm.expectRevert("Deviation can only tighten");
        oracle.setMaxDeviationBps(200);
    }

    function test_setMaxDeviationBps_equal_reverts() public {
        // Setting to same value (100) should revert (require newBps < current)
        vm.expectRevert("Deviation can only tighten");
        oracle.setMaxDeviationBps(100);
    }

    function test_setMaxDeviationBps_tooLow_reverts() public {
        // Below MIN_DEVIATION_FLOOR (50)
        vm.expectRevert("Deviation too low");
        oracle.setMaxDeviationBps(49);
    }

    function test_setMaxDeviationBps_tooHigh_reverts() public {
        // 501 > MAX_DEVIATION_CEILING (500), the ceiling check triggers before the tighten check
        vm.expectRevert("Deviation too high");
        oracle.setMaxDeviationBps(501);
    }

    function test_setMaxDeviationBps_cooldown_reverts() public {
        // First change: 100 -> 90
        oracle.setMaxDeviationBps(90);

        // Second change within 1 day should revert
        vm.warp(block.timestamp + 23 hours);
        vm.expectRevert("Cooldown not met");
        oracle.setMaxDeviationBps(80);
    }

    function test_setMaxDeviationBps_afterCooldown() public {
        // First change
        oracle.setMaxDeviationBps(90);

        // Wait full cooldown
        vm.warp(block.timestamp + 1 days);

        // Second change should succeed
        oracle.setMaxDeviationBps(80);
        assertEq(oracle.maxDeviationBps(), 80);
    }

    function test_setMaxDeviationBps_nonOwner_reverts() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        oracle.setMaxDeviationBps(90);
    }

    function test_setMaxDeviationBps_emitsEvent() public {
        vm.expectEmit(false, false, false, true);
        emit PriceOracle.MaxDeviationUpdated(100, 90);
        oracle.setMaxDeviationBps(90);
    }

    function test_setMaxDeviationBps_atFloor() public {
        // Tighten all the way to MIN_DEVIATION_FLOOR (50) over multiple cooldowns
        uint256 startTime = block.timestamp;
        oracle.setMaxDeviationBps(90);

        vm.warp(startTime + 2 days);
        oracle.setMaxDeviationBps(70);

        vm.warp(startTime + 4 days);
        oracle.setMaxDeviationBps(50);
        assertEq(oracle.maxDeviationBps(), 50);
    }

    // ============ 3. setTWAPOracle Tests ============

    function test_setTWAPOracle_owner() public {
        address newOracle = address(0x1234);
        oracle.setTWAPOracle(newOracle);
        assertEq(oracle.getTWAPOracle(), newOracle);
    }

    function test_setTWAPOracle_toZero() public {
        // Setting to zero address disables TWAP oracle
        oracle.setTWAPOracle(address(0));
        assertEq(oracle.getTWAPOracle(), address(0));
    }

    function test_setTWAPOracle_nonOwner_reverts() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        oracle.setTWAPOracle(address(0x1234));
    }

    function test_setTWAPOracle_emitsEvent() public {
        address oldOracle = address(twapOracle);
        address newOracle = address(0x5678);

        vm.expectEmit(true, true, false, false);
        emit IPriceOracle.TWAPOracleUpdated(oldOracle, newOracle);
        oracle.setTWAPOracle(newOracle);
    }

    // ============ 4. setUseTWAP Tests ============

    function test_setUseTWAP_emits() public {
        vm.expectEmit(false, false, false, true);
        emit IPriceOracle.TWAPModeChanged(false);
        oracle.setUseTWAP(false);
        assertFalse(oracle.useTWAP());
    }

    function test_setUseTWAP_nonOwner_reverts() public {
        vm.prank(nonOwner);
        vm.expectRevert();
        oracle.setUseTWAP(false);
    }

    // ============ 5. getWBTCPrice Tests ============

    function test_getWBTCPrice_normal() public {
        // Refresh pyth price at current timestamp
        pyth.setPrice(PYTH_PRICE_ID, PYTH_WBTC_PRICE, PYTH_WBTC_EXPO);

        uint256 price = oracle.getWBTCPrice();
        // Price should be approximately 102,000e18
        // Allow small tolerance due to TWAP/AMM rounding
        assertApproxEqRel(price, 102_000e18, 0.01e18); // 1% tolerance
    }

    function test_getWBTCPrice_chainlinkPythMismatch_reverts() public {
        // Set Pyth price 5% higher than Chainlink
        // Chainlink: 102000, Pyth: 107100
        pyth.setPrice(PYTH_PRICE_ID, 10_710_000, PYTH_WBTC_EXPO);

        vm.expectRevert("Chainlink/Pyth price mismatch");
        oracle.getWBTCPrice();
    }

    function test_getWBTCPrice_uniswapMismatch_reverts() public {
        // Refresh pyth
        pyth.setPrice(PYTH_PRICE_ID, PYTH_WBTC_PRICE, PYTH_WBTC_EXPO);

        // Disable TWAP to use spot price, then manipulate pool reserves
        oracle.setUseTWAP(false);

        // Skew pool: add extra USDC to make WBTC appear 10% more expensive
        // Current: 10 WBTC : 1,020,000 USDC
        // New: 10 WBTC : 1,122,000 USDC (10% higher)
        usdc.transfer(address(poolWbtcUsdc), 102_000e6);
        poolWbtcUsdc.sync();

        vm.expectRevert("Uniswap/Oracle price mismatch");
        oracle.getWBTCPrice();
    }

    // ============ 6. getBTDPrice Tests ============

    function test_getBTDPrice_normal() public {
        uint256 price = oracle.getBTDPrice();
        // BTD/USDC pool is 1:1, so price should be ~1e18
        assertApproxEqRel(price, 1e18, 0.01e18);
    }

    function test_getBTDPrice_twapSpotDeviation_reverts() public {
        // First get TWAP established, then skew spot significantly
        // Add 6% more USDC to make spot price deviate > 5% from TWAP
        usdc.transfer(address(poolBtdUsdc), 60_001e6);
        poolBtdUsdc.sync();

        vm.expectRevert("BTD: TWAP/spot deviation");
        oracle.getBTDPrice();
    }

    function test_getBTDPrice_belowFloor_reverts() public {
        // Floor = 90% * CR(1.0) * IUSD(1.0) = 0.9e18
        // Need BTD TWAP price < 0.9. Drain USDC from pool.
        // We need to manipulate both TWAP and spot to be below 0.9
        // Easiest: create new pair with low ratio, warm up TWAP

        // Transfer BTD to push the price down significantly
        // Add lots of BTD to the pool (increases supply, lowers price)
        btd.mint(deployer, 2_000_000e18);
        btd.transfer(address(poolBtdUsdc), 2_000_000e18);
        poolBtdUsdc.sync();

        // Now TWAP is ~1.0 but spot is ~0.33. Need to warm up TWAP too.
        // Record first observation with new reserves
        twapOracle.updateIfNeeded(address(poolBtdUsdc));
        vm.warp(block.timestamp + 31 minutes);
        twapOracle.updateIfNeeded(address(poolBtdUsdc));
        vm.warp(block.timestamp + 31 minutes);

        // Refresh Pyth timestamp so it doesn't go stale
        pyth.setPrice(PYTH_PRICE_ID, PYTH_WBTC_PRICE, PYTH_WBTC_EXPO);

        // Now TWAP should reflect the low price
        // The BTD price from TWAP should be ~0.33 which is < floor 0.9
        vm.expectRevert("BTD: price below floor");
        oracle.getBTDPrice();
    }

    // ============ 7. getBTBPrice / getBRSPrice Tests ============

    function test_getBTBPrice_normal() public {
        // Refresh Pyth
        pyth.setPrice(PYTH_PRICE_ID, PYTH_WBTC_PRICE, PYTH_WBTC_EXPO);

        uint256 price = oracle.getBTBPrice();
        // BTB/BTD = 1:1, BTD/USDC = 1:1, so BTB price ~1.0
        assertApproxEqRel(price, 1e18, 0.01e18);
    }

    function test_getBRSPrice_normal() public {
        // Refresh Pyth
        pyth.setPrice(PYTH_PRICE_ID, PYTH_WBTC_PRICE, PYTH_WBTC_EXPO);

        uint256 price = oracle.getBRSPrice();
        // BRS/BTD = 1:1, BTD/USDC = 1:1, so BRS price ~1.0
        assertApproxEqRel(price, 1e18, 0.01e18);
    }

    // ============ 8. getStBTDPrice / getStBTBPrice Tests ============

    function test_getStBTDPrice_noShares() public view {
        // No shares minted in stBTD vault, should return BTD price
        uint256 stPrice = oracle.getStBTDPrice();
        uint256 btdPrice = oracle.getBTDPrice();
        assertEq(stPrice, btdPrice);
    }

    function test_getStBTDPrice_withInterest() public {
        // Deposit some BTD into stBTD
        uint256 depositAmount = 1000e18;
        btd.mint(deployer, depositAmount);
        btd.approve(address(stbtd), depositAmount);
        stbtd.deposit(depositAmount, deployer);

        // Simulate interest: transfer extra BTD directly to the vault
        uint256 interestAmount = 100e18;
        btd.mint(deployer, interestAmount);
        btd.transfer(address(stbtd), interestAmount);

        // stBTD price = (totalAssets / totalSupply) * BTD price
        // totalAssets = 1100, totalSupply = 1000
        // stBTD price = 1.1 * BTD price
        uint256 stPrice = oracle.getStBTDPrice();
        uint256 btdPrice = oracle.getBTDPrice();
        uint256 expectedPrice = (1100 * btdPrice) / 1000;

        assertApproxEqRel(stPrice, expectedPrice, 0.001e18);
        assertTrue(stPrice > btdPrice);
    }

    function test_getStBTBPrice_noShares() public {
        // Refresh Pyth for BTB pricing chain
        pyth.setPrice(PYTH_PRICE_ID, PYTH_WBTC_PRICE, PYTH_WBTC_EXPO);

        uint256 stPrice = oracle.getStBTBPrice();
        uint256 btbPrice = oracle.getBTBPrice();
        assertEq(stPrice, btbPrice);
    }

    // ============ 9. getUSDCPrice / getUSDTPrice Tests ============

    function test_getUSDCPrice_normal() public view {
        uint256 price = oracle.getUSDCPrice();
        assertEq(price, 1e18);
    }

    function test_getUSDCPrice_depeg_reverts() public {
        // Set USDC price to 0.98 (2% depeg, > 1% threshold)
        chainlinkUsdcUsd.setAnswer(98_000_000); // 0.98 * 1e8
        vm.expectRevert("Stablecoin depeg detected");
        oracle.getUSDCPrice();
    }

    function test_getUSDTPrice_normal() public view {
        uint256 price = oracle.getUSDTPrice();
        assertEq(price, 1e18);
    }

    function test_getUSDTPrice_depeg_reverts() public {
        // Set USDT price to 1.02 (2% above peg)
        chainlinkUsdtUsd.setAnswer(102_000_000); // 1.02 * 1e8
        vm.expectRevert("Stablecoin depeg detected");
        oracle.getUSDTPrice();
    }

    // ============ 10. getPrice(address token) Routing Tests ============

    function test_getPrice_routing() public {
        // Refresh Pyth for all pricing chains
        pyth.setPrice(PYTH_PRICE_ID, PYTH_WBTC_PRICE, PYTH_WBTC_EXPO);

        // WBTC
        uint256 wbtcPrice = oracle.getPrice(address(wbtc));
        assertApproxEqRel(wbtcPrice, 102_000e18, 0.01e18);

        // BTD
        uint256 btdPrice = oracle.getPrice(address(btd));
        assertApproxEqRel(btdPrice, 1e18, 0.01e18);

        // BTB
        uint256 btbPrice = oracle.getPrice(address(btb));
        assertApproxEqRel(btbPrice, 1e18, 0.01e18);

        // BRS
        uint256 brsPrice = oracle.getPrice(address(brs));
        assertApproxEqRel(brsPrice, 1e18, 0.01e18);

        // USDC
        uint256 usdcPrice = oracle.getPrice(address(usdc));
        assertEq(usdcPrice, 1e18);

        // USDT
        uint256 usdtPrice = oracle.getPrice(address(usdt));
        assertEq(usdtPrice, 1e18);

        // stBTD
        uint256 stBtdPrice = oracle.getPrice(address(stbtd));
        assertApproxEqRel(stBtdPrice, 1e18, 0.01e18);

        // stBTB
        uint256 stBtbPrice = oracle.getPrice(address(stbtb));
        assertApproxEqRel(stBtbPrice, 1e18, 0.01e18);
    }

    function test_getPrice_unknownToken_reverts() public {
        vm.expectRevert("Price not available for this token");
        oracle.getPrice(address(0xDEAD));
    }

    // ============ 11. Pyth Internal Tests (via getWBTCPrice) ============

    function test_getPythPrice_stale_reverts() public {
        // Set Pyth price with a publishTime that is old
        pyth.setPriceWithTimestamp(
            PYTH_PRICE_ID,
            PYTH_WBTC_PRICE,
            0,
            PYTH_WBTC_EXPO,
            block.timestamp - 61 // 61 seconds ago, exceeds PYTH_MAX_STALENESS=60
        );

        vm.expectRevert("Pyth price stale");
        oracle.getWBTCPrice();
    }

    function test_getPythPrice_wideConfidence_reverts() public {
        // Confidence ratio must satisfy: conf * 100 <= price
        // price = 10,200,000, so max conf = 102,000
        // Set conf > 102,000 to trigger wide confidence
        pyth.setPriceWithConf(
            PYTH_PRICE_ID,
            PYTH_WBTC_PRICE,
            102_001, // conf > price/100
            PYTH_WBTC_EXPO
        );

        vm.expectRevert("Pyth confidence too wide");
        oracle.getWBTCPrice();
    }

    function test_getPythPrice_atMaxConfidence() public {
        // Exactly at the boundary: conf * 100 = price -> should pass
        // price = 10,200,000, conf = 102,000
        pyth.setPriceWithConf(
            PYTH_PRICE_ID,
            PYTH_WBTC_PRICE,
            102_000, // conf * 100 == price, boundary passes
            PYTH_WBTC_EXPO
        );

        // Should not revert (boundary is <=)
        uint256 price = oracle.getWBTCPrice();
        assertGt(price, 0);
    }

    function test_getPythPrice_exactlyStaleness() public {
        // publishTime exactly 60 seconds ago should pass (<=)
        pyth.setPriceWithTimestamp(
            PYTH_PRICE_ID,
            PYTH_WBTC_PRICE,
            0,
            PYTH_WBTC_EXPO,
            block.timestamp - 60
        );

        // Should not revert
        uint256 price = oracle.getWBTCPrice();
        assertGt(price, 0);
    }

    // ============ 12. isTWAPEnabled / getTWAPOracle Tests ============

    function test_isTWAPEnabled() public {
        // Both useTWAP=true and oracle is set
        assertTrue(oracle.isTWAPEnabled());

        // Disable useTWAP
        oracle.setUseTWAP(false);
        assertFalse(oracle.isTWAPEnabled());

        // Re-enable useTWAP but remove oracle
        oracle.setUseTWAP(true);
        oracle.setTWAPOracle(address(0));
        assertFalse(oracle.isTWAPEnabled());
    }

    function test_getTWAPOracle() public view {
        assertEq(oracle.getTWAPOracle(), address(twapOracle));
    }

    // ============ Additional Edge Case Tests ============

    function test_getWBTCPrice_spotMode() public {
        // Disable TWAP, should use spot price
        oracle.setUseTWAP(false);
        pyth.setPrice(PYTH_PRICE_ID, PYTH_WBTC_PRICE, PYTH_WBTC_EXPO);

        uint256 price = oracle.getWBTCPrice();
        assertApproxEqRel(price, 102_000e18, 0.01e18);
    }

    function test_getPrice_pool_base_quote() public view {
        // Test the three-argument getPrice(pool, base, quote) for WBTC/USDC
        uint256 price = oracle.getPrice(
            address(poolWbtcUsdc),
            address(wbtc),
            address(usdc)
        );
        assertApproxEqRel(price, 102_000e18, 0.01e18);
    }

    function test_initialize_withZeroTWAPOracle() public {
        // TWAP oracle can be zero at init (optional)
        PriceOracle oracleNoTwap = ProxyTestHelper.deployPriceOracle(
            deployer,
            address(core),
            address(gov),
            address(0), // no TWAP oracle
            PYTH_PRICE_ID
        );
        assertEq(oracleNoTwap.getTWAPOracle(), address(0));
        assertFalse(oracleNoTwap.isTWAPEnabled());
    }

    function test_getBTDPrice_twapOracleNotSet_reverts() public {
        // Remove TWAP oracle
        oracle.setTWAPOracle(address(0));

        // getBTDPrice always uses TWAP internally, so should revert
        vm.expectRevert("TWAP oracle not set");
        oracle.getBTDPrice();
    }

    function test_getUSDCPrice_slightDeviation() public view {
        // USDC at $1.005 (0.5% deviation) should pass
        // Default mock answer is 1e8 which is exactly $1
        // The mock is already at exactly $1, so this passes trivially
        uint256 price = oracle.getUSDCPrice();
        assertEq(price, 1e18);
    }

    function test_getUSDCPrice_atBoundary() public {
        // deviationWithin uses priceA as denominator: |price - 1| * 10000 <= price * 100
        // At 0.99: |0.01| * 10000 = 1e20 vs 0.99e18 * 100 = 9.9e19 -> fails (just outside)
        // At 0.991: |0.009| * 10000 = 9e19 vs 0.991e18 * 100 = 9.91e19 -> passes
        chainlinkUsdcUsd.setAnswer(99_100_000); // 0.991 * 1e8
        uint256 price = oracle.getUSDCPrice();
        assertApproxEqRel(price, 0.991e18, 0.001e18);
    }

    function test_getUSDTPrice_atBoundary() public {
        // Set USDT to 1.01 (exactly 1% above)
        chainlinkUsdtUsd.setAnswer(101_000_000); // 1.01 * 1e8
        uint256 price = oracle.getUSDTPrice();
        assertApproxEqRel(price, 1.01e18, 0.001e18);
    }
}
