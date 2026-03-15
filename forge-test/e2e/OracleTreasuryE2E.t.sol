// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/PriceOracle.sol";
import {UniswapV2TWAPOracle} from "../../contracts/UniswapV2TWAPOracle.sol";
import "../../contracts/Treasury.sol";
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
import "../../contracts/local/MockIUSDManager.sol";
import "../../contracts/local/UniswapV2Pair.sol";
import "../../contracts/libraries/Constants.sol";
import "../helpers/ProxyTestHelper.sol";

/// @notice Minimal mock Minter that returns a fixed collateral ratio
contract MockMinterCR {
    uint256 private _cr;

    constructor(uint256 cr_) {
        _cr = cr_;
    }

    function getCollateralRatio() external view returns (uint256) {
        return _cr;
    }

    function setCR(uint256 cr_) external {
        _cr = cr_;
    }
}

/// @title Oracle + Treasury End-to-End Integration Test
/// @notice Tests real PriceOracle + UniswapV2TWAPOracle + Treasury with mock feeds and tokens
contract OracleTreasuryE2ETest is Test {

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
    UniswapV2TWAPOracle public twapOracle;
    PriceOracle public oracle;
    Treasury public treasury;
    MockMinterCR public mockMinter;
    MockIUSDManager public iusdManager;

    // Chainlink mocks
    MockAggregatorV3 public chainlinkBtcUsd;
    MockAggregatorV3 public chainlinkWbtcBtc;
    MockAggregatorV3 public chainlinkUsdcUsd;
    MockAggregatorV3 public chainlinkUsdtUsd;

    // ============ Actors ============

    address public deployer = address(this);
    address public alice = address(0xA11CE);
    address public mockRouter = address(0xDEAD);

    // ============ Constants ============

    uint256 constant START_TIME = 1_700_000_000;

    // ============ setUp ============

    function setUp() public {
        vm.warp(START_TIME);

        // --- Phase 1: Deploy mock external tokens ---
        wbtc = new MockWBTC(deployer);
        usdc = new MockUSDC(deployer);
        usdt = new MockUSDT(deployer);
        weth = new MockWETH(deployer);

        // --- Phase 2: Deploy core tokens ---
        brs = new BRS(deployer);
        btd = ProxyTestHelper.deployBTD(deployer);
        btb = ProxyTestHelper.deployBTB(deployer);

        // --- Phase 2.5: Staking tokens ---
        stbtd = ProxyTestHelper.deployStBTD(IERC20(address(btd)), deployer);
        stbtb = ProxyTestHelper.deployStBTB(IERC20(address(btb)), deployer);

        // --- Phase 3: Mint tokens for pool liquidity ---
        // BTD and BTB need MINTER_ROLE to mint
        bytes32 minterRole = btd.MINTER_ROLE();
        btd.grantRole(minterRole, deployer);
        btb.grantRole(btb.MINTER_ROLE(), deployer);
        btd.mint(deployer, 500_000e18);
        btb.mint(deployer, 500_000e18);

        // --- Phase 4: Deploy Uniswap V2 pairs with correct token ordering ---
        poolWbtcUsdc = _createAndFundPair(
            address(wbtc), address(usdc),
            1e8,    // 1 WBTC
            100_000e6 // 100,000 USDC
        );

        poolBtdUsdc = _createAndFundPair(
            address(btd), address(usdc),
            100_000e18, // 100,000 BTD
            100_000e6   // 100,000 USDC
        );

        poolBtbBtd = _createAndFundPair(
            address(btb), address(btd),
            100_000e18, // 100,000 BTB
            100_000e18  // 100,000 BTD
        );

        poolBrsBtd = _createAndFundPair(
            address(brs), address(btd),
            100_000e18, // 100,000 BRS
            100_000e18  // 100,000 BTD
        );

        // --- Phase 5: ConfigCore ---
        core = new ConfigCore(
            address(wbtc), address(btd), address(btb), address(brs),
            address(weth), address(usdc), address(usdt),
            address(poolWbtcUsdc), address(poolBtdUsdc),
            address(poolBtbBtd), address(poolBrsBtd),
            address(stbtd), address(stbtb)
        );

        // --- Phase 6: ConfigGov ---
        gov = ProxyTestHelper.deployConfigGov(deployer);

        // --- Phase 7: Deploy Chainlink mocks ---
        chainlinkBtcUsd = new MockAggregatorV3(100_000 * 1e8);   // $100,000
        chainlinkWbtcBtc = new MockAggregatorV3(1e8);            // 1:1 WBTC/BTC
        chainlinkUsdcUsd = new MockAggregatorV3(1e8);            // $1.00
        chainlinkUsdtUsd = new MockAggregatorV3(1e8);            // $1.00

        // --- Phase 9: Set oracle addresses in ConfigGov ---
        gov.setAddressParam(ConfigGov.AddressParamType.ChainlinkBtcUsd, address(chainlinkBtcUsd));
        gov.setAddressParam(ConfigGov.AddressParamType.ChainlinkWbtcBtc, address(chainlinkWbtcBtc));
        gov.setAddressParam(ConfigGov.AddressParamType.ChainlinkUsdcUsd, address(chainlinkUsdcUsd));
        gov.setAddressParam(ConfigGov.AddressParamType.ChainlinkUsdtUsd, address(chainlinkUsdtUsd));

        // --- Phase 10: Deploy TWAP Oracle ---
        twapOracle = ProxyTestHelper.deployTWAPOracle(deployer);

        // --- Phase 11: Deploy PriceOracle (real, via proxy) ---
        oracle = ProxyTestHelper.deployPriceOracle(
            deployer,
            address(core),
            address(gov),
            address(twapOracle)
        );

        // --- Phase 12: Deploy Treasury ---
        treasury = ProxyTestHelper.deployTreasury(deployer, address(core), mockRouter);

        // --- Phase 13: Deploy Mock Minter (CR = 100%) ---
        mockMinter = new MockMinterCR(1e18);

        // --- Phase 14: Deploy Mock IUSD Manager ($1.00) ---
        iusdManager = new MockIUSDManager(1e18);

        // --- Phase 15: Set core contracts in ConfigCore ---
        core.setCoreContracts(
            address(treasury),
            address(mockMinter),
            address(oracle),
            address(iusdManager),
            address(0x1111), // interestPool placeholder
            address(0x2222)  // farmingPool placeholder
        );
        core.renounceOwnership();

        // --- Phase 16: TWAP warmup for all 4 pairs ---
        _warmupTWAP(address(poolWbtcUsdc));
        _warmupTWAP(address(poolBtdUsdc));
        _warmupTWAP(address(poolBtbBtd));
        _warmupTWAP(address(poolBrsBtd));

        // --- Phase 17: Fund test users ---
        wbtc.transfer(alice, 100e8); // 100 WBTC
        brs.transfer(address(treasury), 10_000e18); // BRS for compensation tests
    }

    // ============ Helpers ============

    /// @notice Create a UniswapV2Pair with correct token ordering and fund it
    function _createAndFundPair(
        address tokenA,
        address tokenB,
        uint256 amountA,
        uint256 amountB
    ) internal returns (UniswapV2Pair pair) {
        pair = new UniswapV2Pair();

        // Sort tokens by address (lower address = token0)
        (address token0, address token1, uint256 amount0, uint256 amount1) =
            tokenA < tokenB
                ? (tokenA, tokenB, amountA, amountB)
                : (tokenB, tokenA, amountB, amountA);

        pair.initialize(token0, token1);

        // Transfer tokens and mint LP
        IERC20(token0).transfer(address(pair), amount0);
        IERC20(token1).transfer(address(pair), amount1);
        pair.mint(deployer);
    }

    /// @notice Warm up TWAP for a pair so it becomes queryable
    /// @dev Requires two observations separated by >= PERIOD (30 min)
    function _warmupTWAP(address pair) internal {
        uint256 currentTime = block.timestamp;

        // First observation
        vm.warp(currentTime);
        twapOracle.updateIfNeeded(pair);

        // Second observation after PERIOD
        vm.warp(currentTime + 31 minutes);
        twapOracle.updateIfNeeded(pair);

        // Advance past second observation so getTWAP can use it as ref
        vm.warp(currentTime + 62 minutes);
    }

    // ============================================================
    //           Scenario 1: WBTC price query (all sources agree)
    // ============================================================

    /// @notice When Chainlink and TWAP agree on ~$100k, getWBTCPrice succeeds
    function test_scenario1_wbtcPriceNormal() public view {
        uint256 price = oracle.getWBTCPrice();
        // Should return TWAP price close to $100,000
        assertApproxEqRel(price, 100_000e18, 0.05e18, "WBTC price should be ~$100,000");
    }

    // ============================================================
    //           Scenario 2: BTD price query
    // ============================================================

    /// @notice BTD price should be ~$1.00 from the BTD/USDC pool
    function test_scenario2_btdPrice() public view {
        uint256 price = oracle.getBTDPrice();
        assertApproxEqRel(price, 1e18, 0.05e18, "BTD price should be ~$1.00");
    }

    // ============================================================
    //           Scenario 3: TWAP warmup flow
    // ============================================================

    /// @notice Verify that a fresh pair's TWAP transitions from not-ready to ready
    function test_scenario3_twapWarmupFlow() public {
        // Deploy a fresh pair
        UniswapV2Pair freshPair = new UniswapV2Pair();

        // Sort tokens for this pair
        (address t0, address t1) = address(btd) < address(usdc)
            ? (address(btd), address(usdc))
            : (address(usdc), address(btd));
        freshPair.initialize(t0, t1);

        // Fund the pair
        uint256 btdAmount = 50_000e18;
        uint256 usdcAmount = 50_000e6;
        btd.mint(deployer, btdAmount);

        if (t0 == address(btd)) {
            btd.transfer(address(freshPair), btdAmount);
            usdc.transfer(address(freshPair), usdcAmount);
        } else {
            usdc.transfer(address(freshPair), usdcAmount);
            btd.transfer(address(freshPair), btdAmount);
        }
        freshPair.mint(deployer);

        // TWAP should NOT be ready yet
        assertFalse(twapOracle.isTWAPReady(address(freshPair)), "TWAP should not be ready before warmup");

        // First observation
        uint256 t = block.timestamp;
        vm.warp(t + 1);
        twapOracle.updateIfNeeded(address(freshPair));

        // Still not ready (need PERIOD to pass)
        assertFalse(twapOracle.isTWAPReady(address(freshPair)), "TWAP should not be ready after first observation");

        // Second observation after PERIOD
        vm.warp(t + 1 + 31 minutes);
        twapOracle.updateIfNeeded(address(freshPair));

        // Advance time past PERIOD from the second observation
        vm.warp(t + 1 + 62 minutes);

        // Now TWAP should be ready
        assertTrue(twapOracle.isTWAPReady(address(freshPair)), "TWAP should be ready after warmup");
    }

    // ============================================================
    //           Scenario 4: Oracle price deviation blocks query
    // ============================================================

    /// @notice When Chainlink and Uniswap prices diverge beyond maxDeviationBps, getWBTCPrice reverts
    function test_scenario4_deviationBlocks() public {
        // Change Chainlink BTC/USD to $105,000 (+5%)
        chainlinkBtcUsd.setAnswer(105_000 * 1e8);
        // Uniswap pool stays at $100,000
        // Default maxDeviationBps is 100 (1%), so 5% deviation should revert

        vm.expectRevert("Uniswap/Chainlink price mismatch");
        oracle.getWBTCPrice();
    }

    // ============================================================
    //           Scenario 5: Treasury deposit and balance check
    // ============================================================

    /// @notice Deposit WBTC to treasury as minter and verify balance
    function test_scenario5_treasuryDepositBalance() public {
        address minterAddr = address(mockMinter);

        // Fund the minter with WBTC
        wbtc.transfer(minterAddr, 1e8);

        vm.startPrank(minterAddr);
        wbtc.approve(address(treasury), 1e8);
        treasury.depositWBTC(1e8);
        vm.stopPrank();

        (uint256 wbtcBal, , ) = treasury.getBalances();
        assertEq(wbtcBal, 1e8, "Treasury should hold 1 WBTC");
    }

    // ============================================================
    //           Scenario 6: Treasury withdraw
    // ============================================================

    /// @notice Deposit WBTC then partially withdraw, verify remaining balance
    function test_scenario6_treasuryWithdraw() public {
        address minterAddr = address(mockMinter);

        // Fund the minter with WBTC
        wbtc.transfer(minterAddr, 1e8);

        vm.startPrank(minterAddr);
        wbtc.approve(address(treasury), 1e8);
        treasury.depositWBTC(1e8);
        treasury.withdrawWBTC(5e7);
        vm.stopPrank();

        (uint256 wbtcBal, , ) = treasury.getBalances();
        assertEq(wbtcBal, 5e7, "Treasury should hold 0.5 WBTC after withdrawal");
    }

    // ============================================================
    //           Scenario 7: BRS compensation
    // ============================================================

    /// @notice Compensate a user with BRS from treasury (as minter)
    function test_scenario7_brsCompensation() public {
        address minterAddr = address(mockMinter);

        vm.prank(minterAddr);
        treasury.compensate(alice, 500e18);

        assertEq(brs.balanceOf(alice), 500e18, "Alice should receive 500 BRS");
    }

    // ============================================================
    //           Scenario 8: Chain pricing (BTB, BRS via BTD)
    // ============================================================

    /// @notice BTB and BRS prices should be ~$1 since they are 1:1 with BTD
    function test_scenario8_chainPricing() public view {
        uint256 btbPrice = oracle.getBTBPrice();
        uint256 brsPrice = oracle.getBRSPrice();

        // Both should be ~$1 since 1:1 with BTD and BTD ~$1
        assertApproxEqRel(btbPrice, 1e18, 0.1e18, "BTB price should be ~$1.00");
        assertApproxEqRel(brsPrice, 1e18, 0.1e18, "BRS price should be ~$1.00");
    }
}
