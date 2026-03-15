// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Initializable} from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../../contracts/ConfigGov.sol";
import "../../contracts/Treasury.sol";
import "../../contracts/Minter.sol";
import "../../contracts/InterestPool.sol";
import "../../contracts/FarmingPool.sol";
import "../../contracts/IdealUSDManager.sol";
import "../../contracts/PriceOracle.sol";
import "../../contracts/ConfigCore.sol";
import "../../contracts/BTD.sol";
import "../../contracts/BTB.sol";
import "../../contracts/BRS.sol";
import "../../contracts/UniswapV2TWAPOracle.sol";
import "../../contracts/stBTD.sol";
import "../../contracts/stBTB.sol";
import "../../contracts/local/MockWBTC.sol";
import "../../contracts/local/MockUSDC.sol";
import "../../contracts/local/MockPriceOracle.sol";
import "../../contracts/local/MockIUSDManager.sol";
import "../../contracts/local/MockAggregatorV3.sol";
import "../../contracts/local/UniswapV2Pair.sol";
import "../../contracts/libraries/Constants.sol";
import "../helpers/ProxyTestHelper.sol";

/// @title Upgradeability Unit Tests
/// @notice Tests UUPS upgrade patterns for all upgradeable contracts
contract UpgradeabilityUnitTest is Test {

    address public deployer = address(this);
    address public alice = address(0xA11CE);
    address public mockRouter = address(0xDEAD);

    // ============ Test: Cannot reinitialize proxy ============

    function test_configGov_cannotReinitialize() public {
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        gov.initialize(deployer);
    }

    function test_treasury_cannotReinitialize() public {
        (ConfigCore core,,) = _deployMinimalCore();
        Treasury treasury = ProxyTestHelper.deployTreasury(deployer, address(core), mockRouter);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        treasury.initialize(deployer, address(core), mockRouter);
    }

    function test_minter_cannotReinitialize() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        Minter minter = ProxyTestHelper.deployMinter(deployer, address(core), address(gov));
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        minter.initialize(deployer, address(core), address(gov));
    }

    function test_interestPool_cannotReinitialize() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        InterestPool pool = ProxyTestHelper.deployInterestPool(deployer, address(core), address(gov), deployer);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        pool.initialize(deployer, address(core), address(gov), deployer);
    }

    function test_farmingPool_cannotReinitialize() public {
        (ConfigCore core,,) = _deployMinimalCore();
        BRS brs = new BRS(deployer);
        address[] memory funds = new address[](0);
        uint256[] memory shares = new uint256[](0);
        FarmingPool farm = ProxyTestHelper.deployFarmingPool(deployer, address(brs), address(core), funds, shares);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        farm.initialize(deployer, address(brs), address(core), funds, shares);
    }

    function test_idealUSDManager_cannotReinitialize() public {
        (ConfigGov gov, IdealUSDManager mgr) = _deployIUSDManager();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        mgr.initialize(deployer, address(gov), 1e18);
    }

    function test_btd_cannotReinitialize() public {
        BTD btd = ProxyTestHelper.deployBTD(deployer);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        btd.initialize(deployer);
    }

    function test_btb_cannotReinitialize() public {
        BTB btb = ProxyTestHelper.deployBTB(deployer);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        btb.initialize(deployer);
    }

    function test_twapOracle_cannotReinitialize() public {
        UniswapV2TWAPOracle oracle = ProxyTestHelper.deployTWAPOracle(deployer);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        oracle.initialize(deployer);
    }

    function test_stBTD_cannotReinitialize() public {
        BTD btd = ProxyTestHelper.deployBTD(deployer);
        stBTD vault = ProxyTestHelper.deployStBTD(IERC20(address(btd)), deployer);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(IERC20(address(btd)), deployer);
    }

    function test_stBTB_cannotReinitialize() public {
        BTB btb = ProxyTestHelper.deployBTB(deployer);
        stBTB vault = ProxyTestHelper.deployStBTB(IERC20(address(btb)), deployer);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        vault.initialize(IERC20(address(btb)), deployer);
    }

    // ============ Test: Cannot initialize implementation directly ============

    function test_configGov_implCannotInitialize() public {
        ConfigGov impl = new ConfigGov();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(deployer);
    }

    function test_treasury_implCannotInitialize() public {
        Treasury impl = new Treasury();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(deployer, address(1), mockRouter);
    }

    function test_minter_implCannotInitialize() public {
        Minter impl = new Minter();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(deployer, address(1), address(2));
    }

    function test_interestPool_implCannotInitialize() public {
        InterestPool impl = new InterestPool();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(deployer, address(1), address(2), address(3));
    }

    function test_farmingPool_implCannotInitialize() public {
        FarmingPool impl = new FarmingPool();
        address[] memory funds = new address[](0);
        uint256[] memory shares = new uint256[](0);
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(deployer, address(1), address(2), funds, shares);
    }

    function test_idealUSDManager_implCannotInitialize() public {
        IdealUSDManager impl = new IdealUSDManager();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(deployer, address(1), 1e18);
    }

    function test_btd_implCannotInitialize() public {
        BTD impl = new BTD();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(deployer);
    }

    function test_btb_implCannotInitialize() public {
        BTB impl = new BTB();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(deployer);
    }

    function test_twapOracle_implCannotInitialize() public {
        UniswapV2TWAPOracle impl = new UniswapV2TWAPOracle();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(deployer);
    }

    function test_stBTD_implCannotInitialize() public {
        stBTD impl = new stBTD();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(IERC20(address(1)), deployer);
    }

    function test_stBTB_implCannotInitialize() public {
        stBTB impl = new stBTB();
        vm.expectRevert(Initializable.InvalidInitialization.selector);
        impl.initialize(IERC20(address(1)), deployer);
    }

    // ============ Test: Owner can upgrade via upgradeToAndCall ============

    function test_configGov_ownerCanUpgrade() public {
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);

        // Set a param to verify state
        gov.setParam(ConfigGov.ParamType.MintFeeBp, 100);
        assertEq(gov.mintFeeBP(), 100);

        // Deploy new implementation and upgrade
        ConfigGov newImpl = new ConfigGov();
        gov.upgradeToAndCall(address(newImpl), "");

        // State preserved after upgrade
        assertEq(gov.mintFeeBP(), 100, "State should be preserved after upgrade");
    }

    function test_treasury_ownerCanUpgrade() public {
        (ConfigCore core,,) = _deployMinimalCore();
        Treasury treasury = ProxyTestHelper.deployTreasury(deployer, address(core), mockRouter);

        // Upgrade
        Treasury newImpl = new Treasury();
        treasury.upgradeToAndCall(address(newImpl), "");

        // State preserved
        assertEq(treasury.router(), mockRouter, "Router should be preserved");
    }

    function test_minter_ownerCanUpgrade() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        Minter minter = ProxyTestHelper.deployMinter(deployer, address(core), address(gov));

        Minter newImpl = new Minter();
        minter.upgradeToAndCall(address(newImpl), "");

        assertEq(minter.configCore(), address(core), "Core should be preserved");
    }

    // ============ Test: BTD/BTB upgrade ============

    function test_btd_adminCanUpgrade() public {
        BTD btd = ProxyTestHelper.deployBTD(deployer);
        btd.grantRole(btd.MINTER_ROLE(), deployer);
        btd.mint(alice, 1000e18);

        BTD newImpl = new BTD();
        btd.upgradeToAndCall(address(newImpl), "");

        assertEq(btd.balanceOf(alice), 1000e18, "Balance should be preserved");
        assertTrue(btd.hasRole(btd.MINTER_ROLE(), deployer), "MINTER_ROLE should be preserved");
    }

    function test_btd_nonAdminCannotUpgrade() public {
        BTD btd = ProxyTestHelper.deployBTD(deployer);
        BTD newImpl = new BTD();

        vm.prank(alice);
        vm.expectRevert();
        btd.upgradeToAndCall(address(newImpl), "");
    }

    function test_btb_adminCanUpgrade() public {
        BTB btb = ProxyTestHelper.deployBTB(deployer);
        btb.grantRole(btb.MINTER_ROLE(), deployer);
        btb.mint(alice, 500e18);

        BTB newImpl = new BTB();
        btb.upgradeToAndCall(address(newImpl), "");

        assertEq(btb.balanceOf(alice), 500e18, "Balance should be preserved");
        assertTrue(btb.hasRole(btb.MINTER_ROLE(), deployer), "MINTER_ROLE should be preserved");
    }

    function test_btb_nonAdminCannotUpgrade() public {
        BTB btb = ProxyTestHelper.deployBTB(deployer);
        BTB newImpl = new BTB();

        vm.prank(alice);
        vm.expectRevert();
        btb.upgradeToAndCall(address(newImpl), "");
    }

    // ============ Test: TWAPOracle upgrade ============

    function test_twapOracle_ownerCanUpgrade() public {
        UniswapV2TWAPOracle oracle = ProxyTestHelper.deployTWAPOracle(deployer);

        // Create a pair and make an observation
        MockWBTC wbtc = new MockWBTC(deployer);
        MockUSDC usdc = new MockUSDC(deployer);
        UniswapV2Pair pair = new UniswapV2Pair();
        if (address(wbtc) < address(usdc)) {
            pair.initialize(address(wbtc), address(usdc));
        } else {
            pair.initialize(address(usdc), address(wbtc));
        }
        // Add liquidity
        address t0 = pair.token0();
        if (t0 == address(wbtc)) {
            wbtc.transfer(address(pair), 1e8);
            usdc.transfer(address(pair), 100_000e6);
        } else {
            usdc.transfer(address(pair), 100_000e6);
            wbtc.transfer(address(pair), 1e8);
        }
        pair.mint(deployer);

        // Record observation
        vm.warp(1_000_000);
        oracle.updateIfNeeded(address(pair));

        (, uint32 ts1,) = oracle.getObservationInfo(address(pair));
        assertEq(ts1, uint32(block.timestamp), "Observation should be recorded");

        // Upgrade
        UniswapV2TWAPOracle newImpl = new UniswapV2TWAPOracle();
        oracle.upgradeToAndCall(address(newImpl), "");

        // Observation preserved
        (, uint32 ts2,) = oracle.getObservationInfo(address(pair));
        assertEq(ts2, ts1, "Observation data should be preserved after upgrade");
    }

    function test_twapOracle_nonOwnerCannotUpgrade() public {
        UniswapV2TWAPOracle oracle = ProxyTestHelper.deployTWAPOracle(deployer);
        UniswapV2TWAPOracle newImpl = new UniswapV2TWAPOracle();

        vm.prank(alice);
        vm.expectRevert();
        oracle.upgradeToAndCall(address(newImpl), "");
    }

    // ============ Test: stBTD/stBTB upgrade ============

    function test_stBTD_ownerCanUpgrade() public {
        BTD btd = ProxyTestHelper.deployBTD(deployer);
        btd.grantRole(btd.MINTER_ROLE(), deployer);
        btd.mint(alice, 1000e18);
        stBTD vault = ProxyTestHelper.deployStBTD(IERC20(address(btd)), deployer);

        // Alice deposits
        vm.startPrank(alice);
        btd.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 100e18, "Alice should have 100 shares");

        // Upgrade
        stBTD newImpl = new stBTD();
        vault.upgradeToAndCall(address(newImpl), "");

        // Deposit preserved
        assertEq(vault.balanceOf(alice), 100e18, "Shares should be preserved after upgrade");
        assertEq(vault.totalAssets(), 100e18, "Total assets should be preserved");
    }

    function test_stBTD_nonOwnerCannotUpgrade() public {
        BTD btd = ProxyTestHelper.deployBTD(deployer);
        stBTD vault = ProxyTestHelper.deployStBTD(IERC20(address(btd)), deployer);
        stBTD newImpl = new stBTD();

        vm.prank(alice);
        vm.expectRevert();
        vault.upgradeToAndCall(address(newImpl), "");
    }

    function test_stBTB_ownerCanUpgrade() public {
        BTB btb = ProxyTestHelper.deployBTB(deployer);
        btb.grantRole(btb.MINTER_ROLE(), deployer);
        btb.mint(alice, 1000e18);
        stBTB vault = ProxyTestHelper.deployStBTB(IERC20(address(btb)), deployer);

        // Alice deposits
        vm.startPrank(alice);
        btb.approve(address(vault), 100e18);
        vault.deposit(100e18, alice);
        vm.stopPrank();

        assertEq(vault.balanceOf(alice), 100e18, "Alice should have 100 shares");

        // Upgrade
        stBTB newImpl = new stBTB();
        vault.upgradeToAndCall(address(newImpl), "");

        // Deposit preserved
        assertEq(vault.balanceOf(alice), 100e18, "Shares should be preserved after upgrade");
        assertEq(vault.totalAssets(), 100e18, "Total assets should be preserved");
    }

    function test_stBTB_nonOwnerCannotUpgrade() public {
        BTB btb = ProxyTestHelper.deployBTB(deployer);
        stBTB vault = ProxyTestHelper.deployStBTB(IERC20(address(btb)), deployer);
        stBTB newImpl = new stBTB();

        vm.prank(alice);
        vm.expectRevert();
        vault.upgradeToAndCall(address(newImpl), "");
    }

    // ============ Test: Non-owner upgrade reverts ============

    function test_configGov_nonOwnerCannotUpgrade() public {
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        ConfigGov newImpl = new ConfigGov();

        vm.prank(alice);
        vm.expectRevert();
        gov.upgradeToAndCall(address(newImpl), "");
    }

    function test_treasury_nonOwnerCannotUpgrade() public {
        (ConfigCore core,,) = _deployMinimalCore();
        Treasury treasury = ProxyTestHelper.deployTreasury(deployer, address(core), mockRouter);
        Treasury newImpl = new Treasury();

        vm.prank(alice);
        vm.expectRevert();
        treasury.upgradeToAndCall(address(newImpl), "");
    }

    function test_minter_nonOwnerCannotUpgrade() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        Minter minter = ProxyTestHelper.deployMinter(deployer, address(core), address(gov));
        Minter newImpl = new Minter();

        vm.prank(alice);
        vm.expectRevert();
        minter.upgradeToAndCall(address(newImpl), "");
    }

    function test_interestPool_nonOwnerCannotUpgrade() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        InterestPool pool = ProxyTestHelper.deployInterestPool(deployer, address(core), address(gov), deployer);
        InterestPool newImpl = new InterestPool();

        vm.prank(alice);
        vm.expectRevert();
        pool.upgradeToAndCall(address(newImpl), "");
    }

    function test_farmingPool_nonOwnerCannotUpgrade() public {
        (ConfigCore core,,) = _deployMinimalCore();
        BRS brs = new BRS(deployer);
        address[] memory funds = new address[](0);
        uint256[] memory shares = new uint256[](0);
        FarmingPool farm = ProxyTestHelper.deployFarmingPool(deployer, address(brs), address(core), funds, shares);
        FarmingPool newImpl = new FarmingPool();

        vm.prank(alice);
        vm.expectRevert();
        farm.upgradeToAndCall(address(newImpl), "");
    }

    // ============ Test: upgradeCore (×5) ============

    function test_minter_upgradeCore() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        Minter minter = ProxyTestHelper.deployMinter(deployer, address(core), address(gov));

        (ConfigCore newCore,,) = _deployMinimalCore();
        minter.upgradeCore(address(newCore));
        assertEq(minter.configCore(), address(newCore), "Core should be updated");
    }

    function test_minter_upgradeCore_zeroReverts() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        Minter minter = ProxyTestHelper.deployMinter(deployer, address(core), address(gov));

        vm.expectRevert("Invalid core");
        minter.upgradeCore(address(0));
    }

    function test_minter_upgradeCore_nonOwnerReverts() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        Minter minter = ProxyTestHelper.deployMinter(deployer, address(core), address(gov));

        vm.prank(alice);
        vm.expectRevert();
        minter.upgradeCore(address(1));
    }

    function test_treasury_upgradeCore() public {
        (ConfigCore core,,) = _deployMinimalCore();
        Treasury treasury = ProxyTestHelper.deployTreasury(deployer, address(core), mockRouter);

        (ConfigCore newCore,,) = _deployMinimalCore();
        treasury.upgradeCore(address(newCore));
        assertEq(treasury.configCore(), address(newCore), "Core should be updated");
    }

    function test_treasury_upgradeCore_zeroReverts() public {
        (ConfigCore core,,) = _deployMinimalCore();
        Treasury treasury = ProxyTestHelper.deployTreasury(deployer, address(core), mockRouter);

        vm.expectRevert("Invalid core");
        treasury.upgradeCore(address(0));
    }

    function test_treasury_upgradeCore_nonOwnerReverts() public {
        (ConfigCore core,,) = _deployMinimalCore();
        Treasury treasury = ProxyTestHelper.deployTreasury(deployer, address(core), mockRouter);

        vm.prank(alice);
        vm.expectRevert();
        treasury.upgradeCore(address(1));
    }

    function test_priceOracle_upgradeCore() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        PriceOracle oracle = ProxyTestHelper.deployPriceOracle(deployer, address(core), address(gov), address(0));

        (ConfigCore newCore,,) = _deployMinimalCore();
        oracle.upgradeCore(address(newCore));
        assertEq(address(oracle.core()), address(newCore), "Core should be updated");
    }

    function test_priceOracle_upgradeCore_zeroReverts() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        PriceOracle oracle = ProxyTestHelper.deployPriceOracle(deployer, address(core), address(gov), address(0));

        vm.expectRevert("Invalid core");
        oracle.upgradeCore(address(0));
    }

    function test_interestPool_upgradeCore() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        InterestPool pool = ProxyTestHelper.deployInterestPool(deployer, address(core), address(gov), deployer);

        (ConfigCore newCore,,) = _deployMinimalCore();
        pool.upgradeCore(address(newCore));
        assertEq(address(pool.core()), address(newCore), "Core should be updated");
    }

    function test_interestPool_upgradeCore_zeroReverts() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        InterestPool pool = ProxyTestHelper.deployInterestPool(deployer, address(core), address(gov), deployer);

        vm.expectRevert("Invalid core");
        pool.upgradeCore(address(0));
    }

    function test_farmingPool_upgradeCore() public {
        (ConfigCore core,,) = _deployMinimalCore();
        BRS brs = new BRS(deployer);
        address[] memory funds = new address[](0);
        uint256[] memory shares = new uint256[](0);
        FarmingPool farm = ProxyTestHelper.deployFarmingPool(deployer, address(brs), address(core), funds, shares);

        (ConfigCore newCore,,) = _deployMinimalCore();
        farm.upgradeCore(address(newCore));
        assertEq(address(farm.core()), address(newCore), "Core should be updated");
    }

    function test_farmingPool_upgradeCore_zeroReverts() public {
        (ConfigCore core,,) = _deployMinimalCore();
        BRS brs = new BRS(deployer);
        address[] memory funds = new address[](0);
        uint256[] memory shares = new uint256[](0);
        FarmingPool farm = ProxyTestHelper.deployFarmingPool(deployer, address(brs), address(core), funds, shares);

        vm.expectRevert("Invalid core");
        farm.upgradeCore(address(0));
    }

    // ============ Test: PriceOracle upgradeGov ============

    function test_priceOracle_upgradeGov() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        PriceOracle oracle = ProxyTestHelper.deployPriceOracle(deployer, address(core), address(gov), address(0));

        ConfigGov newGov = ProxyTestHelper.deployConfigGov(deployer);
        oracle.upgradeGov(address(newGov));
        assertEq(address(oracle.gov()), address(newGov), "Gov should be updated");
    }

    function test_priceOracle_upgradeGov_zeroReverts() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        PriceOracle oracle = ProxyTestHelper.deployPriceOracle(deployer, address(core), address(gov), address(0));

        vm.expectRevert("Invalid gov");
        oracle.upgradeGov(address(0));
    }

    function test_priceOracle_upgradeGov_nonOwnerReverts() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        PriceOracle oracle = ProxyTestHelper.deployPriceOracle(deployer, address(core), address(gov), address(0));

        vm.prank(alice);
        vm.expectRevert();
        oracle.upgradeGov(address(1));
    }

    // ============ Test: Storage preserved across upgrade (mint BTD → upgrade → balance intact) ============

    function test_minter_storagePreservedAcrossUpgrade() public {
        // Deploy full system
        MockWBTC wbtc = new MockWBTC(deployer);
        MockUSDC usdc = new MockUSDC(deployer);
        BTD btd = ProxyTestHelper.deployBTD(deployer);
        BTB btb = ProxyTestHelper.deployBTB(deployer);
        BRS brs = new BRS(deployer);

        ConfigCore core = new ConfigCore(
            address(wbtc), address(btd), address(btb), address(brs),
            address(new MockUSDC(deployer)), address(usdc), address(new MockUSDC(deployer)),
            address(0x6001), address(0x6002), address(0x6003), address(0x6004),
            address(0x5001), address(0x5002)
        );

        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        MockPriceOracle oracle = new MockPriceOracle();
        oracle.setAllPrices(100_000e18, 1e18, 1e18, 1e18, 1e18);
        MockIUSDManager iusdMgr = new MockIUSDManager(1e18);

        Treasury treasury = ProxyTestHelper.deployTreasury(deployer, address(core), mockRouter);
        Minter minter = ProxyTestHelper.deployMinter(deployer, address(core), address(gov));

        // Mock stBTD/stBTB
        vm.mockCall(address(0x5001), abi.encodeWithSignature("totalAssets()"), abi.encode(uint256(0)));
        vm.mockCall(address(0x5002), abi.encodeWithSignature("totalAssets()"), abi.encode(uint256(0)));

        core.setCoreContracts(
            address(treasury), address(minter), address(oracle), address(iusdMgr),
            address(0x7001), address(0x7002)
        );

        btd.grantRole(btd.MINTER_ROLE(), address(minter));

        // Mint BTD
        wbtc.transfer(alice, 1e8);
        vm.startPrank(alice);
        wbtc.approve(address(minter), 1e8);
        minter.mintBTD(1e8);
        vm.stopPrank();

        uint256 aliceBTDBefore = btd.balanceOf(alice);
        assertGt(aliceBTDBefore, 0, "Alice should have BTD");

        // Upgrade Minter
        Minter newImpl = new Minter();
        minter.upgradeToAndCall(address(newImpl), "");

        // Verify state is preserved
        uint256 aliceBTDAfter = btd.balanceOf(alice);
        assertEq(aliceBTDAfter, aliceBTDBefore, "BTD balance should be preserved after upgrade");
        assertEq(minter.configCore(), address(core), "Core address should be preserved");
        assertEq(minter.configGov(), address(gov), "Gov address should be preserved");
    }

    // ============ Test: After renounceOwnership, upgrade permanently reverts ============

    function test_configGov_renounceOwnership_permanentlyFreezes() public {
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);

        // Verify upgrade works before renounce
        ConfigGov impl1 = new ConfigGov();
        gov.upgradeToAndCall(address(impl1), "");

        // Renounce ownership
        gov.renounceOwnership();
        assertEq(gov.owner(), address(0), "Owner should be zero");

        // Upgrade should now permanently fail
        ConfigGov impl2 = new ConfigGov();
        vm.expectRevert();
        gov.upgradeToAndCall(address(impl2), "");
    }

    function test_minter_renounceOwnership_permanentlyFreezes() public {
        (ConfigCore core,,) = _deployMinimalCore();
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        Minter minter = ProxyTestHelper.deployMinter(deployer, address(core), address(gov));

        minter.renounceOwnership();
        assertEq(minter.owner(), address(0));

        Minter newImpl = new Minter();
        vm.expectRevert();
        minter.upgradeToAndCall(address(newImpl), "");
    }

    function test_treasury_renounceOwnership_permanentlyFreezes() public {
        (ConfigCore core,,) = _deployMinimalCore();
        Treasury treasury = ProxyTestHelper.deployTreasury(deployer, address(core), mockRouter);

        treasury.renounceOwnership();
        assertEq(treasury.owner(), address(0));

        Treasury newImpl = new Treasury();
        vm.expectRevert();
        treasury.upgradeToAndCall(address(newImpl), "");
    }

    // ============ Helpers ============

    function _deployMinimalCore() internal returns (ConfigCore core, BRS brs, BTD btd) {
        MockWBTC wbtc = new MockWBTC(deployer);
        MockUSDC usdc = new MockUSDC(deployer);
        btd = ProxyTestHelper.deployBTD(deployer);
        BTB btb = ProxyTestHelper.deployBTB(deployer);
        brs = new BRS(deployer);

        core = new ConfigCore(
            address(wbtc), address(btd), address(btb), address(brs),
            address(new MockUSDC(deployer)), address(usdc), address(new MockUSDC(deployer)),
            address(0x6001), address(0x6002), address(0x6003), address(0x6004),
            address(0x5001), address(0x5002)
        );
    }

    function _deployIUSDManager() internal returns (ConfigGov gov, IdealUSDManager mgr) {
        MockAggregatorV3 pce = new MockAggregatorV3(int256(300_00_000_000));
        gov = ProxyTestHelper.deployConfigGov(deployer);
        gov.setAddressParam(ConfigGov.AddressParamType.PceFeed, address(pce));
        mgr = ProxyTestHelper.deployIdealUSDManager(deployer, address(gov), 1e18);
    }
}
