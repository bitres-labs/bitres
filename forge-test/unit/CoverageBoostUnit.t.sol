// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../contracts/BRS.sol";
import "../../contracts/BTB.sol";
import "../../contracts/BTD.sol";
import "../../contracts/ConfigCore.sol";
import "../../contracts/ConfigGov.sol";
import "../../contracts/FarmingPool.sol";
import "../../contracts/IdealUSDManager.sol";
import "../../contracts/PriceOracle.sol";
import "../../contracts/Treasury.sol";
import "../../contracts/UniswapV2TWAPOracle.sol";
import "../../contracts/interfaces/IFarmingPool.sol";
import "../../contracts/local/MockAggregatorV3.sol";
import "../../contracts/local/MockUSDC.sol";
import "../../contracts/local/MockUSDT.sol";
import "../../contracts/local/MockWBTC.sol";
import "../../contracts/local/MockWETH.sol";
import "../../contracts/local/UniswapV2Pair.sol";
import "../../contracts/stBTB.sol";
import "../../contracts/stBTD.sol";
import "../helpers/ProxyTestHelper.sol";

/// @title CoverageBoostUnit
/// @notice Exercises public aliases, validation branches, and view helpers that
///         are easy to miss in end-to-end tests but useful for audit coverage.
contract CoverageBoostUnitTest is Test {
    address public deployer = address(this);
    address public alice = vm.addr(0xA11CE);
    address public bob = address(0xB0B);
    address public mockRouter = address(0xDEAD);

    function test_brsNoncesAndVotingUpdatePaths() public {
        BRS brs = new BRS(deployer);

        assertEq(brs.nonces(deployer), 0, "initial nonce");

        brs.transfer(alice, 100e18);
        brs.delegate(deployer);

        vm.prank(alice);
        brs.delegate(alice);

        assertEq(brs.getVotes(alice), 100e18, "delegated votes");
    }

    function test_tokenProxyInitializationRejectsZeroAdmin() public {
        BTD btdImpl = new BTD();
        vm.expectRevert("BTD: zero admin");
        new ERC1967Proxy(address(btdImpl), abi.encodeCall(BTD.initialize, (address(0))));

        BTB btbImpl = new BTB();
        vm.expectRevert("BTB: zero admin");
        new ERC1967Proxy(address(btbImpl), abi.encodeCall(BTB.initialize, (address(0))));
    }

    function test_configGovAddressBatchAndValidationBranches() public {
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);

        ConfigGov.AddressParamType[] memory addrTypes = new ConfigGov.AddressParamType[](3);
        addrTypes[0] = ConfigGov.AddressParamType.PceFeed;
        addrTypes[1] = ConfigGov.AddressParamType.PythWbtc;
        addrTypes[2] = ConfigGov.AddressParamType.ChainlinkUsdtUsd;
        address[] memory addrs = new address[](3);
        addrs[0] = address(0x101);
        addrs[1] = address(0x102);
        addrs[2] = address(0x103);

        gov.setAddressParamsBatch(addrTypes, addrs);
        assertEq(gov.pceFeed(), address(0x101));
        assertEq(gov.pythWbtc(), address(0x102));
        assertEq(gov.chainlinkUsdtUsd(), address(0x103));

        address[] memory shortAddrs = new address[](2);
        vm.expectRevert("ConfigGov: length mismatch");
        gov.setAddressParamsBatch(addrTypes, shortAddrs);

        addrs[1] = address(0);
        vm.expectRevert("ConfigGov: zero address");
        gov.setAddressParamsBatch(addrTypes, addrs);

        vm.expectRevert("ConfigGov: zero governor");
        gov.setGovernor(address(0));

        _expectParamRevert(gov, ConfigGov.ParamType.MintFeeBp, 1001, "ConfigGov: mint fee too high");
        _expectParamRevert(gov, ConfigGov.ParamType.InterestFeeBp, 2001, "ConfigGov: interest fee too high");
        _expectParamRevert(gov, ConfigGov.ParamType.RedeemFeeBp, 1001, "ConfigGov: redeem fee too high");
        _expectParamRevert(gov, ConfigGov.ParamType.MinBtbPrice, 1e17 - 1, "ConfigGov: min BTB price too low");
        _expectParamRevert(gov, ConfigGov.ParamType.MinBtbPrice, 1e18 + 1, "ConfigGov: min BTB price too high");
        _expectParamRevert(gov, ConfigGov.ParamType.MaxBtbRate, 99, "ConfigGov: max BTB rate too low");
        _expectParamRevert(gov, ConfigGov.ParamType.MaxBtbRate, 3001, "ConfigGov: max BTB rate too high");
        _expectParamRevert(gov, ConfigGov.ParamType.MaxBtdRate, 99, "ConfigGov: max BTD rate too low");
        _expectParamRevert(gov, ConfigGov.ParamType.MaxBtdRate, 3001, "ConfigGov: max BTD rate too high");
        _expectParamRevert(gov, ConfigGov.ParamType.PceMaxDeviation, 1e15 - 1, "ConfigGov: PCE deviation too low");
        _expectParamRevert(gov, ConfigGov.ParamType.PceMaxDeviation, 1e17 + 1, "ConfigGov: PCE deviation too high");
        _expectParamRevert(gov, ConfigGov.ParamType.BaseRateDefault, 99, "ConfigGov: base rate too low");
        _expectParamRevert(gov, ConfigGov.ParamType.BaseRateDefault, 1001, "ConfigGov: base rate too high");
    }

    function test_configCoreRenounceBeforeCoreContractsReverts() public {
        SystemParts memory parts = _deployParts();
        ConfigCore core = _deployCore(parts, address(0x6001), address(0x6002), address(0x6003), address(0x6004));

        vm.expectRevert("ConfigCore: core contracts not set");
        core.renounceOwnership();
    }

    function test_idealUSDManagerLazyUpdateHistoryAndFormatting() public {
        vm.warp(1_000_000);
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        MockAggregatorV3 pce = new MockAggregatorV3(300_00_000_000);
        gov.setAddressParam(ConfigGov.AddressParamType.PceFeed, address(pce));
        IdealUSDManager mgr = ProxyTestHelper.deployIdealUSDManager(deployer, address(gov), 1e18);

        assertEq(mgr.getUpdateHistoryLength(), 0, "initial history");
        vm.expectRevert("No updates yet");
        mgr.getLatestUpdate();
        assertGt(bytes(mgr.getFormattedInfo()).length, 0, "formatted info");

        vm.expectRevert("Only internal call");
        mgr.updateIUSDInternal();

        vm.warp(block.timestamp + 26 days);
        assertTrue(mgr.tryUpdateIUSD(), "lazy update should execute");
        assertFalse(mgr.tryUpdateIUSD(), "second lazy update should be skipped");
        assertEq(mgr.getUpdateHistoryLength(), 1, "history length");
        assertEq(mgr.getLatestUpdate().timestamp, block.timestamp, "latest timestamp");
        assertGt(mgr.lastPCEValue(), 0, "pce value");
    }

    function test_farmingPoolAdminViewsFundingAndLPValidation() public {
        SystemParts memory parts = _deployParts();
        ConfigCore core = _deployCore(parts, address(0x6001), address(0x6002), address(0x6003), address(0x6004));

        address[] memory funds = new address[](3);
        funds[0] = address(0xF001);
        funds[1] = address(0);
        funds[2] = address(0xF003);
        uint256[] memory shares = new uint256[](3);
        shares[0] = 10;
        shares[1] = 0;
        shares[2] = 5;
        FarmingPool farm = ProxyTestHelper.deployFarmingPool(deployer, address(parts.brs), address(core), funds, shares);

        assertEq(farm.brs(), address(parts.brs), "brs helper");
        parts.brs.approve(address(farm), 100_000e18);
        farm.fundRewards(100_000e18);

        vm.expectRevert("FarmingPool: amount zero");
        farm.fundRewards(0);

        vm.expectRevert("FarmingPool: length mismatch");
        farm.setFunds(funds, new uint256[](2));

        uint256[] memory invalidShares = new uint256[](3);
        invalidShares[0] = 60;
        invalidShares[1] = 30;
        invalidShares[2] = 20;
        vm.expectRevert("FarmingPool: shares exceed 100%");
        farm.setFunds(funds, invalidShares);

        farm.setFunds(funds, shares);
        farm.addPool(IERC20(address(parts.btd)), 100, IFarmingPool.PoolKind.Single, true);
        assertEq(uint8(farm.poolKind(0)), uint8(IFarmingPool.PoolKind.Single));
        assertGt(farm.currentRewardPerSecond(), 0, "reward rate");

        IERC20[] memory tokens = new IERC20[](2);
        tokens[0] = IERC20(address(parts.usdc));
        tokens[1] = IERC20(address(parts.weth));
        uint256[] memory allocs = new uint256[](2);
        allocs[0] = 200;
        allocs[1] = 50;
        IFarmingPool.PoolKind[] memory kinds = new IFarmingPool.PoolKind[](2);
        kinds[0] = IFarmingPool.PoolKind.Single;
        kinds[1] = IFarmingPool.PoolKind.Single;
        farm.addPools(tokens, allocs, kinds);

        IERC20[] memory mismatchedTokens = new IERC20[](1);
        vm.expectRevert("FarmingPool: length mismatch");
        farm.addPools(mismatchedTokens, allocs, kinds);

        IFarmingPool.PoolKind[] memory mismatchedKinds = new IFarmingPool.PoolKind[](1);
        vm.expectRevert("FarmingPool: kind mismatch");
        farm.addPools(tokens, allocs, mismatchedKinds);

        parts.btd.mint(alice, 20e18);
        vm.startPrank(alice);
        parts.btd.approve(address(farm), 20e18);
        farm.deposit(0, 20e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        farm.setPool(0, 150, true);
        farm.massUpdatePools();

        UniswapV2Pair lp = _deployPair(address(parts.wbtc), address(parts.usdc));
        _seedPair(lp, address(parts.wbtc), 2e8, address(parts.usdc), 200_000e6);
        farm.addPool(IERC20(address(lp)), 300, IFarmingPool.PoolKind.LP);
        uint256 lpAmount = lp.balanceOf(deployer) / 2;
        lp.approve(address(farm), lpAmount);
        farm.deposit(3, lpAmount);
    }

    function test_priceOracleTWAPUpdateEntrypoints() public {
        SystemParts memory parts = _deployParts();
        UniswapV2Pair poolWbtcUsdc = _deployPair(address(parts.wbtc), address(parts.usdc));
        UniswapV2Pair poolBtdUsdc = _deployPair(address(parts.btd), address(parts.usdc));
        UniswapV2Pair poolBtbBtd = _deployPair(address(parts.btb), address(parts.btd));
        UniswapV2Pair poolBrsBtd = _deployPair(address(parts.brs), address(parts.btd));

        _seedPair(poolWbtcUsdc, address(parts.wbtc), 2e8, address(parts.usdc), 200_000e6);
        _seedPair(poolBtdUsdc, address(parts.btd), 100_000e18, address(parts.usdc), 100_000e6);
        _seedPair(poolBtbBtd, address(parts.btb), 20_000e18, address(parts.btd), 20_000e18);
        _seedPair(poolBrsBtd, address(parts.brs), 100_000e18, address(parts.btd), 10_000e18);

        ConfigCore core =
            _deployCore(parts, address(poolWbtcUsdc), address(poolBtdUsdc), address(poolBtbBtd), address(poolBrsBtd));
        ConfigGov gov = ProxyTestHelper.deployConfigGov(deployer);
        UniswapV2TWAPOracle twap = ProxyTestHelper.deployTWAPOracle(deployer);
        PriceOracle oracle = ProxyTestHelper.deployPriceOracle(deployer, address(core), address(gov), address(twap));

        oracle.updateTWAPForWBTC();
        oracle.updateTWAPForBTCCollateral();
        oracle.updateTWAPForBTD();
        oracle.updateTWAPForBTB();
        oracle.updateTWAPForBRS();
        oracle.updateTWAPAll();
    }

    function _expectParamRevert(ConfigGov gov, ConfigGov.ParamType paramType, uint256 value, string memory reason)
        internal
    {
        vm.expectRevert(bytes(reason));
        gov.setParam(paramType, value);
    }

    struct SystemParts {
        MockWBTC wbtc;
        MockUSDC usdc;
        MockUSDT usdt;
        MockWETH weth;
        BTD btd;
        BTB btb;
        BRS brs;
        stBTD stbtd;
        stBTB stbtb;
    }

    function _deployParts() internal returns (SystemParts memory parts) {
        parts.wbtc = new MockWBTC(deployer);
        parts.usdc = new MockUSDC(deployer);
        parts.usdt = new MockUSDT(deployer);
        parts.weth = new MockWETH(deployer);
        parts.btd = ProxyTestHelper.deployBTD(deployer);
        parts.btb = ProxyTestHelper.deployBTB(deployer);
        parts.brs = new BRS(deployer);
        parts.btd.grantRole(parts.btd.MINTER_ROLE(), deployer);
        parts.btb.grantRole(parts.btb.MINTER_ROLE(), deployer);
        parts.btd.mint(deployer, 1_000_000e18);
        parts.btb.mint(deployer, 1_000_000e18);
        parts.stbtd = ProxyTestHelper.deployStBTD(IERC20(address(parts.btd)), deployer);
        parts.stbtb = ProxyTestHelper.deployStBTB(IERC20(address(parts.btb)), deployer);
    }

    function _deployCore(
        SystemParts memory parts,
        address poolWbtcUsdc,
        address poolBtdUsdc,
        address poolBtbBtd,
        address poolBrsBtd
    ) internal returns (ConfigCore) {
        return new ConfigCore(
            address(parts.wbtc),
            address(parts.btd),
            address(parts.btb),
            address(parts.brs),
            address(parts.weth),
            address(parts.usdc),
            address(parts.usdt),
            poolWbtcUsdc,
            poolBtdUsdc,
            poolBtbBtd,
            poolBrsBtd,
            address(parts.stbtd),
            address(parts.stbtb)
        );
    }

    function _deployPair(address tokenA, address tokenB) internal returns (UniswapV2Pair pair) {
        pair = new UniswapV2Pair();
        pair.initialize(tokenA, tokenB);
    }

    function _seedPair(UniswapV2Pair pair, address tokenA, uint256 amountA, address tokenB, uint256 amountB) internal {
        if (pair.token0() == tokenA) {
            IERC20(tokenA).transfer(address(pair), amountA);
            IERC20(tokenB).transfer(address(pair), amountB);
        } else {
            IERC20(tokenB).transfer(address(pair), amountB);
            IERC20(tokenA).transfer(address(pair), amountA);
        }
        pair.mint(deployer);
    }
}
