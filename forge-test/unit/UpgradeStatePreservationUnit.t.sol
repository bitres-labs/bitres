// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../contracts/BTB.sol";
import "../../contracts/BTD.sol";
import "../../contracts/BRS.sol";
import "../../contracts/ConfigCore.sol";
import "../../contracts/ConfigGov.sol";
import "../../contracts/FarmingPool.sol";
import "../../contracts/IdealUSDManager.sol";
import "../../contracts/InterestPool.sol";
import "../../contracts/Minter.sol";
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

/// @title Upgrade State Preservation Tests
/// @notice Exercises a live multi-module state, upgrades all UUPS modules, and
///         verifies proxy addresses, user balances, staking, and mining state.
contract UpgradeStatePreservationUnitTest is Test {
    bytes32 internal constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    address public deployer = address(this);
    address public alice = address(0xA11CE);
    address public bob = address(0xB0B);
    address public foundation = address(0xF0071DA);
    address public team = address(0x7EA3);
    address public rateOracle = address(0xA7E0);
    address public mockRouter = address(0xDEAD);
    address public governor = address(0xBEEF);

    MockWBTC public wbtc;
    MockUSDC public usdc;
    MockUSDT public usdt;
    MockWETH public weth;
    MockAggregatorV3 public pceFeed;

    BTD public btd;
    BTB public btb;
    BRS public brs;
    stBTD public stbtd;
    stBTB public stbtb;

    UniswapV2Pair public poolWbtcUsdc;
    UniswapV2Pair public poolBtdUsdc;
    UniswapV2Pair public poolBtbBtd;
    UniswapV2Pair public poolBrsBtd;

    ConfigCore public core;
    ConfigGov public gov;
    IdealUSDManager public iusdManager;
    UniswapV2TWAPOracle public twapOracle;
    PriceOracle public priceOracle;
    Treasury public treasury;
    Minter public minter;
    InterestPool public interestPool;
    FarmingPool public farmingPool;

    function setUp() public {
        vm.warp(1_000_000);
        _deploySystem();
        _seedSystemState();
    }

    function test_allUpgradeableModules_preserveAddressesBalancesStakingAndMiningAcrossUpgrade() public {
        address[12] memory proxyAddrsBefore = _proxyAddresses();
        address[12] memory implsBefore = _implementationAddresses();
        bytes32 tokenStateBefore = _tokenStateHash();
        bytes32 stakingStateBefore = _stakingStateHash();
        bytes32 farmingStateBefore = _farmingStateHash();
        bytes32 configStateBefore = _configStateHash();

        _upgradeAllUpgradeableModules();

        _assertProxyAddressesPreserved(proxyAddrsBefore);
        _assertImplementationsChanged(implsBefore);
        assertEq(_tokenStateHash(), tokenStateBefore, "token balances/supplies changed");
        assertEq(_stakingStateHash(), stakingStateBefore, "staking state changed");
        assertEq(_farmingStateHash(), farmingStateBefore, "farming state changed");
        assertEq(_configStateHash(), configStateBefore, "config/module state changed");

        _assertPostUpgradeOperationsStillWork();
    }

    function test_upgradeabilityScope_coreAndBRSRemainFixedByDesign() public view {
        assertEq(_implementationOf(address(core)), address(0), "ConfigCore is not an ERC1967 proxy");
        assertEq(_implementationOf(address(brs)), address(0), "BRS is not an ERC1967 proxy");

        address[12] memory impls = _implementationAddresses();
        for (uint256 i = 0; i < impls.length; i++) {
            assertTrue(impls[i] != address(0), "upgradeable module missing implementation");
        }
    }

    function _deploySystem() internal {
        wbtc = new MockWBTC(deployer);
        usdc = new MockUSDC(deployer);
        usdt = new MockUSDT(deployer);
        weth = new MockWETH(deployer);

        btd = ProxyTestHelper.deployBTD(deployer);
        btb = ProxyTestHelper.deployBTB(deployer);
        brs = new BRS(deployer);
        stbtd = ProxyTestHelper.deployStBTD(IERC20(address(btd)), deployer);
        stbtb = ProxyTestHelper.deployStBTB(IERC20(address(btb)), deployer);

        btd.grantRole(btd.MINTER_ROLE(), deployer);
        btb.grantRole(btb.MINTER_ROLE(), deployer);

        poolWbtcUsdc = _deployPair(address(wbtc), address(usdc));
        poolBtdUsdc = _deployPair(address(btd), address(usdc));
        poolBtbBtd = _deployPair(address(btb), address(btd));
        poolBrsBtd = _deployPair(address(brs), address(btd));
        _seedTwapLiquidity();

        core = new ConfigCore(
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

        gov = ProxyTestHelper.deployConfigGov(deployer);
        pceFeed = new MockAggregatorV3(300_00_000_000);
        gov.setAddressParam(ConfigGov.AddressParamType.PceFeed, address(pceFeed));

        iusdManager = ProxyTestHelper.deployIdealUSDManager(deployer, address(gov), 1e18);
        twapOracle = ProxyTestHelper.deployTWAPOracle(deployer);
        priceOracle = ProxyTestHelper.deployPriceOracle(deployer, address(core), address(gov), address(twapOracle));
        treasury = ProxyTestHelper.deployTreasury(deployer, address(core), mockRouter);
        minter = ProxyTestHelper.deployMinter(deployer, address(core), address(gov));
        interestPool = ProxyTestHelper.deployInterestPool(deployer, address(core), address(gov), rateOracle);

        address[] memory funds = new address[](3);
        funds[0] = address(treasury);
        funds[1] = foundation;
        funds[2] = team;
        uint256[] memory shares = new uint256[](3);
        shares[0] = 15;
        shares[1] = 10;
        shares[2] = 5;
        farmingPool = ProxyTestHelper.deployFarmingPool(deployer, address(brs), address(core), funds, shares);

        core.setCoreContracts(
            address(treasury),
            address(minter),
            address(priceOracle),
            address(iusdManager),
            address(interestPool),
            address(farmingPool)
        );

        btd.grantRole(btd.MINTER_ROLE(), address(minter));
        btd.grantRole(btd.MINTER_ROLE(), address(interestPool));
        btb.grantRole(btb.MINTER_ROLE(), address(minter));
        btb.grantRole(btb.MINTER_ROLE(), address(interestPool));

        interestPool.initializePools();
        stbtd.setInterestPool(address(interestPool));
        stbtb.setInterestPool(address(interestPool));
    }

    function _seedSystemState() internal {
        gov.setParam(ConfigGov.ParamType.MintFeeBp, 75);
        gov.setParam(ConfigGov.ParamType.RedeemFeeBp, 80);
        gov.setParam(ConfigGov.ParamType.BaseRateDefault, 650);
        gov.setGovernor(governor);

        iusdManager.setUpdaterWhitelistEnabled(true);
        iusdManager.setUpdaterAuthorization(alice, true);
        iusdManager.setIUSDValue(1.01e18, "manual override for upgrade preservation");

        twapOracle.updateIfNeeded(address(poolWbtcUsdc));
        priceOracle.setUseTWAP(false);
        priceOracle.setMaxDeviationBps(75);

        treasury.setBuybackParams(11_000e18, 60_000e18, 36 hours, 25, 250);
        treasury.setEthReserveParams(1 ether, 0.7 ether);

        btd.mint(alice, 1_000e18);
        btd.mint(bob, 1_000e18);
        btb.mint(alice, 500e18);
        btb.mint(bob, 500e18);
        btd.mint(address(treasury), 250e18);
        btb.mint(address(treasury), 125e18);
        brs.transfer(address(treasury), 1_000e18);
        brs.transfer(address(farmingPool), 10_000_000e18);
        wbtc.transfer(alice, 10e8);
        wbtc.transfer(bob, 20e8);
        usdc.transfer(alice, 1_000_000e6);
        usdc.transfer(bob, 1_000_000e6);

        farmingPool.addPool(IERC20(address(btd)), 100, IFarmingPool.PoolKind.Single);
        farmingPool.addPool(IERC20(address(usdc)), 200, IFarmingPool.PoolKind.Single);

        vm.startPrank(alice);
        btd.approve(address(stbtd), 200e18);
        stbtd.deposit(200e18, alice);
        btb.approve(address(stbtb), 80e18);
        stbtb.deposit(80e18, alice);
        btd.approve(address(farmingPool), 60e18);
        farmingPool.deposit(0, 60e18);
        usdc.approve(address(farmingPool), 20_000e6);
        farmingPool.deposit(1, 20_000e6);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days);
        farmingPool.updatePool(0);
        farmingPool.updatePool(1);

        vm.startPrank(bob);
        btd.approve(address(interestPool), 120e18);
        interestPool.stakeBTD(120e18);
        btb.approve(address(interestPool), 70e18);
        interestPool.stakeBTB(70e18);
        btd.approve(address(farmingPool), 40e18);
        farmingPool.deposit(0, 40e18);
        usdc.approve(address(farmingPool), 30_000e6);
        farmingPool.deposit(1, 30_000e6);
        vm.stopPrank();
    }

    function _assertPostUpgradeOperationsStillWork() internal {
        vm.startPrank(alice);
        btd.approve(address(farmingPool), 1e18);
        farmingPool.deposit(0, 1e18);
        vm.stopPrank();

        vm.startPrank(bob);
        interestPool.unstakeBTD(1e18);
        vm.stopPrank();
    }

    function _upgradeAllUpgradeableModules() internal {
        _upgradeProxy(address(btd), address(new BTD()));
        _upgradeProxy(address(btb), address(new BTB()));
        _upgradeProxy(address(stbtd), address(new stBTD()));
        _upgradeProxy(address(stbtb), address(new stBTB()));
        _upgradeProxy(address(gov), address(new ConfigGov()));
        _upgradeProxy(address(iusdManager), address(new IdealUSDManager()));
        _upgradeProxy(address(twapOracle), address(new UniswapV2TWAPOracle()));
        _upgradeProxy(address(priceOracle), address(new PriceOracle()));
        _upgradeProxy(address(treasury), address(new Treasury()));
        _upgradeProxy(address(minter), address(new Minter()));
        _upgradeProxy(address(interestPool), address(new InterestPool()));
        _upgradeProxy(address(farmingPool), address(new FarmingPool()));
    }

    function _upgradeProxy(address proxy, address newImplementation) internal {
        address oldImplementation = _implementationOf(proxy);
        assertTrue(oldImplementation != address(0), "proxy missing implementation before upgrade");

        (bool ok,) = proxy.call(abi.encodeWithSignature("upgradeToAndCall(address,bytes)", newImplementation, ""));
        assertTrue(ok, "upgradeToAndCall failed");
        assertEq(_implementationOf(proxy), newImplementation, "implementation slot not updated");
    }

    function _proxyAddresses() internal view returns (address[12] memory proxies) {
        proxies[0] = address(btd);
        proxies[1] = address(btb);
        proxies[2] = address(stbtd);
        proxies[3] = address(stbtb);
        proxies[4] = address(gov);
        proxies[5] = address(iusdManager);
        proxies[6] = address(twapOracle);
        proxies[7] = address(priceOracle);
        proxies[8] = address(treasury);
        proxies[9] = address(minter);
        proxies[10] = address(interestPool);
        proxies[11] = address(farmingPool);
    }

    function _implementationAddresses() internal view returns (address[12] memory impls) {
        address[12] memory proxies = _proxyAddresses();
        for (uint256 i = 0; i < proxies.length; i++) {
            impls[i] = _implementationOf(proxies[i]);
        }
    }

    function _assertProxyAddressesPreserved(address[12] memory beforeAddrs) internal view {
        address[12] memory afterAddrs = _proxyAddresses();
        for (uint256 i = 0; i < afterAddrs.length; i++) {
            assertEq(afterAddrs[i], beforeAddrs[i], "proxy address changed");
        }
    }

    function _assertImplementationsChanged(address[12] memory beforeImpls) internal view {
        address[12] memory afterImpls = _implementationAddresses();
        for (uint256 i = 0; i < afterImpls.length; i++) {
            assertTrue(afterImpls[i] != address(0), "implementation missing after upgrade");
            assertTrue(afterImpls[i] != beforeImpls[i], "implementation did not change");
        }
    }

    function _tokenStateHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                _accountTokenHash(alice),
                _accountTokenHash(bob),
                _accountTokenHash(address(treasury)),
                _accountTokenHash(address(interestPool)),
                _accountTokenHash(address(farmingPool)),
                _accountTokenHash(address(stbtd)),
                _accountTokenHash(address(stbtb)),
                btd.totalSupply(),
                btb.totalSupply(),
                brs.totalSupply()
            )
        );
    }

    function _accountTokenHash(address account) internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                btd.balanceOf(account),
                btb.balanceOf(account),
                brs.balanceOf(account),
                wbtc.balanceOf(account),
                usdc.balanceOf(account),
                usdt.balanceOf(account),
                weth.balanceOf(account),
                stbtd.balanceOf(account),
                stbtb.balanceOf(account)
            )
        );
    }

    function _stakingStateHash() internal view returns (bytes32) {
        return keccak256(abi.encode(_vaultStateHash(), _interestPoolStateHash(), _interestUserStateHash()));
    }

    function _vaultStateHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                stbtd.totalSupply(),
                stbtb.totalSupply(),
                stbtd.totalAssets(),
                stbtb.totalAssets(),
                stbtd.interestPool(),
                stbtb.interestPool()
            )
        );
    }

    function _interestPoolStateHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                interestPool.initialized(),
                address(interestPool.core()),
                address(interestPool.gov()),
                interestPool.rateOracle(),
                interestPool.totalStaked(address(btd)),
                interestPool.totalStaked(address(btb))
            )
        );
    }

    function _interestUserStateHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                interestPool.userStaked(address(btd), address(stbtd)),
                interestPool.userStaked(address(btb), address(stbtb)),
                interestPool.userStaked(address(btd), bob),
                interestPool.userStaked(address(btb), bob),
                interestPool.totalAssetsOf(address(btd), address(stbtd)),
                interestPool.totalAssetsOf(address(btb), address(stbtb)),
                interestPool.totalAssetsOf(address(btd), bob),
                interestPool.totalAssetsOf(address(btb), bob)
            )
        );
    }

    function _farmingStateHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                _farmingConfigHash(),
                _farmingPoolHash(0),
                _farmingPoolHash(1),
                _farmingUserHash(0, alice),
                _farmingUserHash(0, bob),
                _farmingUserHash(1, alice),
                _farmingUserHash(1, bob),
                _farmingPendingHash()
            )
        );
    }

    function _farmingConfigHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                address(farmingPool.rewardToken()),
                address(farmingPool.core()),
                farmingPool.startTime(),
                farmingPool.minted(),
                farmingPool.totalAllocPoint(),
                farmingPool.poolLength(),
                farmingPool.fundAddrs(0),
                farmingPool.fundAddrs(1),
                farmingPool.fundAddrs(2),
                farmingPool.fundShares(0),
                farmingPool.fundShares(1),
                farmingPool.fundShares(2)
            )
        );
    }

    function _farmingPendingHash() internal view returns (bytes32) {
        return keccak256(abi.encode(farmingPool.pendingReward(0, alice), farmingPool.pendingReward(1, alice)));
    }

    function _farmingPoolHash(uint256 pid) internal view returns (bytes32) {
        (
            IERC20 lpToken,
            uint256 allocPoint,
            uint256 lastRewardTime,
            uint256 accRewardPerShare,
            uint256 totalStaked,
            IFarmingPool.PoolKind kind
        ) = farmingPool.poolInfo(pid);

        return keccak256(abi.encode(address(lpToken), allocPoint, lastRewardTime, accRewardPerShare, totalStaked, kind));
    }

    function _farmingUserHash(uint256 pid, address account) internal view returns (bytes32) {
        (uint256 amount, uint256 rewardDebt) = farmingPool.userInfo(pid, account);
        return keccak256(abi.encode(amount, rewardDebt));
    }

    function _configStateHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                _govStateHash(),
                _iusdStateHash(),
                _priceOracleStateHash(),
                _twapStateHash(),
                _treasuryStateHash(),
                _minterStateHash()
            )
        );
    }

    function _govStateHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                gov.mintFeeBP(),
                gov.redeemFeeBP(),
                gov.baseRateDefault(),
                gov.governor(),
                gov.getAddressParam(ConfigGov.AddressParamType.PceFeed)
            )
        );
    }

    function _iusdStateHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                address(iusdManager.configGov()),
                iusdManager.getCurrentIUSD(),
                iusdManager.lastUpdateTime(),
                iusdManager.lastManualOverrideTime(),
                iusdManager.manualOverrideCount(),
                iusdManager.updaterWhitelistEnabled(),
                iusdManager.authorizedUpdaters(alice)
            )
        );
    }

    function _priceOracleStateHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                address(priceOracle.core()),
                address(priceOracle.gov()),
                priceOracle.useTWAP(),
                priceOracle.maxDeviationBps(),
                priceOracle.lastDeviationUpdate(),
                priceOracle.getTWAPOracle()
            )
        );
    }

    function _twapStateHash() internal view returns (bytes32) {
        (uint32 olderTimestamp, uint32 newerTimestamp, uint32 elapsed) =
            twapOracle.getObservationInfo(address(poolWbtcUsdc));
        return keccak256(abi.encode(olderTimestamp, newerTimestamp, elapsed));
    }

    function _treasuryStateHash() internal view returns (bytes32) {
        return keccak256(
            abi.encode(
                treasury.configCore(),
                treasury.router(),
                treasury.minBuybackAmount(),
                treasury.maxBuybackAmount(),
                treasury.buybackCooldown(),
                treasury.buybackProbability(),
                treasury.maxSlippageBps(),
                treasury.minEthReserve(),
                treasury.ethTopupAmount()
            )
        );
    }

    function _minterStateHash() internal view returns (bytes32) {
        return keccak256(abi.encode(minter.configCore(), minter.configGov()));
    }

    function _implementationOf(address proxy) internal view returns (address) {
        return address(uint160(uint256(vm.load(proxy, ERC1967_IMPLEMENTATION_SLOT))));
    }

    function _deployPair(address tokenA, address tokenB) internal returns (UniswapV2Pair pair) {
        pair = new UniswapV2Pair();
        pair.initialize(tokenA, tokenB);
    }

    function _seedTwapLiquidity() internal {
        btd.mint(deployer, 500_000e18);
        btb.mint(deployer, 250_000e18);

        _addLiquidity(poolWbtcUsdc, 2e8, 200_000e6);
        _addLiquidity(poolBtdUsdc, 100_000e18, 100_000e6);
        _addLiquidity(poolBtbBtd, 20_000e18, 20_000e18);
        _addLiquidity(poolBrsBtd, 100_000e18, 10_000e18);
    }

    function _addLiquidity(UniswapV2Pair pair, uint256 amount0, uint256 amount1) internal {
        IERC20(pair.token0()).transfer(address(pair), amount0);
        IERC20(pair.token1()).transfer(address(pair), amount1);
        pair.mint(deployer);
    }
}
