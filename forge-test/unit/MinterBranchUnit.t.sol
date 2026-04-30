// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../contracts/BRS.sol";
import "../../contracts/BTB.sol";
import "../../contracts/BTD.sol";
import "../../contracts/ConfigCore.sol";
import "../../contracts/ConfigGov.sol";
import "../../contracts/Minter.sol";
import "../../contracts/Treasury.sol";
import "../../contracts/interfaces/IIdealUSDManager.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/local/MockPriceOracle.sol";
import "../../contracts/local/MockUSDC.sol";
import "../../contracts/local/MockUSDT.sol";
import "../../contracts/local/MockWBTC.sol";
import "../../contracts/local/MockWETH.sol";
import "../../contracts/stBTB.sol";
import "../../contracts/stBTD.sol";
import "../helpers/ProxyTestHelper.sol";

contract BranchIUSDManager is IIdealUSDManager {
    uint256 public price = 1e18;
    uint256 public updatedAt = block.timestamp;
    bool public updateResult;
    bool public shouldRevert;

    function setUpdateResult(bool value) external {
        updateResult = value;
    }

    function setShouldRevert(bool value) external {
        shouldRevert = value;
    }

    function getCurrentIUSD() external view returns (uint256) {
        return price;
    }

    function lastUpdateTime() external view returns (uint256) {
        return updatedAt;
    }

    function tryUpdateIUSD() external returns (bool updated) {
        if (shouldRevert) {
            revert("iusd update failed");
        }
        updatedAt = block.timestamp;
        return updateResult;
    }
}

contract MinterBranchUnitTest is Test {
    event IUSDUpdateAttempted(bool updated);

    address public owner = address(this);
    address public user = vm.addr(0xC0FFEE);
    address public interestPool = address(0x1111);
    address public farmingPool = address(0x2222);

    MockWBTC public wbtc;
    MockUSDC public usdc;
    MockUSDT public usdt;
    MockWETH public weth;
    BTD public btd;
    BTB public btb;
    BRS public brs;
    stBTD public stbtd;
    stBTB public stbtb;
    ConfigCore public core;
    ConfigGov public gov;
    MockPriceOracle public priceOracle;
    BranchIUSDManager public iusdManager;
    Treasury public treasury;
    Minter public minter;

    function setUp() public {
        _deploySystem();
        wbtc.transfer(user, 20e8);
    }

    function test_mintBTD_zeroFeeSkipsFeeMintAndReusesTreasuryAllowance() public {
        gov.setParam(ConfigGov.ParamType.MintFeeBp, 0);

        vm.startPrank(user);
        wbtc.approve(address(minter), 2e8);
        minter.mintBTD(1e8);
        uint256 allowanceAfterFirst = wbtc.allowance(address(minter), address(treasury));
        minter.mintBTD(1e8);
        vm.stopPrank();

        assertEq(btd.balanceOf(address(treasury)), 0, "zero mint fee should skip treasury fee mint");
        assertEq(
            wbtc.allowance(address(minter), address(treasury)),
            allowanceAfterFirst,
            "max treasury allowance should be reused without being decremented"
        );
    }

    function test_mintBTD_coversIUSDUpdateTrueFalseAndCatchBranches() public {
        gov.setParam(ConfigGov.ParamType.MintFeeBp, 0);

        vm.startPrank(user);
        wbtc.approve(address(minter), 3e8);

        iusdManager.setUpdateResult(true);
        vm.expectEmit(false, false, false, true);
        emit IUSDUpdateAttempted(true);
        minter.mintBTD(1e8);

        iusdManager.setUpdateResult(false);
        vm.expectEmit(false, false, false, true);
        emit IUSDUpdateAttempted(false);
        minter.mintBTD(1e8);

        iusdManager.setShouldRevert(true);
        vm.expectEmit(false, false, false, true);
        emit IUSDUpdateAttempted(false);
        minter.mintBTD(1e8);

        vm.stopPrank();
    }

    function test_mintBTD_revertsWhenPriceOracleNotSet() public {
        ConfigCore unsetCore = _deployCore();
        Minter isolatedMinter = ProxyTestHelper.deployMinter(owner, address(unsetCore), address(gov));

        vm.startPrank(user);
        wbtc.approve(address(isolatedMinter), 1e8);
        vm.expectRevert("PriceOracle not set");
        isolatedMinter.mintBTD(1e8);
        vm.stopPrank();
    }

    function test_redeemBTD_zeroFeeReturnsOnlyCollateralAndSkipsCompensation() public {
        gov.setParam(ConfigGov.ParamType.MintFeeBp, 0);
        gov.setParam(ConfigGov.ParamType.RedeemFeeBp, 0);

        _mintBTDFromUser(1e8);
        uint256 btdToRedeem = 10_000e18;
        uint256 userWbtcBefore = wbtc.balanceOf(user);

        vm.startPrank(user);
        btd.approve(address(minter), btdToRedeem);
        minter.redeemBTD(btdToRedeem);
        vm.stopPrank();

        assertGt(wbtc.balanceOf(user), userWbtcBefore, "redeem should return BTC collateral");
        assertEq(btb.balanceOf(user), 0, "healthy redeem should not mint BTB");
        assertEq(brs.balanceOf(user), 0, "healthy redeem should not compensate BRS");
        assertEq(btd.balanceOf(address(treasury)), 0, "zero redeem fee should skip treasury fee mint");
    }

    function test_redeemBTD_underCollateralizedMintsBTBWhenBTBHealthy() public {
        gov.setParam(ConfigGov.ParamType.MintFeeBp, 0);
        gov.setParam(ConfigGov.ParamType.RedeemFeeBp, 0);
        _mintBTDFromUser(1e8);
        priceOracle.setWBTCPrice(25_000e18);
        priceOracle.setBTBPrice(1e18);

        vm.startPrank(user);
        btd.approve(address(minter), 10_000e18);
        minter.redeemBTD(10_000e18);
        vm.stopPrank();

        assertGt(btb.balanceOf(user), 0, "undercollateralized redeem should mint BTB");
        assertEq(brs.balanceOf(user), 0, "healthy BTB price should not trigger BRS compensation");
    }

    function test_redeemBTD_underCollateralizedCompensatesBRSWhenBTBBelowMin() public {
        gov.setParam(ConfigGov.ParamType.MintFeeBp, 0);
        gov.setParam(ConfigGov.ParamType.RedeemFeeBp, 0);
        _mintBTDFromUser(1e8);
        priceOracle.setWBTCPrice(25_000e18);
        priceOracle.setBTBPrice(25e16);
        priceOracle.setBRSPrice(10e18);
        brs.transfer(address(treasury), 1_000e18);

        vm.startPrank(user);
        btd.approve(address(minter), 10_000e18);
        minter.redeemBTD(10_000e18);
        vm.stopPrank();

        assertGt(btb.balanceOf(user), 0, "BTB floor branch should mint BTB");
        assertGt(brs.balanceOf(user), 0, "BTB below floor should trigger BRS compensation");
    }

    function test_redeemBTD_revertsInvalidSecondaryAndBRSPrices() public {
        gov.setParam(ConfigGov.ParamType.MintFeeBp, 0);
        gov.setParam(ConfigGov.ParamType.RedeemFeeBp, 0);
        _mintBTDFromUser(1e8);
        priceOracle.setWBTCPrice(25_000e18);

        vm.startPrank(user);
        btd.approve(address(minter), 20_000e18);

        priceOracle.setBTBPrice(0);
        vm.expectRevert("Invalid secondary price");
        minter.redeemBTD(10_000e18);

        priceOracle.setBTBPrice(25e16);
        priceOracle.setBRSPrice(0);
        vm.expectRevert("Invalid BRS price");
        minter.redeemBTD(10_000e18);

        vm.stopPrank();
    }

    function test_redeemBTB_revertsWhenCRBelow100() public {
        wbtc.transfer(address(treasury), 1e5);
        btd.mint(address(0xD00D), 1_000e18);
        btb.mint(user, 1_000e18);

        vm.startPrank(user);
        btb.approve(address(minter), 1_000e18);
        vm.expectRevert("CR<100%, BTB not redeemable");
        minter.redeemBTB(1_000e18);
        vm.stopPrank();
    }

    function test_redeemBTB_revertsWhenAmountExceedsMaxRedeemable() public {
        _seedSurplusForBTBRedeem();
        btb.mint(user, 2_000e18);

        vm.startPrank(user);
        btb.approve(address(minter), 2_000e18);
        vm.expectRevert("Exceeds max redeemable");
        minter.redeemBTB(2_000e18);
        vm.stopPrank();
    }

    function test_redeemBTB_successWithinMaxRedeemable() public {
        _seedSurplusForBTBRedeem();
        btb.mint(user, 500e18);

        vm.startPrank(user);
        btb.approve(address(minter), 500e18);
        minter.redeemBTB(500e18);
        vm.stopPrank();

        assertEq(btb.balanceOf(user), 0, "BTB should be burned");
        assertEq(btd.balanceOf(user), 500e18, "BTD should be minted one for one");
    }

    function _deploySystem() internal {
        wbtc = new MockWBTC(owner);
        usdc = new MockUSDC(owner);
        usdt = new MockUSDT(owner);
        weth = new MockWETH(owner);
        btd = ProxyTestHelper.deployBTD(owner);
        btb = ProxyTestHelper.deployBTB(owner);
        brs = new BRS(owner);
        stbtd = ProxyTestHelper.deployStBTD(IERC20(address(btd)), owner);
        stbtb = ProxyTestHelper.deployStBTB(IERC20(address(btb)), owner);
        core = _deployCore();
        gov = ProxyTestHelper.deployConfigGov(owner);
        priceOracle = new MockPriceOracle();
        iusdManager = new BranchIUSDManager();
        treasury = ProxyTestHelper.deployTreasury(owner, address(core), address(0xCAFE));
        minter = ProxyTestHelper.deployMinter(owner, address(core), address(gov));

        core.setCoreContracts(
            address(treasury), address(minter), address(priceOracle), address(iusdManager), interestPool, farmingPool
        );

        btd.grantRole(btd.MINTER_ROLE(), address(minter));
        btb.grantRole(btb.MINTER_ROLE(), address(minter));
        btd.grantRole(btd.MINTER_ROLE(), owner);
        btb.grantRole(btb.MINTER_ROLE(), owner);
    }

    function _deployCore() internal returns (ConfigCore) {
        return new ConfigCore(
            address(wbtc),
            address(btd),
            address(btb),
            address(brs),
            address(weth),
            address(usdc),
            address(usdt),
            address(0x1001),
            address(0x1002),
            address(0x1003),
            address(0x1004),
            address(stbtd),
            address(stbtb)
        );
    }

    function _mintBTDFromUser(uint256 wbtcAmount) internal {
        vm.startPrank(user);
        wbtc.approve(address(minter), wbtcAmount);
        minter.mintBTD(wbtcAmount);
        vm.stopPrank();
    }

    function _seedSurplusForBTBRedeem() internal {
        wbtc.transfer(address(treasury), 1e8);
        btd.mint(address(0xD00D), 49_000e18);
        priceOracle.setWBTCPrice(50_000e18);
        priceOracle.setIUSDPrice(1e18);
    }
}
