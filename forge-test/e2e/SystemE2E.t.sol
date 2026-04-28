// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/BTD.sol";
import "../../contracts/BTB.sol";
import "../../contracts/BRS.sol";
import "../../contracts/stBTD.sol";
import "../../contracts/stBTB.sol";
import "../../contracts/Minter.sol";
import "../../contracts/Treasury.sol";
import "../../contracts/InterestPool.sol";
import "../../contracts/FarmingPool.sol";
import "../../contracts/ConfigCore.sol";
import "../../contracts/ConfigGov.sol";
import "../../contracts/local/MockWBTC.sol";
import "../../contracts/local/MockUSDC.sol";
import "../../contracts/local/MockUSDT.sol";
import "../../contracts/local/MockWETH.sol";
import "../../contracts/local/MockPriceOracle.sol";
import "../../contracts/local/MockIUSDManager.sol";
import "../../contracts/local/UniswapV2Pair.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/interfaces/IFarmingPool.sol";
import "../helpers/ProxyTestHelper.sol";

/// @title Full System E2E Test
/// @notice Mirrors FullSystem.ts deployment, then tests all whitepaper functionality
contract SystemE2ETest is Test {

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
    MockPriceOracle public priceOracle;
    MockIUSDManager public iusdManager;
    Treasury public treasury;
    Minter public minter;
    InterestPool public interestPool;
    FarmingPool public farmingPool;

    // ============ Actors ============

    address public deployer = address(this);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public carol = address(0xCA301);
    address public foundation = address(0xF0071DA);
    address public team = address(0x7EA3);
    address public mockRouter = address(0xDEAD);

    // ============ Price Constants ============

    uint256 constant WBTC_PRICE = 102_000e18;  // $102,000
    uint256 constant BTD_PRICE = 1e18;          // $1.00
    uint256 constant BTB_PRICE = 1e18;          // $1.00
    uint256 constant BRS_PRICE = 1e18;          // $1.00
    uint256 constant IUSD_PRICE = 1e18;         // $1.00

    // ============ setUp: Full System Deployment ============

    function setUp() public {
        // --- Phase 1: Mock external tokens ---
        wbtc = new MockWBTC(deployer);
        usdc = new MockUSDC(deployer);
        usdt = new MockUSDT(deployer);
        weth = new MockWETH(deployer);

        // --- Phase 2: Core tokens ---
        brs = new BRS(deployer);
        btd = ProxyTestHelper.deployBTD(deployer);
        btb = ProxyTestHelper.deployBTB(deployer);

        // --- Phase 2.5: Staking tokens ---
        stbtd = ProxyTestHelper.deployStBTD(IERC20(address(btd)), deployer);
        stbtb = ProxyTestHelper.deployStBTB(IERC20(address(btb)), deployer);

        // --- Phase 3: Uniswap V2 pairs ---
        poolWbtcUsdc = new UniswapV2Pair();
        poolWbtcUsdc.initialize(address(wbtc), address(usdc));
        poolBtdUsdc = new UniswapV2Pair();
        poolBtdUsdc.initialize(address(btd), address(usdc));
        poolBtbBtd = new UniswapV2Pair();
        poolBtbBtd.initialize(address(btb), address(btd));
        poolBrsBtd = new UniswapV2Pair();
        poolBrsBtd.initialize(address(brs), address(btd));

        // --- Phase 4: ConfigCore ---
        core = new ConfigCore(
            address(wbtc), address(btd), address(btb), address(brs),
            address(weth), address(usdc), address(usdt),
            address(poolWbtcUsdc), address(poolBtdUsdc),
            address(poolBtbBtd), address(poolBrsBtd),
            address(stbtd), address(stbtb)
        );

        // --- Phase 6: ConfigGov ---
        gov = ProxyTestHelper.deployConfigGov(deployer);

        // --- Phase 7: Mock oracles (replacing real PriceOracle + IdealUSDManager) ---
        priceOracle = new MockPriceOracle();
        priceOracle.setAllPrices(WBTC_PRICE, BTD_PRICE, BTB_PRICE, BRS_PRICE, IUSD_PRICE);
        iusdManager = new MockIUSDManager(IUSD_PRICE);

        // --- Phase 8: Treasury ---
        treasury = ProxyTestHelper.deployTreasury(deployer, address(core), mockRouter);

        // --- Phase 9: Minter ---
        minter = ProxyTestHelper.deployMinter(deployer, address(core), address(gov));

        // --- Phase 10: InterestPool ---
        interestPool = ProxyTestHelper.deployInterestPool(deployer, address(core), address(gov), deployer);

        // --- Phase 11: Grant MINTER_ROLE ---
        bytes32 minterRole = btd.MINTER_ROLE();
        btd.grantRole(minterRole, address(minter));
        btd.grantRole(minterRole, address(interestPool));
        btb.grantRole(btb.MINTER_ROLE(), address(minter));
        btb.grantRole(btb.MINTER_ROLE(), address(interestPool));

        // --- Phase 12: FarmingPool ---
        address[] memory funds = new address[](3);
        funds[0] = address(treasury);
        funds[1] = foundation;
        funds[2] = team;
        uint256[] memory shares = new uint256[](3);
        shares[0] = 20;
        shares[1] = 10;
        shares[2] = 10;
        farmingPool = ProxyTestHelper.deployFarmingPool(
            deployer, address(brs), address(core), funds, shares
        );

        // --- Phase 13: BRS distribution to FarmingPool ---
        brs.transfer(address(farmingPool), Constants.BRS_MAX_SUPPLY - 1e18);
        // Keep 1 BRS for deployer, rest to farming

        // --- Phase 14: ConfigCore.setCoreContracts + renounceOwnership ---
        core.setCoreContracts(
            address(treasury),
            address(minter),
            address(priceOracle),
            address(iusdManager),
            address(interestPool),
            address(farmingPool)
        );
        core.renounceOwnership();

        // --- Phase 15: ConfigGov params ---
        ConfigGov.ParamType[] memory paramTypes = new ConfigGov.ParamType[](4);
        uint256[] memory paramValues = new uint256[](4);
        paramTypes[0] = ConfigGov.ParamType.MintFeeBp;
        paramValues[0] = 50;   // 0.5%
        paramTypes[1] = ConfigGov.ParamType.RedeemFeeBp;
        paramValues[1] = 50;   // 0.5%
        paramTypes[2] = ConfigGov.ParamType.BaseRateDefault;
        paramValues[2] = 500;  // 5%
        paramTypes[3] = ConfigGov.ParamType.MinBtbPrice;
        paramValues[3] = 5e17; // 0.5 BTD
        gov.setParamsBatch(paramTypes, paramValues);

        // --- Phase 16: Initialize InterestPool ---
        interestPool.initializePools();

        // --- Phase 16b: Add farming pool (single-token BTD pool) ---
        farmingPool.addPool(IERC20(address(btd)), 100, IFarmingPool.PoolKind.Single);

        // --- Phase 16c: Fund users with WBTC ---
        wbtc.transfer(alice, 1000 * 1e8);   // 1000 BTC
        wbtc.transfer(bob, 1000 * 1e8);
        wbtc.transfer(carol, 1000 * 1e8);

        // --- Phase 16d: Fund treasury with BRS for compensation ---
        brs.transfer(address(treasury), 1e18); // deployer's remaining 1 BRS
        // Note: treasury already gets BRS from farming fund distribution
    }

    // ============ Helper Functions ============

    /// @notice Mint BTD for a user from WBTC
    function _mintBTDForUser(address user, uint256 wbtcAmount) internal {
        vm.startPrank(user);
        wbtc.approve(address(minter), wbtcAmount);
        minter.mintBTD(wbtcAmount);
        vm.stopPrank();
    }

    /// @notice Set WBTC price on the mock oracle
    function _setWBTCPrice(uint256 price) internal {
        priceOracle.setWBTCPrice(price);
    }

    /// @notice Crash BTC price to a specific value
    function _crashBTCPrice(uint256 newPrice) internal {
        priceOracle.setWBTCPrice(newPrice);
    }

    /// @notice Set BTB price on the mock oracle
    function _setBTBPrice(uint256 price) internal {
        priceOracle.setBTBPrice(price);
    }

    /// @notice Set BRS price on the mock oracle
    function _setBRSPrice(uint256 price) internal {
        priceOracle.setBRSPrice(price);
    }

    // ============================================================
    //                    A. MINTING TESTS (5)
    // ============================================================

    /// @notice Test basic mint: 1 BTC -> BTD, fee goes to treasury
    function test_mint_basic() public {
        uint256 wbtcAmount = 1e8; // 1 BTC

        vm.startPrank(alice);
        wbtc.approve(address(minter), wbtcAmount);

        uint256 aliceBTDBefore = btd.balanceOf(alice);
        uint256 treasuryBTDBefore = btd.balanceOf(address(treasury));

        minter.mintBTD(wbtcAmount);
        vm.stopPrank();

        uint256 aliceBTDAfter = btd.balanceOf(alice);
        uint256 treasuryBTDAfter = btd.balanceOf(address(treasury));

        // Alice should receive BTD
        uint256 received = aliceBTDAfter - aliceBTDBefore;
        assertGt(received, 0, "Alice should receive BTD");

        // Treasury should receive fee
        uint256 feeReceived = treasuryBTDAfter - treasuryBTDBefore;
        assertGt(feeReceived, 0, "Treasury should receive fee");

        // At $102k per BTC, gross should be ~102,000 BTD
        // Fee = 0.5% of 102,000 = 510 BTD
        // Net = 102,000 - 510 = 101,490 BTD
        assertApproxEqRel(received, 101_490e18, 0.01e18, "~101,490 BTD expected");
        assertApproxEqRel(feeReceived, 510e18, 0.01e18, "~510 BTD fee expected");

        // WBTC should now be in treasury
        (uint256 wbtcBal, , ) = treasury.getBalances();
        assertEq(wbtcBal, wbtcAmount, "Treasury should hold the WBTC");
    }

    /// @notice calculateMintAmount preview matches actual mint
    function test_mint_feeCalculation() public {
        uint256 wbtcAmount = 5e8; // 5 BTC

        (uint256 previewBTD, uint256 previewFee) = minter.calculateMintAmount(wbtcAmount);

        vm.startPrank(alice);
        wbtc.approve(address(minter), wbtcAmount);
        minter.mintBTD(wbtcAmount);
        vm.stopPrank();

        uint256 aliceBTD = btd.balanceOf(alice);
        uint256 treasuryFee = btd.balanceOf(address(treasury));

        assertEq(aliceBTD, previewBTD, "Preview BTD should match actual");
        assertEq(treasuryFee, previewFee, "Preview fee should match actual");
    }

    /// @notice Test small and large mint amounts
    function test_mint_variousAmounts() public {
        // Small: 0.001 BTC
        uint256 smallAmount = 1e5;
        _mintBTDForUser(alice, smallAmount);
        assertGt(btd.balanceOf(alice), 0, "Small mint should work");

        // Large: 100 BTC
        uint256 largeAmount = 100e8;
        uint256 balBefore = btd.balanceOf(bob);
        _mintBTDForUser(bob, largeAmount);
        uint256 received = btd.balanceOf(bob) - balBefore;
        // ~100 * 102,000 * 0.995 = ~10,149,000 BTD
        assertApproxEqRel(received, 10_149_000e18, 0.01e18, "Large mint amount check");
    }

    /// @notice Revert on zero amount
    function test_mint_revertZeroAmount() public {
        vm.startPrank(alice);
        wbtc.approve(address(minter), 1e8);
        vm.expectRevert("Amount below minimum BTC");
        minter.mintBTD(0);
        vm.stopPrank();
    }

    /// @notice Revert when user hasn't approved WBTC
    function test_mint_revertNoApproval() public {
        vm.startPrank(alice);
        vm.expectRevert();
        minter.mintBTD(1e8);
        vm.stopPrank();
    }

    // ============================================================
    //                B. REDEMPTION TESTS (9)
    // ============================================================

    /// @notice Full WBTC redemption when CR > 100%
    function test_redeem_fullWBTC_CRAbove100() public {
        // Mint first
        _mintBTDForUser(alice, 10e8); // 10 BTC

        uint256 btdBal = btd.balanceOf(alice);
        uint256 redeemAmount = btdBal / 2; // Redeem half

        vm.startPrank(alice);
        btd.approve(address(minter), redeemAmount);

        uint256 wbtcBefore = wbtc.balanceOf(alice);
        minter.redeemBTD(redeemAmount);
        vm.stopPrank();

        uint256 wbtcReceived = wbtc.balanceOf(alice) - wbtcBefore;
        assertGt(wbtcReceived, 0, "Should receive WBTC");

        // No BTB or BRS should be issued
        assertEq(btb.balanceOf(alice), 0, "No BTB when CR>100%");
    }

    /// @notice calculateBurnAmount preview matches actual redeem
    function test_redeem_feeCalculation() public {
        _mintBTDForUser(alice, 10e8);

        uint256 redeemAmount = 50_000e18;
        (uint256 previewWBTC, uint256 previewFee) = minter.calculateBurnAmount(redeemAmount);

        uint256 wbtcBefore = wbtc.balanceOf(alice);
        uint256 treasuryBTDBefore = btd.balanceOf(address(treasury));

        vm.startPrank(alice);
        btd.approve(address(minter), redeemAmount);
        minter.redeemBTD(redeemAmount);
        vm.stopPrank();

        uint256 wbtcReceived = wbtc.balanceOf(alice) - wbtcBefore;
        assertEq(wbtcReceived, previewWBTC, "Preview WBTC should match actual");

        // Fee is minted to treasury
        uint256 treasuryFeeReceived = btd.balanceOf(address(treasury)) - treasuryBTDBefore;
        assertEq(treasuryFeeReceived, previewFee, "Preview fee should match actual");
    }

    /// @notice Undercollateralized redemption: BTB compensation (BTB price >= minBTBPrice)
    function test_redeem_undercollateralized_BTB() public {
        // Step 1: Mint BTD at high price
        _mintBTDForUser(alice, 10e8);

        // Step 2: Crash BTC price so CR < 100%
        _crashBTCPrice(51_000e18); // $51,000 (roughly halved)
        // CR = (10 BTC * $51k) / (102,000 BTD * $1) ≈ 50%

        // Set BTB price above minBTBPrice (0.5 BTD)
        _setBTBPrice(0.8e18);

        uint256 redeemAmount = 10_000e18;

        vm.startPrank(alice);
        btd.approve(address(minter), redeemAmount);
        minter.redeemBTD(redeemAmount);
        vm.stopPrank();

        // Should receive some WBTC + BTB, no BRS
        assertGt(wbtc.balanceOf(alice) - (1000e8 - 10e8), 0, "Should receive some WBTC");
        assertGt(btb.balanceOf(alice), 0, "Should receive BTB compensation");
    }

    /// @notice Three-tier compensation: BTB price < minBTBPrice → WBTC + BTB + BRS
    function test_redeem_threeTier_BRS() public {
        _mintBTDForUser(alice, 10e8);

        // Crash BTC price
        _crashBTCPrice(51_000e18);

        // Set BTB price below minBTBPrice (0.5 BTD * $1 BTD = $0.5)
        _setBTBPrice(0.3e18); // Below $0.5 min
        _setBRSPrice(1e18);

        uint256 redeemAmount = 10_000e18;

        vm.startPrank(alice);
        btd.approve(address(minter), redeemAmount);
        minter.redeemBTD(redeemAmount);
        vm.stopPrank();

        assertGt(btb.balanceOf(alice), 0, "Should receive BTB");
        assertGt(brs.balanceOf(alice), 0, "Should receive BRS (three-tier)");
    }

    /// @notice Boundary test: exact CR = 100%
    function test_redeem_exactCR100() public {
        _mintBTDForUser(alice, 10e8);

        // Get exact BTD supply to calculate required WBTC price for CR=100%
        uint256 totalBTDSupply = btd.totalSupply();
        // CR = (10 BTC * price) / (totalBTD * $1) = 1.0
        // price = totalBTD / 10 * 1e8 / 1e18 = totalBTD * 1e8 / (10 * 1e18)
        // But price is 18 decimals: price_18 = totalBTD / 10
        // Wait, CR = (wbtc * wbtcPrice / 1e8) / (totalBTD * iusdPrice / 1e18)
        // For CR=1e18: wbtc * wbtcPrice * 1e18 / (1e8 * totalBTD * iusdPrice) = 1e18
        // wbtcPrice = totalBTD * iusdPrice * 1e8 / (wbtc * 1e18)
        // = totalBTD * 1e18 * 1e8 / (10e8 * 1e18) = totalBTD / 10
        uint256 exactPrice = totalBTDSupply / 10;
        _setWBTCPrice(exactPrice);

        uint256 cr = minter.getCollateralRatio();
        // Should be exactly or very close to 1e18
        assertApproxEqAbs(cr, 1e18, 1e15, "CR should be ~100%");

        // Redeem should still give full WBTC (CR >= 100%)
        uint256 redeemAmount = 1_000e18;
        vm.startPrank(alice);
        btd.approve(address(minter), redeemAmount);
        minter.redeemBTD(redeemAmount);
        vm.stopPrank();

        assertEq(btb.balanceOf(alice), 0, "No BTB at CR=100%");
    }

    /// @notice Redeem BTB for BTD when CR > 100%
    function test_redeemBTB_success() public {
        // Step 1: Create BTB by minting then redeeming under-collateral
        _mintBTDForUser(alice, 10e8);
        _crashBTCPrice(51_000e18);
        _setBTBPrice(0.8e18);

        uint256 redeemBTDAmount = 10_000e18;
        vm.startPrank(alice);
        btd.approve(address(minter), redeemBTDAmount);
        minter.redeemBTD(redeemBTDAmount);
        vm.stopPrank();

        uint256 btbBalance = btb.balanceOf(alice);
        assertGt(btbBalance, 0, "Alice should have BTB");

        // Step 2: Increase price significantly so CR > 100% WITH excess for BTB redemption
        // After crash to $51k and partial redemption, treasury has less WBTC.
        // We need collateralValue > liabilityValue by at least btbAmount * iusdPrice.
        // Increase price well above $102k to ensure sufficient surplus.
        _setWBTCPrice(200_000e18); // $200k - enough excess collateral
        _setBTBPrice(BTB_PRICE);

        uint256 cr = minter.getCollateralRatio();
        assertGt(cr, 1e18, "CR should be > 100%");

        // Step 3: Redeem a small BTB amount to stay within max redeemable
        // maxRedeemable = (collateralValue - liabilityValue) / iusdPrice
        uint256 redeemBTB = btbBalance > 1_000e18 ? 1_000e18 : btbBalance;

        uint256 aliceBTDBefore = btd.balanceOf(alice);
        vm.startPrank(alice);
        btb.approve(address(minter), redeemBTB);
        minter.redeemBTB(redeemBTB);
        vm.stopPrank();

        uint256 aliceBTDAfter = btd.balanceOf(alice);
        // BTB redeemed 1:1 for BTD
        assertEq(aliceBTDAfter - aliceBTDBefore, redeemBTB, "BTB redeemed 1:1 for BTD");
    }

    /// @notice Redeem BTB reverts when CR < 100%
    function test_redeemBTB_revertWhenCRBelow100() public {
        // Create BTB first
        _mintBTDForUser(alice, 10e8);
        _crashBTCPrice(51_000e18);
        _setBTBPrice(0.8e18);

        uint256 redeemBTDAmount = 10_000e18;
        vm.startPrank(alice);
        btd.approve(address(minter), redeemBTDAmount);
        minter.redeemBTD(redeemBTDAmount);
        vm.stopPrank();

        uint256 btbBalance = btb.balanceOf(alice);
        assertGt(btbBalance, 0, "Should have BTB");

        // Keep CR < 100% (don't restore price)
        vm.startPrank(alice);
        btb.approve(address(minter), btbBalance);
        vm.expectRevert("CR<100%, BTB not redeemable");
        minter.redeemBTB(btbBalance);
        vm.stopPrank();
    }

    /// @notice Revert when user doesn't have enough BTD
    function test_redeem_revertInsufficientBalance() public {
        // Alice has no BTD
        vm.startPrank(alice);
        vm.expectRevert("Not enough BTD");
        minter.redeemBTD(1000e18);
        vm.stopPrank();
    }

    /// @notice Revert when redeem amount is below minimum
    function test_redeem_revertBelowMinimum() public {
        _mintBTDForUser(alice, 1e8);

        vm.startPrank(alice);
        btd.approve(address(minter), 1);
        vm.expectRevert("Amount below minimum");
        minter.redeemBTD(1); // 1 wei, below MIN_STABLECOIN_18_AMOUNT
        vm.stopPrank();
    }

    // ============================================================
    //             C. INTEREST & STAKING TESTS (7)
    // ============================================================

    /// @notice Stake BTD, accrue interest over 1 year, unstake and verify ~5%
    function test_interest_stakeBTD_accrueOverTime() public {
        _mintBTDForUser(alice, 10e8);

        uint256 btdSupplyBefore = btd.totalSupply();
        uint256 stakeAmount = 50_000e18;

        vm.startPrank(alice);
        btd.approve(address(interestPool), stakeAmount);
        interestPool.stakeBTD(stakeAmount);
        vm.stopPrank();

        // Warp 1 year
        vm.warp(block.timestamp + 365 days);

        // Unstake the full available amount (principal + interest).
        // _unstake allows withdrawing up to user.amount + pendingInterest.
        // We unstake the full stakeAmount + expected interest.
        // Interest = stakeAmount * 500 / 10000 = 2,500 BTD
        // But splitWithdrawal proportionally splits. To get ALL interest + principal,
        // we need to unstake totalAvailable = stakeAmount + pending.
        // However we can just unstake stakeAmount (getting proportional split)
        // and verify the BTD total supply increased by the interest amount.
        uint256 aliceBTDBefore = btd.balanceOf(alice);

        vm.startPrank(alice);
        interestPool.unstakeBTD(stakeAmount);
        vm.stopPrank();

        uint256 aliceBTDAfter = btd.balanceOf(alice);
        uint256 btdReceived = aliceBTDAfter - aliceBTDBefore;

        // Alice receives exactly stakeAmount from unstake (proportional split)
        assertEq(btdReceived, stakeAmount, "Unstake returns requested amount");

        // But new BTD was minted as interest - check supply increase
        uint256 btdSupplyAfter = btd.totalSupply();
        uint256 supplyIncrease = btdSupplyAfter - btdSupplyBefore;

        // Interest was minted: interestShare to alice + treasury fee (5% of interestShare)
        // For 5% annual on 50k for 1 year: ~2,500 BTD interest
        // Treasury gets 5% of that: ~125 BTD
        // Total minted: ~2,625 BTD
        assertGt(supplyIncrease, 0, "BTD supply should increase from interest");
        // The interest portion (what was minted to alice as part of unstake):
        // interestShare = stakeAmount * pending / (stakeAmount + pending)
        // ≈ stakeAmount * 2500 / 52500 ≈ 2381 BTD (minted to alice)
        // Treasury gets 5% of 2381 = ~119 BTD
        // Total new BTD ≈ 2500 BTD
        assertApproxEqRel(supplyIncrease, 2500e18, 0.1e18, "~2500 BTD minted as interest");
    }

    /// @notice Stake BTB, accrue interest over 1 year
    function test_interest_stakeBTB_accrueOverTime() public {
        // Create BTB via undercollateralized redemption
        _mintBTDForUser(alice, 10e8);
        _crashBTCPrice(51_000e18);
        _setBTBPrice(0.8e18);

        uint256 redeemAmount = 50_000e18;
        vm.startPrank(alice);
        btd.approve(address(minter), redeemAmount);
        minter.redeemBTD(redeemAmount);
        vm.stopPrank();

        uint256 btbBalance = btb.balanceOf(alice);
        assertGt(btbBalance, 0, "Should have BTB");

        // Restore prices for clean interest test
        _setWBTCPrice(WBTC_PRICE);
        _setBTBPrice(BTB_PRICE);

        uint256 stakeAmount = btbBalance > 10_000e18 ? 10_000e18 : btbBalance;

        vm.startPrank(alice);
        btb.approve(address(interestPool), stakeAmount);
        interestPool.stakeBTB(stakeAmount);
        vm.stopPrank();

        // Warp 1 year
        vm.warp(block.timestamp + 365 days);

        // Unstake uses splitWithdrawal which proportionally splits withdrawal
        // between interest and principal. To claim interest separately,
        // unstake the full amount (which includes proportional interest)
        // then check that totalBTB > what was staked.
        // The key insight: unstake(stakeAmount) returns exactly stakeAmount
        // but part is newly-minted interest and part is returned principal.
        // To verify interest accrued, we unstake MORE than stakeAmount
        // (totalAvailable = principal + pendingInterest).
        uint256 btbBefore = btb.balanceOf(alice);

        // Unstake full available (principal + interest) by passing
        // total available amount
        vm.startPrank(alice);
        // First unstake the principal amount
        interestPool.unstakeBTB(stakeAmount);
        vm.stopPrank();

        uint256 btbAfter = btb.balanceOf(alice);
        assertGe(btbAfter, btbBefore, "BTB balance should not decrease after unstake");

        // The actual interest was minted internally. Let's verify via
        // checking BTB totalSupply increased (interest was minted)
        uint256 totalBTBSupply = btb.totalSupply();
        assertGt(totalBTBSupply, btbBalance, "BTB supply should increase from interest");
    }

    /// @notice Treasury fee: 5% of BTD interest goes to treasury
    function test_interest_treasuryFee() public {
        _mintBTDForUser(alice, 10e8);

        uint256 treasuryBTDBefore = btd.balanceOf(address(treasury));

        uint256 stakeAmount = 50_000e18;
        vm.startPrank(alice);
        btd.approve(address(interestPool), stakeAmount);
        interestPool.stakeBTD(stakeAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        vm.startPrank(alice);
        interestPool.unstakeBTD(stakeAmount);
        vm.stopPrank();

        uint256 treasuryBTDAfter = btd.balanceOf(address(treasury));
        uint256 treasuryFee = treasuryBTDAfter - treasuryBTDBefore;

        // Treasury should receive 5% of the interest paid to alice
        // Interest ≈ 2500 BTD, treasury fee ≈ 125 BTD
        assertGt(treasuryFee, 0, "Treasury should receive interest fee");
        assertApproxEqRel(treasuryFee, 125e18, 0.05e18, "~125 BTD treasury fee");
    }

    /// @notice Multiple users: bob earns ~2x alice (2x stake)
    function test_interest_multipleUsers() public {
        _mintBTDForUser(alice, 10e8);
        _mintBTDForUser(bob, 20e8);

        uint256 aliceStake = 50_000e18;
        uint256 bobStake = 100_000e18;

        vm.startPrank(alice);
        btd.approve(address(interestPool), aliceStake);
        interestPool.stakeBTD(aliceStake);
        vm.stopPrank();

        vm.startPrank(bob);
        btd.approve(address(interestPool), bobStake);
        interestPool.stakeBTD(bobStake);
        vm.stopPrank();

        vm.warp(block.timestamp + 365 days);

        uint256 aliceBTDBefore = btd.balanceOf(alice);
        vm.startPrank(alice);
        interestPool.unstakeBTD(aliceStake);
        vm.stopPrank();
        uint256 aliceInterest = btd.balanceOf(alice) - aliceBTDBefore - aliceStake;

        uint256 bobBTDBefore = btd.balanceOf(bob);
        vm.startPrank(bob);
        interestPool.unstakeBTD(bobStake);
        vm.stopPrank();
        uint256 bobInterest = btd.balanceOf(bob) - bobBTDBefore - bobStake;

        // Bob staked 2x, should earn ~2x interest
        assertApproxEqRel(bobInterest, aliceInterest * 2, 0.02e18, "Bob ~2x interest");
    }

    /// @notice Rate oracle updates the rate
    function test_interest_rateUpdate() public {
        _mintBTDForUser(alice, 10e8);

        uint256 stakeAmount = 50_000e18;
        vm.startPrank(alice);
        btd.approve(address(interestPool), stakeAmount);
        interestPool.stakeBTD(stakeAmount);
        vm.stopPrank();

        // Warp > 1 day so rate update cooldown passes
        vm.warp(block.timestamp + 2 days);

        // deployer is the rateOracle, can call updateBTDAnnualRate
        interestPool.updateBTDAnnualRate();

        // Verify rate was updated (read the pool state)
        (, , , , uint256 annualRateBps) = _getBTDPoolState();
        assertGt(annualRateBps, 0, "Rate should be set");
    }

    /// @notice stBTD vault: deposit and withdraw
    function test_stBTD_vault_depositWithdraw() public {
        _mintBTDForUser(alice, 1e8);

        uint256 depositAmount = 10_000e18;

        vm.startPrank(alice);
        btd.approve(address(stbtd), depositAmount);
        uint256 shares = stbtd.deposit(depositAmount, alice);
        vm.stopPrank();

        assertGt(shares, 0, "Should receive shares");
        assertEq(stbtd.balanceOf(alice), shares, "Share balance check");

        // Withdraw
        vm.startPrank(alice);
        stbtd.withdraw(depositAmount, alice, alice);
        vm.stopPrank();

        assertEq(stbtd.balanceOf(alice), 0, "Shares should be burned");
    }

    /// @notice stBTB vault: deposit and withdraw
    function test_stBTB_vault_depositWithdraw() public {
        // Create BTB first
        _mintBTDForUser(alice, 10e8);
        _crashBTCPrice(51_000e18);
        _setBTBPrice(0.8e18);

        uint256 redeemAmount = 50_000e18;
        vm.startPrank(alice);
        btd.approve(address(minter), redeemAmount);
        minter.redeemBTD(redeemAmount);
        vm.stopPrank();

        uint256 btbBalance = btb.balanceOf(alice);
        assertGt(btbBalance, 0, "Should have BTB");

        uint256 depositAmount = btbBalance > 5_000e18 ? 5_000e18 : btbBalance;

        vm.startPrank(alice);
        btb.approve(address(stbtb), depositAmount);
        uint256 shares = stbtb.deposit(depositAmount, alice);
        vm.stopPrank();

        assertGt(shares, 0, "Should receive stBTB shares");

        vm.startPrank(alice);
        stbtb.withdraw(depositAmount, alice, alice);
        vm.stopPrank();

        assertEq(stbtb.balanceOf(alice), 0, "stBTB shares should be burned");
    }

    // ============================================================
    //                  D. FARMING TESTS (5)
    // ============================================================

    /// @notice Deposit BTD, warp time, claim BRS rewards
    function test_farming_deposit_accrue_claim() public {
        _mintBTDForUser(alice, 1e8);

        uint256 depositAmount = 10_000e18;

        vm.startPrank(alice);
        btd.approve(address(farmingPool), depositAmount);
        farmingPool.deposit(0, depositAmount);
        vm.stopPrank();

        // Warp 1 day
        vm.warp(block.timestamp + 1 days);

        uint256 pending = farmingPool.pendingReward(0, alice);
        assertGt(pending, 0, "Should have pending rewards");

        uint256 brsBefore = brs.balanceOf(alice);
        vm.prank(alice);
        farmingPool.claim(0);
        uint256 brsReceived = brs.balanceOf(alice) - brsBefore;

        assertGt(brsReceived, 0, "Should receive BRS");
    }

    /// @notice Withdraw principal + claim BRS rewards
    function test_farming_withdraw_withRewards() public {
        _mintBTDForUser(alice, 1e8);

        uint256 depositAmount = 10_000e18;
        vm.startPrank(alice);
        btd.approve(address(farmingPool), depositAmount);
        farmingPool.deposit(0, depositAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        uint256 btdBefore = btd.balanceOf(alice);
        uint256 brsBefore = brs.balanceOf(alice);

        vm.prank(alice);
        farmingPool.withdraw(0, depositAmount);

        uint256 btdReturned = btd.balanceOf(alice) - btdBefore;
        uint256 brsReceived = brs.balanceOf(alice) - brsBefore;

        assertEq(btdReturned, depositAmount, "Should return full deposit");
        assertGt(brsReceived, 0, "Should receive BRS rewards");
    }

    /// @notice Fund distribution: 20% treasury, 10% foundation, 10% team
    function test_farming_fundDistribution() public {
        _mintBTDForUser(alice, 1e8);

        uint256 depositAmount = 10_000e18;
        vm.startPrank(alice);
        btd.approve(address(farmingPool), depositAmount);
        farmingPool.deposit(0, depositAmount);
        vm.stopPrank();

        uint256 treasuryBRSBefore = brs.balanceOf(address(treasury));
        uint256 foundationBRSBefore = brs.balanceOf(foundation);
        uint256 teamBRSBefore = brs.balanceOf(team);

        // Warp and trigger pool update
        vm.warp(block.timestamp + 1 days);
        farmingPool.updatePool(0);

        uint256 treasuryBRS = brs.balanceOf(address(treasury)) - treasuryBRSBefore;
        uint256 foundationBRS = brs.balanceOf(foundation) - foundationBRSBefore;
        uint256 teamBRS = brs.balanceOf(team) - teamBRSBefore;

        assertGt(treasuryBRS, 0, "Treasury should get BRS");
        assertGt(foundationBRS, 0, "Foundation should get BRS");
        assertGt(teamBRS, 0, "Team should get BRS");

        // Treasury share should be ~2x foundation/team (20% vs 10%)
        assertApproxEqRel(treasuryBRS, foundationBRS * 2, 0.02e18, "Treasury ~2x foundation");
        assertApproxEqRel(foundationBRS, teamBRS, 0.02e18, "Foundation ~= team");
    }

    /// @notice Multiple pools: rewards proportional to allocPoint
    function test_farming_multiplePoolsAllocation() public {
        // Add a second pool with 2x weight
        farmingPool.addPool(IERC20(address(btd)), 200, IFarmingPool.PoolKind.Single);

        _mintBTDForUser(alice, 2e8);
        _mintBTDForUser(bob, 2e8);

        uint256 depositAmount = 10_000e18;

        // Alice deposits in pool 0 (weight 100)
        vm.startPrank(alice);
        btd.approve(address(farmingPool), depositAmount);
        farmingPool.deposit(0, depositAmount);
        vm.stopPrank();

        // Bob deposits in pool 1 (weight 200)
        vm.startPrank(bob);
        btd.approve(address(farmingPool), depositAmount);
        farmingPool.deposit(1, depositAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        uint256 alicePending = farmingPool.pendingReward(0, alice);
        uint256 bobPending = farmingPool.pendingReward(1, bob);

        // Bob's pool has 2x weight, so ~2x rewards
        assertApproxEqRel(bobPending, alicePending * 2, 0.05e18, "Pool 1 ~2x rewards");
    }

    /// @notice Emergency withdraw: forfeit rewards, get principal
    function test_farming_emergencyWithdraw() public {
        _mintBTDForUser(alice, 1e8);

        uint256 depositAmount = 10_000e18;
        vm.startPrank(alice);
        btd.approve(address(farmingPool), depositAmount);
        farmingPool.deposit(0, depositAmount);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);

        // Verify there are pending rewards
        uint256 pending = farmingPool.pendingReward(0, alice);
        assertGt(pending, 0, "Should have pending rewards");

        uint256 btdBefore = btd.balanceOf(alice);
        uint256 brsBefore = brs.balanceOf(alice);

        vm.prank(alice);
        farmingPool.emergencyWithdraw(0);

        // Should get principal back, no BRS
        uint256 btdReturned = btd.balanceOf(alice) - btdBefore;
        uint256 brsReceived = brs.balanceOf(alice) - brsBefore;

        assertEq(btdReturned, depositAmount, "Should return full deposit");
        assertEq(brsReceived, 0, "No BRS on emergency withdraw");
    }

    // ============================================================
    //              E. GOVERNANCE / CONFIG TESTS (3)
    // ============================================================

    /// @notice Change mintFee, verify new fee applies
    function test_governance_paramChange() public {
        // Change mint fee from 50bp to 100bp (1%)
        gov.setParam(ConfigGov.ParamType.MintFeeBp, 100);

        _mintBTDForUser(alice, 1e8);

        // Fee should be 1% of ~102,000 = ~1,020 BTD
        uint256 treasuryBTD = btd.balanceOf(address(treasury));
        assertApproxEqRel(treasuryBTD, 1_020e18, 0.01e18, "~1020 BTD fee at 1%");
    }

    /// @notice Batch update params, verify all
    function test_governance_batchParamUpdate() public {
        ConfigGov.ParamType[] memory types = new ConfigGov.ParamType[](3);
        uint256[] memory vals = new uint256[](3);

        types[0] = ConfigGov.ParamType.MintFeeBp;
        vals[0] = 100;  // 1%
        types[1] = ConfigGov.ParamType.RedeemFeeBp;
        vals[1] = 100;  // 1%
        types[2] = ConfigGov.ParamType.BaseRateDefault;
        vals[2] = 300;  // 3%

        gov.setParamsBatch(types, vals);

        assertEq(gov.mintFeeBP(), 100, "MintFee updated");
        assertEq(gov.redeemFeeBP(), 100, "RedeemFee updated");
        assertEq(gov.baseRateDefault(), 300, "BaseRate updated");
    }

    /// @notice Out-of-range param / non-owner reverts
    function test_governance_paramValidation_revert() public {
        // Mint fee > 1000bp (10%) should revert
        vm.expectRevert("ConfigGov: mint fee too high");
        gov.setParam(ConfigGov.ParamType.MintFeeBp, 1500);

        // Non-owner should revert
        vm.prank(alice);
        vm.expectRevert();
        gov.setParam(ConfigGov.ParamType.MintFeeBp, 100);
    }

    // ============================================================
    //              F. PRICE SCENARIO TESTS (4)
    // ============================================================

    /// @notice BTC crashes 50%: CR drops, compensation mode activates
    function test_scenario_btcCrash50pct() public {
        _mintBTDForUser(alice, 10e8);

        // After minting, CR = 100% because btdGross (including fee) = WBTC value / IUSD
        // Verify it starts at exactly ~100%
        uint256 crBefore = minter.getCollateralRatio();
        assertGe(crBefore, 1e18, "CR should be >= 100% initially");

        // Crash 50%
        _crashBTCPrice(WBTC_PRICE / 2); // $51,000

        uint256 crAfter = minter.getCollateralRatio();
        assertLt(crAfter, 1e18, "CR should be < 100% after crash");

        // Redeeming now should give BTB compensation
        _setBTBPrice(0.8e18);
        uint256 redeemAmount = 10_000e18;

        vm.startPrank(alice);
        btd.approve(address(minter), redeemAmount);
        minter.redeemBTD(redeemAmount);
        vm.stopPrank();

        assertGt(btb.balanceOf(alice), 0, "Should get BTB compensation");
    }

    /// @notice BTC surges 100%: CR improves, full WBTC redemption
    function test_scenario_btcSurge100pct() public {
        _mintBTDForUser(alice, 10e8);

        // Double price
        _setWBTCPrice(WBTC_PRICE * 2); // $204,000

        uint256 cr = minter.getCollateralRatio();
        // CR starts at ~100% with original price, doubling price => CR ~200%
        assertGe(cr, 2e18, "CR should be >= 200%");

        // Redeem should give full WBTC
        uint256 redeemAmount = 50_000e18;

        vm.startPrank(alice);
        btd.approve(address(minter), redeemAmount);

        uint256 wbtcBefore = wbtc.balanceOf(alice);
        minter.redeemBTD(redeemAmount);
        vm.stopPrank();

        uint256 wbtcReceived = wbtc.balanceOf(alice) - wbtcBefore;
        assertGt(wbtcReceived, 0, "Should get WBTC back");
        assertEq(btb.balanceOf(alice), 0, "No BTB when fully collateralized");
    }

    /// @notice BTB price collapse triggers BRS three-tier compensation
    function test_scenario_btbPriceCollapse() public {
        _mintBTDForUser(alice, 10e8);
        _crashBTCPrice(51_000e18); // CR ~ 50%

        // BTB collapses below minBTBPrice ($0.5)
        _setBTBPrice(0.1e18); // $0.10
        _setBRSPrice(1e18);

        uint256 redeemAmount = 10_000e18;
        vm.startPrank(alice);
        btd.approve(address(minter), redeemAmount);
        minter.redeemBTD(redeemAmount);
        vm.stopPrank();

        assertGt(btb.balanceOf(alice), 0, "Should receive BTB");
        assertGt(brs.balanceOf(alice), 0, "Should receive BRS (price collapse)");
    }

    /// @notice IUSD inflation affects mint amount
    function test_scenario_iusdInflation() public {
        // Normal mint at IUSD=$1
        _mintBTDForUser(alice, 1e8);
        uint256 btdAtNormal = btd.balanceOf(alice);

        // Set IUSD to $1.05 (5% inflation)
        iusdManager.setPrice(1.05e18);
        priceOracle.setIUSDPrice(1.05e18);

        _mintBTDForUser(bob, 1e8);
        uint256 btdAtInflation = btd.balanceOf(bob);

        // Bob should receive fewer BTD due to inflation
        assertLt(btdAtInflation, btdAtNormal, "Inflation should reduce BTD minted");

        // Difference should be ~5%
        uint256 reduction = btdAtNormal - btdAtInflation;
        assertApproxEqRel(reduction, btdAtNormal * 5 / 100, 0.05e18, "~5% reduction");
    }

    // ============================================================
    //                G. EDGE CASE TESTS (5)
    // ============================================================

    /// @notice 3 users mint concurrently, verify all correct
    function test_edge_multiUserConcurrentMints() public {
        uint256 amount1 = 5e8;
        uint256 amount2 = 10e8;
        uint256 amount3 = 3e8;

        _mintBTDForUser(alice, amount1);
        _mintBTDForUser(bob, amount2);
        _mintBTDForUser(carol, amount3);

        // Verify each received correct proportional amount
        uint256 aliceBTD = btd.balanceOf(alice);
        uint256 bobBTD = btd.balanceOf(bob);
        uint256 carolBTD = btd.balanceOf(carol);

        // Bob deposited 2x alice, should have ~2x BTD
        assertApproxEqRel(bobBTD, aliceBTD * 2, 0.01e18, "Bob ~2x alice");
        // Carol deposited 60% of alice
        assertApproxEqRel(carolBTD * 5, aliceBTD * 3, 0.01e18, "Carol ~60% of alice");

        // Total WBTC in treasury
        (uint256 wbtcBal, , ) = treasury.getBalances();
        assertEq(wbtcBal, amount1 + amount2 + amount3, "All WBTC in treasury");
    }

    /// @notice Mint then redeem: only fees should be lost
    function test_edge_mintThenRedeem_valuePreservation() public {
        uint256 initialWBTC = 10e8;
        _mintBTDForUser(alice, initialWBTC);

        uint256 btdBalance = btd.balanceOf(alice);

        vm.startPrank(alice);
        btd.approve(address(minter), btdBalance);
        minter.redeemBTD(btdBalance);
        vm.stopPrank();

        uint256 finalWBTC = wbtc.balanceOf(alice);
        // alice started with 1000 BTC, used 10, should get most back
        uint256 wbtcReturned = finalWBTC - (1000e8 - initialWBTC);

        // Loss should be ~1% (0.5% mint fee + 0.5% redeem fee, compounded)
        // Mint fee reduces BTD, redeem fee reduces BTD further, so ~1% WBTC loss
        uint256 lossPercent = (initialWBTC - wbtcReturned) * 10000 / initialWBTC;
        assertApproxEqAbs(lossPercent, 100, 5, "~1% loss from fees");
    }

    /// @notice Max WBTC amount (10,000 BTC), no overflow
    function test_edge_maxWBTCAmount() public {
        // Give alice 10k BTC
        wbtc.transfer(alice, 10_000e8);

        vm.startPrank(alice);
        wbtc.approve(address(minter), 10_000e8);
        minter.mintBTD(10_000e8);
        vm.stopPrank();

        // Should not overflow, alice should have ~10,000 * 102,000 * 0.995 = ~1,014,900,000 BTD
        uint256 aliceBTD = btd.balanceOf(alice);
        assertGt(aliceBTD, 1_000_000_000e18, "Should have ~1B BTD");
    }

    /// @notice Test both sides of the CR=100% boundary
    function test_edge_exactCR100Boundary() public {
        _mintBTDForUser(alice, 10e8);

        uint256 totalBTDSupply = btd.totalSupply();
        // Price for CR exactly 100%: price = totalBTD * iusdPrice / (wbtcBalance)
        // wbtcBalance = 10e8, iusdPrice = 1e18
        // price (8→18 normalized): totalBTD / 10
        uint256 exactPrice = totalBTDSupply / 10;

        // Slightly above CR=100%
        _setWBTCPrice(exactPrice + 1e14);
        uint256 crAbove = minter.getCollateralRatio();
        assertGe(crAbove, 1e18, "CR >= 100%");

        // Slightly below CR=100%
        _setWBTCPrice(exactPrice - 1e14);
        uint256 crBelow = minter.getCollateralRatio();
        assertLt(crBelow, 1e18, "CR < 100%");

        // Restore for cleanup
        _setWBTCPrice(WBTC_PRICE);
    }

    /// @notice Treasury BRS shortfall: partial BRS payout + event
    function test_edge_treasuryBRSShortfall() public {
        // Setup: drain treasury BRS first
        // Treasury has some BRS from setUp. Let's create a scenario
        // where compensation exceeds treasury BRS balance.

        _mintBTDForUser(alice, 100e8); // 100 BTC worth of BTD

        // Crash price hard
        _crashBTCPrice(20_000e18); // $20k, CR ~20%
        _setBTBPrice(0.1e18); // Very low BTB
        _setBRSPrice(0.01e18); // Very low BRS (so BRS amount needed is huge)

        // Attempt large redemption to trigger shortfall
        uint256 redeemAmount = 100_000e18;

        vm.startPrank(alice);
        btd.approve(address(minter), redeemAmount);

        // The compensate function handles shortfall gracefully
        vm.expectEmit(false, false, false, false);
        emit Treasury.BRSCompensationShortfall(alice, 0, 0);
        minter.redeemBTD(redeemAmount);
        vm.stopPrank();

        // Alice should still get what's available
        // The important thing is no revert
    }

    // ============================================================
    //              H. ACCESS CONTROL TESTS (4)
    // ============================================================

    /// @notice Treasury deposit/withdraw/compensate restricted to Minter
    function test_access_treasury_onlyMinter() public {
        // Non-minter cannot deposit
        vm.startPrank(alice);
        vm.expectRevert("Treasury: only Minter");
        treasury.depositWBTC(1e8);
        vm.stopPrank();

        // Non-minter cannot withdraw
        vm.startPrank(alice);
        vm.expectRevert("Treasury: only Minter");
        treasury.withdrawWBTC(1e8);
        vm.stopPrank();

        // Non-minter cannot compensate
        vm.startPrank(alice);
        vm.expectRevert("Treasury: only Minter");
        treasury.compensate(alice, 1e18);
        vm.stopPrank();
    }

    /// @notice Cannot mint BTD/BTB directly without MINTER_ROLE
    function test_access_cannotMintTokenDirectly() public {
        vm.startPrank(alice);

        vm.expectRevert();
        btd.mint(alice, 1000e18);

        vm.expectRevert();
        btb.mint(alice, 1000e18);

        vm.stopPrank();
    }

    /// @notice ConfigCore setCoreContracts can only be called once
    function test_access_configCoreImmutable() public {
        // core already had setCoreContracts called and ownership renounced
        // Any attempt should fail (owner is zero address now)
        vm.expectRevert();
        core.setCoreContracts(
            address(treasury), address(minter), address(priceOracle),
            address(iusdManager), address(interestPool), address(farmingPool)
        );
    }

    /// @notice Minter pause blocks operations, unpause allows
    function test_access_minterPauseUnpause() public {
        // Pause minter
        minter.pause();

        // Mint should revert
        vm.startPrank(alice);
        wbtc.approve(address(minter), 1e8);
        vm.expectRevert();
        minter.mintBTD(1e8);
        vm.stopPrank();

        // Unpause
        minter.unpause();

        // Mint should work
        _mintBTDForUser(alice, 1e8);
        assertGt(btd.balanceOf(alice), 0, "Should mint after unpause");
    }

    // ============================================================
    //                  Internal Helpers
    // ============================================================

    /// @notice Read BTD pool state from InterestPool
    function _getBTDPoolState() internal view returns (
        address token,
        uint256 totalStaked,
        uint256 accInterestPerShare,
        uint256 lastAccrual,
        uint256 annualRateBps
    ) {
        (IMintableERC20 t, uint256 ts, uint256 aips, uint256 la, uint256 arb) = _readBTDPool();
        return (address(t), ts, aips, la, arb);
    }

    /// @notice Helper to read btdPool struct fields
    function _readBTDPool() internal view returns (
        IMintableERC20, uint256, uint256, uint256, uint256
    ) {
        // InterestPool.btdPool is a public struct, returns all fields
        return interestPool.btdPool();
    }
}
