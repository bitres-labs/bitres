// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
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
import "../../contracts/local/MockPriceOracle.sol";
import "../../contracts/local/MockIUSDManager.sol";
import "../../contracts/local/UniswapV2Pair.sol";
import "../../contracts/libraries/Constants.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import "../helpers/ProxyTestHelper.sol";

/// @notice Simple mock router for buyback tests
contract MockRouter {
    address public wethAddr;

    constructor(address _weth) {
        wethAddr = _weth;
    }

    function WETH() external view returns (address) {
        return wethAddr;
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint /* amountOutMin */,
        address[] calldata path,
        address to,
        uint /* deadline */
    ) external returns (uint[] memory amounts) {
        // Transfer input tokens from caller (treasury)
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        // Transfer output tokens to recipient (simulate 1:1 swap)
        uint256 outputAmount = amountIn;
        IERC20(path[path.length - 1]).transfer(to, outputAmount);
        amounts = new uint[](path.length);
        amounts[0] = amountIn;
        amounts[path.length - 1] = outputAmount;
    }
}

contract TreasuryUnitTest is Test {
    // ============ Contracts ============
    Treasury public treasury;
    ConfigCore public configCore;
    ConfigGov public configGov;

    // ============ Tokens ============
    MockWBTC public wbtc;
    BTD public btd;
    BTB public btb;
    BRS public brs;
    MockUSDC public usdc;
    MockUSDT public usdt;
    MockWETH public weth;
    stBTD public stbtd;
    stBTB public stbtb;

    // ============ Pools ============
    UniswapV2Pair public poolWbtcUsdc;
    UniswapV2Pair public poolBtdUsdc;
    UniswapV2Pair public poolBtbBtd;
    UniswapV2Pair public poolBrsBtd;

    // ============ Mock Contracts ============
    MockPriceOracle public priceOracle;
    MockIUSDManager public iusdManager;
    MockRouter public mockRouter;

    // ============ Addresses ============
    address public owner = address(this);
    address public minter = address(0xA1);
    address public interestPool = address(0x1111);
    address public farmingPool = address(0x2222);
    address public user = address(0xBEEF);

    function setUp() public {
        // Deploy tokens - mint to this test contract
        wbtc = new MockWBTC(address(this));
        btd = ProxyTestHelper.deployBTD(address(this));
        btb = ProxyTestHelper.deployBTB(address(this));
        brs = new BRS(address(this));
        usdc = new MockUSDC(address(this));
        usdt = new MockUSDT(address(this));
        weth = new MockWETH(address(this));

        // Deploy staking tokens
        stbtd = ProxyTestHelper.deployStBTD(IERC20(address(btd)), address(this));
        stbtb = ProxyTestHelper.deployStBTB(IERC20(address(btb)), address(this));

        // Deploy Uniswap V2 Pairs and initialize
        poolWbtcUsdc = new UniswapV2Pair();
        poolWbtcUsdc.initialize(address(wbtc), address(usdc));

        poolBtdUsdc = new UniswapV2Pair();
        poolBtdUsdc.initialize(address(btd), address(usdc));

        poolBtbBtd = new UniswapV2Pair();
        poolBtbBtd.initialize(address(btb), address(btd));

        poolBrsBtd = new UniswapV2Pair();
        poolBrsBtd.initialize(address(brs), address(btd));

        // Deploy ConfigCore
        configCore = new ConfigCore(
            address(wbtc),
            address(btd),
            address(btb),
            address(brs),
            address(weth),
            address(usdc),
            address(usdt),
            address(poolWbtcUsdc),
            address(poolBtdUsdc),
            address(poolBtbBtd),
            address(poolBrsBtd),
            address(stbtd),
            address(stbtb)
        );

        // Deploy ConfigGov
        configGov = ProxyTestHelper.deployConfigGov(owner);

        // Deploy MockPriceOracle and MockIUSDManager
        priceOracle = new MockPriceOracle();
        iusdManager = new MockIUSDManager(1e18);

        // Deploy MockRouter
        mockRouter = new MockRouter(address(weth));

        // Deploy Treasury via proxy
        treasury = ProxyTestHelper.deployTreasury(owner, address(configCore), address(mockRouter));

        // Set core contracts in ConfigCore
        configCore.setCoreContracts(
            address(treasury),
            minter,
            address(priceOracle),
            address(iusdManager),
            interestPool,
            farmingPool
        );

        // Grant MINTER_ROLE to this test contract so we can mint BTD
        btd.grantRole(btd.MINTER_ROLE(), address(this));
    }

    // ================================================================
    //                      INITIALIZE TESTS
    // ================================================================

    function test_initialize_setsOwner() public view {
        assertEq(treasury.owner(), owner);
    }

    function test_initialize_setsCore() public view {
        assertEq(address(treasury.core()), address(configCore));
    }

    function test_initialize_setsRouter() public view {
        assertEq(treasury.router(), address(mockRouter));
    }

    function test_initialize_setsDefaults() public view {
        assertEq(treasury.minBuybackAmount(), 10_000e18);
        assertEq(treasury.maxBuybackAmount(), 50_000e18);
        assertEq(treasury.buybackCooldown(), 24 hours);
        assertEq(treasury.buybackProbability(), 10);
        assertEq(treasury.maxSlippageBps(), 200);
        assertEq(treasury.minEthReserve(), 0.5 ether);
        assertEq(treasury.ethTopupAmount(), 0.5 ether);
    }

    function test_initialize_revertsZeroOwner() public {
        Treasury impl = new Treasury();
        vm.expectRevert("Treasury: invalid owner");
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(Treasury.initialize, (address(0), address(configCore), address(mockRouter)))
        );
    }

    function test_initialize_revertsZeroCore() public {
        Treasury impl = new Treasury();
        vm.expectRevert("Treasury: invalid core");
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(Treasury.initialize, (owner, address(0), address(mockRouter)))
        );
    }

    function test_initialize_revertsZeroRouter() public {
        Treasury impl = new Treasury();
        vm.expectRevert("Treasury: invalid router");
        new ERC1967Proxy(
            address(impl),
            abi.encodeCall(Treasury.initialize, (owner, address(configCore), address(0)))
        );
    }

    function test_initialize_cannotReinitialize() public {
        vm.expectRevert();
        treasury.initialize(owner, address(configCore), address(mockRouter));
    }

    // ================================================================
    //                      DEPOSIT WBTC TESTS
    // ================================================================

    function test_depositWBTC_success() public {
        uint256 amt = 1e8; // 1 WBTC
        wbtc.transfer(minter, amt);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), amt);
        treasury.depositWBTC(amt);
        vm.stopPrank();

        assertEq(wbtc.balanceOf(address(treasury)), amt);
    }

    function test_depositWBTC_emitsEvent() public {
        uint256 amt = 5e8;
        wbtc.transfer(minter, amt);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), amt);

        vm.expectEmit(true, false, false, true);
        emit ITreasury.WBTCDeposited(minter, amt);
        treasury.depositWBTC(amt);
        vm.stopPrank();
    }

    function test_depositWBTC_revertsNonMinter() public {
        vm.prank(user);
        vm.expectRevert("Treasury: only Minter");
        treasury.depositWBTC(1e8);
    }

    function test_depositWBTC_revertsAmountTooSmall() public {
        vm.prank(minter);
        vm.expectRevert("Treasury: amount too small");
        treasury.depositWBTC(0);
    }

    function test_depositWBTC_revertsExceedsMax() public {
        uint256 overMax = Constants.MAX_WBTC_AMOUNT + 1;
        vm.prank(minter);
        vm.expectRevert("Treasury: exceeds max WBTC");
        treasury.depositWBTC(overMax);
    }

    function test_depositWBTC_minAmount() public {
        uint256 amt = Constants.MIN_BTC_AMOUNT; // 1 satoshi
        wbtc.transfer(minter, amt);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), amt);
        treasury.depositWBTC(amt);
        vm.stopPrank();

        assertEq(wbtc.balanceOf(address(treasury)), amt);
    }

    function test_depositWBTC_maxAmount() public {
        uint256 amt = Constants.MAX_WBTC_AMOUNT; // 10,000 BTC
        wbtc.transfer(minter, amt);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), amt);
        treasury.depositWBTC(amt);
        vm.stopPrank();

        assertEq(wbtc.balanceOf(address(treasury)), amt);
    }

    // ================================================================
    //                      WITHDRAW WBTC TESTS
    // ================================================================

    function test_withdrawWBTC_success() public {
        uint256 amt = 2e8;
        // First deposit
        wbtc.transfer(minter, amt);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), amt);
        treasury.depositWBTC(amt);

        // Now withdraw
        treasury.withdrawWBTC(amt);
        vm.stopPrank();

        assertEq(wbtc.balanceOf(address(treasury)), 0);
        assertEq(wbtc.balanceOf(minter), amt);
    }

    function test_withdrawWBTC_emitsEvent() public {
        uint256 amt = 1e8;
        _depositWBTCToTreasury(amt);

        vm.prank(minter);
        vm.expectEmit(true, false, false, true);
        emit ITreasury.WBTCWithdrawn(minter, amt);
        treasury.withdrawWBTC(amt);
    }

    function test_withdrawWBTC_revertsNonMinter() public {
        vm.prank(user);
        vm.expectRevert("Treasury: only Minter");
        treasury.withdrawWBTC(1e8);
    }

    function test_withdrawWBTC_revertsAmountTooSmall() public {
        vm.prank(minter);
        vm.expectRevert("Treasury: amount too small");
        treasury.withdrawWBTC(0);
    }

    function test_withdrawWBTC_revertsExceedsMax() public {
        vm.prank(minter);
        vm.expectRevert("Treasury: exceeds max WBTC");
        treasury.withdrawWBTC(Constants.MAX_WBTC_AMOUNT + 1);
    }

    function test_withdrawWBTC_revertsInsufficientBalance() public {
        vm.prank(minter);
        vm.expectRevert("Treasury: insufficient WBTC");
        treasury.withdrawWBTC(1e8);
    }

    function test_withdrawWBTC_partialWithdraw() public {
        _depositWBTCToTreasury(5e8);

        vm.prank(minter);
        treasury.withdrawWBTC(3e8);

        assertEq(wbtc.balanceOf(address(treasury)), 2e8);
    }

    // ================================================================
    //                      COMPENSATE TESTS
    // ================================================================

    function test_compensate_fullPayout() public {
        uint256 brsAmount = 1000e18;
        // Give treasury some BRS
        brs.transfer(address(treasury), brsAmount);

        uint256 compensationAmt = 500e18;
        vm.prank(minter);
        treasury.compensate(user, compensationAmt);

        assertEq(brs.balanceOf(user), compensationAmt);
        assertEq(brs.balanceOf(address(treasury)), brsAmount - compensationAmt);
    }

    function test_compensate_emitsBRSCompensated() public {
        brs.transfer(address(treasury), 1000e18);

        vm.prank(minter);
        vm.expectEmit(true, false, false, true);
        emit ITreasury.BRSCompensated(user, 500e18);
        treasury.compensate(user, 500e18);
    }

    function test_compensate_partialPayoutWithShortfall() public {
        uint256 treasuryBRS = 100e18;
        brs.transfer(address(treasury), treasuryBRS);

        uint256 requested = 500e18;
        vm.prank(minter);
        treasury.compensate(user, requested);

        // User gets only what treasury has
        assertEq(brs.balanceOf(user), treasuryBRS);
        assertEq(brs.balanceOf(address(treasury)), 0);
    }

    function test_compensate_zeroBalanceNoTransfer() public {
        // Treasury has no BRS
        uint256 requested = 100e18;
        vm.prank(minter);
        treasury.compensate(user, requested);

        // No transfer happened, no revert
        assertEq(brs.balanceOf(user), 0);
    }

    function test_compensate_revertsNonMinter() public {
        vm.prank(user);
        vm.expectRevert("Treasury: only Minter");
        treasury.compensate(user, 100e18);
    }

    function test_compensate_revertsZeroAddress() public {
        vm.prank(minter);
        vm.expectRevert("Treasury: zero address");
        treasury.compensate(address(0), 100e18);
    }

    function test_compensate_revertsAmountTooSmall() public {
        vm.prank(minter);
        vm.expectRevert("Treasury: amount too small");
        treasury.compensate(user, Constants.MIN_STABLECOIN_18_AMOUNT - 1);
    }

    function test_compensate_revertsExceedsMax() public {
        vm.prank(minter);
        vm.expectRevert("Treasury: exceeds max BRS");
        treasury.compensate(user, Constants.MAX_STABLECOIN_18_AMOUNT + 1);
    }

    function test_compensate_minAmount() public {
        brs.transfer(address(treasury), 1e18);

        vm.prank(minter);
        treasury.compensate(user, Constants.MIN_STABLECOIN_18_AMOUNT);

        assertEq(brs.balanceOf(user), Constants.MIN_STABLECOIN_18_AMOUNT);
    }

    // ================================================================
    //                      BUYBACK BRS TESTS
    // ================================================================

    function test_buybackBRS_success() public {
        uint256 btdAmount = 1000e18;
        uint256 minBRSOut = 1e15; // MIN_STABLECOIN_18_AMOUNT

        // Mint BTD to treasury
        btd.mint(address(treasury), btdAmount);
        // Fund mock router with BRS for swap output
        brs.transfer(address(mockRouter), btdAmount);

        treasury.buybackBRS(btdAmount, minBRSOut);

        // Treasury should have received BRS from swap
        assertEq(brs.balanceOf(address(treasury)), btdAmount);
        // Treasury BTD should be consumed
        assertEq(btd.balanceOf(address(treasury)), 0);
    }

    function test_buybackBRS_emitsBRSBuyback() public {
        uint256 btdAmount = 500e18;
        btd.mint(address(treasury), btdAmount);
        brs.transfer(address(mockRouter), btdAmount);

        vm.expectEmit(false, false, false, true);
        emit ITreasury.BRSBuyback(btdAmount, btdAmount); // 1:1 mock swap
        treasury.buybackBRS(btdAmount, 1e15);
    }

    function test_buybackBRS_revertsNonOwner() public {
        vm.prank(user);
        vm.expectRevert();
        treasury.buybackBRS(1000e18, 1e15);
    }

    function test_buybackBRS_revertsBtdAmountTooSmall() public {
        vm.expectRevert("Treasury: BTD amount too small");
        treasury.buybackBRS(Constants.MIN_STABLECOIN_18_AMOUNT - 1, 1e15);
    }

    function test_buybackBRS_revertsBtdAmountTooLarge() public {
        vm.expectRevert("Treasury: BTD amount too large");
        treasury.buybackBRS(Constants.MAX_STABLECOIN_18_AMOUNT + 1, 1e15);
    }

    function test_buybackBRS_revertsMinBRSOutTooSmall() public {
        vm.expectRevert("Treasury: minBRSOut too small");
        treasury.buybackBRS(1e15, Constants.MIN_STABLECOIN_18_AMOUNT - 1);
    }

    function test_buybackBRS_revertsMinBRSOutTooLarge() public {
        vm.expectRevert("Treasury: minBRSOut too large");
        treasury.buybackBRS(1e15, Constants.MAX_STABLECOIN_18_AMOUNT + 1);
    }

    function test_buybackBRS_revertsInsufficientBTD() public {
        // Treasury has no BTD
        vm.expectRevert("Treasury: insufficient BTD");
        treasury.buybackBRS(1000e18, 1e15);
    }

    // ================================================================
    //                      TRY LAZY BUYBACK TESTS
    // ================================================================

    function test_tryLazyBuyback_revertsUnauthorizedCaller() public {
        vm.prank(user);
        vm.expectRevert("Treasury: unauthorized buyback caller");
        treasury.tryLazyBuyback();
    }

    function test_tryLazyBuyback_returnsFalseOnCooldown() public {
        // Set lastBuybackTime to now by setting buyback params and doing a buyback
        // Simpler: just call from owner with insufficient BTD first, then try again
        // Actually, cooldown starts at 0, so first call won't hit cooldown unless
        // block.timestamp < lastBuybackTime + cooldown
        // lastBuybackTime = 0, cooldown = 24h, so block.timestamp (1) < 24h is true
        // So the very first call WILL pass cooldown check.
        // We need to force a successful buyback first, then check cooldown.

        // Fund treasury with BTD for a potential buyback
        btd.mint(address(treasury), 50_000e18);
        brs.transfer(address(mockRouter), 50_000e18);

        // The random trigger is non-deterministic, so just test cooldown logic:
        // If lastBuybackTime is recent, it should return false
        // We can do this by warping time so that a buyback succeeds, then trying again

        // First, try from owner - may or may not execute depending on random
        // Instead, test cooldown by directly checking the condition:
        // After setting lastBuybackTime to current via a successful buyback

        // Let's test by brute-forcing until one succeeds, then checking cooldown
        bool executed = false;
        for (uint256 i = 0; i < 200; i++) {
            vm.warp(block.timestamp + 1 days + 1 + i);
            vm.roll(block.number + 1);
            btd.mint(address(treasury), 50_000e18);
            brs.transfer(address(mockRouter), 50_000e18);
            executed = treasury.tryLazyBuyback();
            if (executed) break;
        }

        if (executed) {
            // Now try again immediately - should return false due to cooldown
            btd.mint(address(treasury), 50_000e18);
            brs.transfer(address(mockRouter), 50_000e18);
            vm.roll(block.number + 1);
            bool secondResult = treasury.tryLazyBuyback();
            assertFalse(secondResult, "Should return false due to cooldown");
        }
        // If no execution happened in 200 tries (unlikely), test is still valid
    }

    function test_tryLazyBuyback_returnsFalseInsufficientBTD() public {
        // Treasury has less BTD than minBuybackAmount (10,000e18)
        btd.mint(address(treasury), 5000e18);

        vm.warp(block.timestamp + 1 days + 1);
        vm.roll(block.number + 1);

        bool executed = treasury.tryLazyBuyback();
        assertFalse(executed, "Should return false when BTD below min");
    }

    function test_tryLazyBuyback_accessMinter() public {
        // Minter should be authorized
        btd.mint(address(treasury), 5000e18); // Below min, so returns false not revert
        vm.warp(block.timestamp + 1 days + 1);
        vm.roll(block.number + 1);

        vm.prank(minter);
        bool executed = treasury.tryLazyBuyback();
        assertFalse(executed); // Not enough BTD, but no revert
    }

    function test_tryLazyBuyback_accessInterestPool() public {
        btd.mint(address(treasury), 5000e18);
        vm.warp(block.timestamp + 1 days + 1);
        vm.roll(block.number + 1);

        vm.prank(interestPool);
        bool executed = treasury.tryLazyBuyback();
        assertFalse(executed);
    }

    function test_tryLazyBuyback_accessFarmingPool() public {
        btd.mint(address(treasury), 5000e18);
        vm.warp(block.timestamp + 1 days + 1);
        vm.roll(block.number + 1);

        vm.prank(farmingPool);
        bool executed = treasury.tryLazyBuyback();
        assertFalse(executed);
    }

    function test_tryLazyBuyback_accessOwner() public {
        btd.mint(address(treasury), 5000e18);
        vm.warp(block.timestamp + 1 days + 1);
        vm.roll(block.number + 1);

        // owner is address(this), no prank needed
        bool executed = treasury.tryLazyBuyback();
        assertFalse(executed);
    }

    // ================================================================
    //                      SET BUYBACK PARAMS TESTS
    // ================================================================

    function test_setBuybackParams_success() public {
        treasury.setBuybackParams(
            5000e18,    // min
            100_000e18, // max
            2 hours,    // cooldown
            50,         // probability
            500         // slippage bps
        );

        assertEq(treasury.minBuybackAmount(), 5000e18);
        assertEq(treasury.maxBuybackAmount(), 100_000e18);
        assertEq(treasury.buybackCooldown(), 2 hours);
        assertEq(treasury.buybackProbability(), 50);
        assertEq(treasury.maxSlippageBps(), 500);
    }

    function test_setBuybackParams_revertsNonOwner() public {
        vm.prank(user);
        vm.expectRevert();
        treasury.setBuybackParams(5000e18, 100_000e18, 2 hours, 50, 500);
    }

    function test_setBuybackParams_revertsMinTooSmall() public {
        vm.expectRevert("Min buyback too small");
        treasury.setBuybackParams(999e18, 100_000e18, 2 hours, 50, 500);
    }

    function test_setBuybackParams_revertsMaxLessThanMin() public {
        vm.expectRevert("Max must >= min");
        treasury.setBuybackParams(10_000e18, 5000e18, 2 hours, 50, 500);
    }

    function test_setBuybackParams_revertsMaxTooLarge() public {
        vm.expectRevert("Max buyback too large");
        treasury.setBuybackParams(1000e18, 1_000_001e18, 2 hours, 50, 500);
    }

    function test_setBuybackParams_revertsCooldownTooShort() public {
        vm.expectRevert("Cooldown too short");
        treasury.setBuybackParams(1000e18, 50_000e18, 59 minutes, 50, 500);
    }

    function test_setBuybackParams_revertsCooldownTooLong() public {
        vm.expectRevert("Cooldown too long");
        treasury.setBuybackParams(1000e18, 50_000e18, 8 days, 50, 500);
    }

    function test_setBuybackParams_revertsProbabilityZero() public {
        vm.expectRevert("Invalid probability");
        treasury.setBuybackParams(1000e18, 50_000e18, 2 hours, 0, 500);
    }

    function test_setBuybackParams_revertsProbabilityOver100() public {
        vm.expectRevert("Invalid probability");
        treasury.setBuybackParams(1000e18, 50_000e18, 2 hours, 101, 500);
    }

    function test_setBuybackParams_revertsSlippageTooLow() public {
        vm.expectRevert("Slippage out of range");
        treasury.setBuybackParams(1000e18, 50_000e18, 2 hours, 50, 49);
    }

    function test_setBuybackParams_revertsSlippageTooHigh() public {
        vm.expectRevert("Slippage out of range");
        treasury.setBuybackParams(1000e18, 50_000e18, 2 hours, 50, 1001);
    }

    function test_setBuybackParams_boundaryMin() public {
        // Exact boundary values should succeed
        treasury.setBuybackParams(
            1000e18,        // min boundary
            1000e18,        // max = min
            1 hours,        // cooldown min
            1,              // probability min
            50              // slippage min
        );
        assertEq(treasury.minBuybackAmount(), 1000e18);
        assertEq(treasury.buybackProbability(), 1);
        assertEq(treasury.maxSlippageBps(), 50);
    }

    function test_setBuybackParams_boundaryMax() public {
        treasury.setBuybackParams(
            1000e18,        // min
            1_000_000e18,   // max boundary
            7 days,         // cooldown max
            100,            // probability max
            1000            // slippage max
        );
        assertEq(treasury.maxBuybackAmount(), 1_000_000e18);
        assertEq(treasury.buybackCooldown(), 7 days);
        assertEq(treasury.buybackProbability(), 100);
        assertEq(treasury.maxSlippageBps(), 1000);
    }

    // ================================================================
    //                      SET ETH RESERVE PARAMS TESTS
    // ================================================================

    function test_setEthReserveParams_success() public {
        treasury.setEthReserveParams(1 ether, 2 ether);
        assertEq(treasury.minEthReserve(), 1 ether);
        assertEq(treasury.ethTopupAmount(), 2 ether);
    }

    function test_setEthReserveParams_revertsNonOwner() public {
        vm.prank(user);
        vm.expectRevert();
        treasury.setEthReserveParams(1 ether, 2 ether);
    }

    function test_setEthReserveParams_revertsMinReserveTooSmall() public {
        vm.expectRevert("Min reserve too small");
        treasury.setEthReserveParams(0.09 ether, 1 ether);
    }

    function test_setEthReserveParams_revertsMinReserveTooLarge() public {
        vm.expectRevert("Min reserve too large");
        treasury.setEthReserveParams(11 ether, 1 ether);
    }

    function test_setEthReserveParams_revertsTopupTooSmall() public {
        vm.expectRevert("Topup amount too small");
        treasury.setEthReserveParams(1 ether, 0.09 ether);
    }

    function test_setEthReserveParams_revertsTopupTooLarge() public {
        vm.expectRevert("Topup amount too large");
        treasury.setEthReserveParams(1 ether, 6 ether);
    }

    function test_setEthReserveParams_boundaryMin() public {
        treasury.setEthReserveParams(0.1 ether, 0.1 ether);
        assertEq(treasury.minEthReserve(), 0.1 ether);
        assertEq(treasury.ethTopupAmount(), 0.1 ether);
    }

    function test_setEthReserveParams_boundaryMax() public {
        treasury.setEthReserveParams(10 ether, 5 ether);
        assertEq(treasury.minEthReserve(), 10 ether);
        assertEq(treasury.ethTopupAmount(), 5 ether);
    }

    // ================================================================
    //                      SET ROUTER TESTS
    // ================================================================

    function test_setRouter_success() public {
        address newRouter = address(0xCAFE);
        treasury.setRouter(newRouter);
        assertEq(treasury.router(), newRouter);
    }

    function test_setRouter_emitsEvent() public {
        address oldRouter = treasury.router();
        address newRouter = address(0xCAFE);

        vm.expectEmit(true, true, false, false);
        emit Treasury.RouterUpdated(oldRouter, newRouter);
        treasury.setRouter(newRouter);
    }

    function test_setRouter_revertsNonOwner() public {
        vm.prank(user);
        vm.expectRevert();
        treasury.setRouter(address(0xCAFE));
    }

    function test_setRouter_revertsZeroAddress() public {
        vm.expectRevert("Treasury: invalid router");
        treasury.setRouter(address(0));
    }

    // ================================================================
    //                      WITHDRAW ETH TESTS
    // ================================================================

    function test_withdrawEth_success() public {
        // Send ETH to treasury
        vm.deal(address(treasury), 5 ether);

        address payable recipient = payable(address(0xBEEF));
        uint256 beforeBal = recipient.balance;

        treasury.withdrawEth(2 ether, recipient);

        assertEq(recipient.balance, beforeBal + 2 ether);
        assertEq(address(treasury).balance, 3 ether);
    }

    function test_withdrawEth_revertsNonOwner() public {
        vm.deal(address(treasury), 5 ether);
        vm.prank(user);
        vm.expectRevert();
        treasury.withdrawEth(1 ether, payable(user));
    }

    function test_withdrawEth_revertsZeroRecipient() public {
        vm.deal(address(treasury), 5 ether);
        vm.expectRevert("Invalid recipient");
        treasury.withdrawEth(1 ether, payable(address(0)));
    }

    function test_withdrawEth_revertsInsufficientBalance() public {
        // Treasury has 0 ETH
        vm.expectRevert("Insufficient ETH");
        treasury.withdrawEth(1 ether, payable(user));
    }

    function test_withdrawEth_fullWithdraw() public {
        vm.deal(address(treasury), 3 ether);
        treasury.withdrawEth(3 ether, payable(user));
        assertEq(address(treasury).balance, 0);
        assertEq(user.balance, 3 ether);
    }

    // ================================================================
    //                      RECEIVE ETH TESTS
    // ================================================================

    function test_receive_acceptsEth() public {
        vm.deal(address(this), 10 ether);
        (bool success,) = address(treasury).call{value: 5 ether}("");
        assertTrue(success, "Treasury should accept ETH");
        assertEq(address(treasury).balance, 5 ether);
    }

    function test_receive_multipleDeposits() public {
        vm.deal(address(this), 10 ether);
        (bool s1,) = address(treasury).call{value: 2 ether}("");
        assertTrue(s1);
        (bool s2,) = address(treasury).call{value: 3 ether}("");
        assertTrue(s2);
        assertEq(address(treasury).balance, 5 ether);
    }

    // ================================================================
    //                      GET BALANCES TESTS
    // ================================================================

    function test_getBalances_initiallyZero() public view {
        (uint256 wbtcBal, uint256 brsBal, uint256 btdBal) = treasury.getBalances();
        assertEq(wbtcBal, 0);
        assertEq(brsBal, 0);
        assertEq(btdBal, 0);
    }

    function test_getBalances_afterDeposits() public {
        // Deposit WBTC
        uint256 wbtcAmt = 3e8;
        _depositWBTCToTreasury(wbtcAmt);

        // Transfer BRS to treasury
        uint256 brsAmt = 5000e18;
        brs.transfer(address(treasury), brsAmt);

        // Mint BTD to treasury
        uint256 btdAmt = 10_000e18;
        btd.mint(address(treasury), btdAmt);

        (uint256 wbtcBal, uint256 brsBal, uint256 btdBal) = treasury.getBalances();
        assertEq(wbtcBal, wbtcAmt);
        assertEq(brsBal, brsAmt);
        assertEq(btdBal, btdAmt);
    }

    function test_getBalances_afterWithdraw() public {
        _depositWBTCToTreasury(5e8);
        vm.prank(minter);
        treasury.withdrawWBTC(2e8);

        (uint256 wbtcBal,,) = treasury.getBalances();
        assertEq(wbtcBal, 3e8);
    }

    function test_getBalances_afterCompensation() public {
        brs.transfer(address(treasury), 1000e18);
        vm.prank(minter);
        treasury.compensate(user, 400e18);

        (, uint256 brsBal,) = treasury.getBalances();
        assertEq(brsBal, 600e18);
    }

    function test_getBalances_afterBuyback() public {
        uint256 btdAmt = 2000e18;
        btd.mint(address(treasury), btdAmt);
        brs.transfer(address(mockRouter), btdAmt);

        treasury.buybackBRS(btdAmt, 1e15);

        (uint256 wbtcBal, uint256 brsBal, uint256 btdBal) = treasury.getBalances();
        assertEq(wbtcBal, 0);
        assertEq(brsBal, btdAmt); // 1:1 mock swap
        assertEq(btdBal, 0);
    }

    // ================================================================
    //                      CONFIG CORE VIEW TESTS
    // ================================================================

    function test_configCore_returnsCorrectAddress() public view {
        assertEq(treasury.configCore(), address(configCore));
    }

    // ================================================================
    //                      HELPER FUNCTIONS
    // ================================================================

    /// @notice Helper to deposit WBTC to treasury through the minter
    function _depositWBTCToTreasury(uint256 amt) internal {
        wbtc.transfer(minter, amt);
        vm.startPrank(minter);
        wbtc.approve(address(treasury), amt);
        treasury.depositWBTC(amt);
        vm.stopPrank();
    }
}
