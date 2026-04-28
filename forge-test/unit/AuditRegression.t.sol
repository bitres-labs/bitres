// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BTD} from "../../contracts/BTD.sol";
import {BTB} from "../../contracts/BTB.sol";
import {ConfigCore} from "../../contracts/ConfigCore.sol";
import {ConfigGov} from "../../contracts/ConfigGov.sol";
import {InterestPool} from "../../contracts/InterestPool.sol";
import {stBTD} from "../../contracts/stBTD.sol";
import {stBTB} from "../../contracts/stBTB.sol";
import {CollateralMath} from "../../contracts/libraries/CollateralMath.sol";
import {Constants} from "../../contracts/libraries/Constants.sol";
import {ProxyTestHelper} from "../helpers/ProxyTestHelper.sol";

contract AuditRegressionTest is Test {
    bytes32 private constant MINTER_ROLE = keccak256("MINTER_ROLE");

    address private constant ALICE = address(0xA11CE);
    address private constant TREASURY = address(0xBEEF);

    BTD private btd;
    BTB private btb;
    stBTD private stbtd;
    stBTB private stbtb;
    ConfigCore private core;
    ConfigGov private gov;
    InterestPool private interestPool;

    function setUp() public {
        btd = ProxyTestHelper.deployBTD(address(this));
        btb = ProxyTestHelper.deployBTB(address(this));
        btd.grantRole(MINTER_ROLE, address(this));
        btb.grantRole(MINTER_ROLE, address(this));

        stbtd = ProxyTestHelper.deployStBTD(IERC20(address(btd)), address(this));
        stbtb = ProxyTestHelper.deployStBTB(IERC20(address(btb)), address(this));

        core = new ConfigCore(
            address(0x1001),
            address(btd),
            address(btb),
            address(0x1004),
            address(0x1005),
            address(0x1006),
            address(0x1007),
            address(0x2001),
            address(0x2002),
            address(0x2003),
            address(0x2004),
            address(stbtd),
            address(stbtb)
        );
        gov = ProxyTestHelper.deployConfigGov(address(this));
        interestPool = ProxyTestHelper.deployInterestPool(address(this), address(core), address(gov), address(this));
        interestPool.initializePools();
        stbtd.setInterestPool(address(interestPool));
        stbtb.setInterestPool(address(interestPool));

        core.setCoreContracts(
            TREASURY,
            address(0x3002),
            address(0x3003),
            address(0x3004),
            address(interestPool),
            address(0x3006)
        );

        btd.grantRole(MINTER_ROLE, address(interestPool));
        btb.grantRole(MINTER_ROLE, address(interestPool));
        btd.mint(ALICE, 100_000 ether);
        btb.mint(ALICE, 100_000 ether);
    }

    function test_audit_stBTDDepositUpdatesInterestPoolAccounting() public {
        uint256 amount = 10_000 ether;

        vm.startPrank(ALICE);
        btd.approve(address(stbtd), amount);
        stbtd.deposit(amount, ALICE);
        vm.stopPrank();

        assertEq(stbtd.totalAssets(), amount, "vault reports the deposited BTD");
        assertEq(btd.balanceOf(address(stbtd)), 0, "vault stakes deposited BTD into InterestPool");
        assertEq(interestPool.totalStaked(address(btd)), amount, "InterestPool tracks stBTD vault deposits");
        assertEq(interestPool.totalAssetsOf(address(btd), address(stbtd)), amount, "pool exposes vault assets");
    }

    function test_audit_stBTBDepositUpdatesInterestPoolAccounting() public {
        uint256 amount = 10_000 ether;

        vm.startPrank(ALICE);
        btb.approve(address(stbtb), amount);
        stbtb.deposit(amount, ALICE);
        vm.stopPrank();

        assertEq(stbtb.totalAssets(), amount, "vault reports the deposited BTB");
        assertEq(btb.balanceOf(address(stbtb)), 0, "vault stakes deposited BTB into InterestPool");
        assertEq(interestPool.totalStaked(address(btb)), amount, "InterestPool tracks stBTB vault deposits");
        assertEq(interestPool.totalAssetsOf(address(btb), address(stbtb)), amount, "pool exposes vault assets");
    }

    function test_audit_stBTDAssetsAreNotDoubleCountedByCRFormula() public {
        uint256 totalSupplyBefore = btd.totalSupply();
        uint256 wbtcBalance = 1e8;
        uint256 wbtcPrice = 100_000 ether;

        uint256 crBefore = CollateralMath.collateralRatio(
            wbtcBalance,
            wbtcPrice,
            totalSupplyBefore,
            0,
            Constants.PRECISION_18
        );

        vm.startPrank(ALICE);
        btd.approve(address(stbtd), 10_000 ether);
        stbtd.deposit(10_000 ether, ALICE);
        vm.stopPrank();

        assertEq(btd.totalSupply(), totalSupplyBefore, "staking did not mint new BTD");

        uint256 crAfter = CollateralMath.collateralRatio(
            wbtcBalance,
            wbtcPrice,
            btd.totalSupply(),
            stbtd.totalAssets(),
            Constants.PRECISION_18
        );

        assertEq(crBefore, Constants.PRECISION_18, "baseline CR is exactly 100%");
        assertEq(crAfter, crBefore, "stBTD wraps issued BTD and must not lower CR again");
    }

    function test_audit_interestFeeGovernanceParamIsAppliedByInterestPool() public {
        uint256 stakeAmount = 100 ether;
        gov.setParam(ConfigGov.ParamType.InterestFeeBp, 1000);

        vm.startPrank(ALICE);
        btd.approve(address(interestPool), stakeAmount);
        interestPool.stakeBTD(stakeAmount);
        vm.warp(block.timestamp + Constants.SECONDS_PER_YEAR);
        interestPool.unstakeBTD(105 ether);
        vm.stopPrank();

        assertEq(btd.balanceOf(TREASURY), 0.5 ether, "treasury fee follows ConfigGov interestFeeBP");
    }
}
