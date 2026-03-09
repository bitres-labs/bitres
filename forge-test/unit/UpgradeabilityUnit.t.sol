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
import "../../contracts/local/MockWBTC.sol";
import "../../contracts/local/MockUSDC.sol";
import "../../contracts/local/MockPriceOracle.sol";
import "../../contracts/local/MockIUSDManager.sol";
import "../../contracts/local/MockAggregatorV3.sol";
import "../../contracts/libraries/Constants.sol";
import "../helpers/ProxyTestHelper.sol";

/// @title Upgradeability Unit Tests
/// @notice Tests UUPS upgrade patterns for all 7 upgradeable contracts
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
        (ConfigCore core, BRS brs,) = _deployMinimalCore();
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
        (ConfigCore core, BRS brs,) = _deployMinimalCore();
        address[] memory funds = new address[](0);
        uint256[] memory shares = new uint256[](0);
        FarmingPool farm = ProxyTestHelper.deployFarmingPool(deployer, address(brs), address(core), funds, shares);
        FarmingPool newImpl = new FarmingPool();

        vm.prank(alice);
        vm.expectRevert();
        farm.upgradeToAndCall(address(newImpl), "");
    }

    // ============ Test: Storage preserved across upgrade (mint BTD → upgrade → balance intact) ============

    function test_minter_storagePreservedAcrossUpgrade() public {
        // Deploy full system
        MockWBTC wbtc = new MockWBTC(deployer);
        MockUSDC usdc = new MockUSDC(deployer);
        BTD btd = new BTD(deployer);
        BTB btb = new BTB(deployer);
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
        btd = new BTD(deployer);
        BTB btb = new BTB(deployer);
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
