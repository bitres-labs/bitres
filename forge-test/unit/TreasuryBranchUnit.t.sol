// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

import "../../contracts/BRS.sol";
import "../../contracts/BTB.sol";
import "../../contracts/BTD.sol";
import "../../contracts/ConfigCore.sol";
import "../../contracts/ConfigGov.sol";
import "../../contracts/Treasury.sol";
import "../../contracts/interfaces/ITreasury.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/local/MockIUSDManager.sol";
import "../../contracts/local/MockPriceOracle.sol";
import "../../contracts/local/MockUSDC.sol";
import "../../contracts/local/MockUSDT.sol";
import "../../contracts/local/MockWBTC.sol";
import "../../contracts/local/MockWETH.sol";
import "../../contracts/stBTB.sol";
import "../../contracts/stBTD.sol";
import "../helpers/ProxyTestHelper.sol";

contract TreasuryBranchRouter {
    address public immutable wethAddr;
    bool public shortTokenAmounts;
    bool public shortEthAmounts;
    bool public revertEthSwap;
    uint256 public tokenOutputBps = 10_000;
    uint256 public ethOut = 0.1 ether;
    uint256 public lastTokenAmountIn;
    uint256 public lastEthAmountIn;

    constructor(address _weth) {
        wethAddr = _weth;
    }

    receive() external payable { }

    function WETH() external view returns (address) {
        return wethAddr;
    }

    function setShortTokenAmounts(bool value) external {
        shortTokenAmounts = value;
    }

    function setShortEthAmounts(bool value) external {
        shortEthAmounts = value;
    }

    function setRevertEthSwap(bool value) external {
        revertEthSwap = value;
    }

    function setTokenOutputBps(uint256 value) external {
        tokenOutputBps = value;
    }

    function setEthOut(uint256 value) external {
        ethOut = value;
    }

    function swapExactTokensForTokens(uint256 amountIn, uint256, address[] calldata path, address to, uint256)
        external
        returns (uint256[] memory amounts)
    {
        lastTokenAmountIn = amountIn;
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        uint256 outputAmount = amountIn * tokenOutputBps / 10_000;
        IERC20(path[path.length - 1]).transfer(to, outputAmount);

        amounts = new uint256[](shortTokenAmounts ? 1 : 2);
        amounts[0] = amountIn;
        if (amounts.length > 1) {
            amounts[1] = outputAmount;
        }
    }

    function swapExactTokensForETH(uint256 amountIn, uint256, address[] calldata path, address to, uint256)
        external
        returns (uint256[] memory amounts)
    {
        if (revertEthSwap) {
            revert("router eth swap failed");
        }

        lastEthAmountIn = amountIn;
        IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);
        (bool ok,) = payable(to).call{ value: ethOut }("");
        require(ok, "ETH transfer failed");

        amounts = new uint256[](shortEthAmounts ? 1 : 2);
        amounts[0] = amountIn;
        if (amounts.length > 1) {
            amounts[1] = ethOut;
        }
    }
}

contract TreasuryBranchUnitTest is Test {
    event BRSCompensationShortfall(address indexed to, uint256 requested, uint256 actual);
    event LazyBuybackExecuted(
        address indexed triggeredBy, uint256 btdSpent, uint256 brsReceived, uint256 gasCompensation
    );
    event EthReserveToppedUp(uint256 btdSpent, uint256 ethReceived);

    address public owner = address(this);
    address public minter = vm.addr(0xB17E5);
    address public interestPool = address(0x1111);
    address public farmingPool = address(0x2222);
    address public user = address(0xBEEF);

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
    MockIUSDManager public iusdManager;
    TreasuryBranchRouter public router;
    Treasury public treasury;

    function setUp() public {
        wbtc = new MockWBTC(owner);
        usdc = new MockUSDC(owner);
        usdt = new MockUSDT(owner);
        weth = new MockWETH(owner);
        btd = ProxyTestHelper.deployBTD(owner);
        btb = ProxyTestHelper.deployBTB(owner);
        brs = new BRS(owner);
        stbtd = ProxyTestHelper.deployStBTD(IERC20(address(btd)), owner);
        stbtb = ProxyTestHelper.deployStBTB(IERC20(address(btb)), owner);

        core = new ConfigCore(
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
        gov = ProxyTestHelper.deployConfigGov(owner);
        priceOracle = new MockPriceOracle();
        iusdManager = new MockIUSDManager(1e18);
        router = new TreasuryBranchRouter(address(weth));
        treasury = ProxyTestHelper.deployTreasury(owner, address(core), address(router));

        core.setCoreContracts(
            address(treasury), minter, address(priceOracle), address(iusdManager), interestPool, farmingPool
        );

        btd.grantRole(btd.MINTER_ROLE(), owner);
    }

    function test_compensateCoversZeroPartialExactAndFullPayoutBranches() public {
        vm.prank(minter);
        treasury.compensate(user, 100e18);
        assertEq(brs.balanceOf(user), 0, "zero treasury balance should skip transfer");

        brs.transfer(address(treasury), 40e18);
        vm.prank(minter);
        vm.expectEmit(true, false, false, true);
        emit BRSCompensationShortfall(user, 100e18, 40e18);
        treasury.compensate(user, 100e18);
        assertEq(brs.balanceOf(user), 40e18, "partial payout");

        brs.transfer(address(treasury), 100e18);
        vm.prank(minter);
        treasury.compensate(user, 100e18);
        assertEq(brs.balanceOf(user), 140e18, "exact payout");

        brs.transfer(address(treasury), 200e18);
        vm.prank(minter);
        treasury.compensate(user, 50e18);
        assertEq(brs.balanceOf(user), 190e18, "full payout with surplus");
        assertEq(brs.balanceOf(address(treasury)), 150e18, "surplus retained");
    }

    function test_buybackBRS_revertsInvalidSwapResultBranch() public {
        btd.mint(address(treasury), 1_000e18);
        brs.transfer(address(router), 1_000e18);
        router.setShortTokenAmounts(true);

        vm.expectRevert("Treasury: invalid swap result");
        treasury.buybackBRS(1_000e18, Constants.MIN_STABLECOIN_18_AMOUNT);
    }

    function test_tryLazyBuyback_capsEligibleAmountAtMaxAndPaysEOAGasCompensation() public {
        _setBuybackParams(1_000e18, 2_000e18, 100);
        btd.mint(address(treasury), 10_000e18);
        brs.transfer(address(router), 10_000e18);
        vm.deal(address(treasury), 2 ether);
        vm.txGasPrice(1 gwei);
        _warpPastCooldown();

        uint256 minterEthBefore = minter.balance;
        vm.prank(minter);
        bool executed = treasury.tryLazyBuyback();

        assertTrue(executed, "buyback should execute");
        assertEq(router.lastTokenAmountIn(), 2_000e18, "max buyback amount should cap eligible balance");
        assertGt(minter.balance, minterEthBefore, "EOA caller should receive gas compensation");
    }

    function test_tryLazyBuyback_skipsGasCompensationForContractCaller() public {
        _setBuybackParams(1_000e18, 2_000e18, 100);
        btd.mint(address(treasury), 2_000e18);
        brs.transfer(address(router), 2_000e18);
        vm.deal(address(treasury), 2 ether);
        _warpPastCooldown();

        uint256 ownerEthBefore = owner.balance;
        bool executed = treasury.tryLazyBuyback();

        assertTrue(executed, "owner-triggered buyback should execute");
        assertEq(owner.balance, ownerEthBefore, "contract caller should not receive gas compensation");
    }

    function test_tryLazyBuyback_topsUpEthReserveAndCapsBtdForEth() public {
        _setBuybackParams(1_000e18, 1_000e18, 100);
        treasury.setEthReserveParams(0.5 ether, 0.1 ether);
        btd.mint(address(treasury), 1_150e18);
        brs.transfer(address(router), 1_000e18);
        vm.deal(address(router), 1 ether);
        _warpPastCooldown();

        vm.expectEmit(false, false, false, true);
        emit EthReserveToppedUp(150e18, 0.1 ether);
        bool executed = treasury.tryLazyBuyback();

        assertTrue(executed, "buyback should execute");
        assertEq(router.lastEthAmountIn(), 150e18, "ETH topup should cap BTD input to remaining balance");
        assertEq(address(treasury).balance, 0.1 ether, "ETH reserve should be topped up");
    }

    function test_tryLazyBuyback_skipsEthTopupWhenRemainingBtdBelowThreshold() public {
        _setBuybackParams(1_000e18, 1_000e18, 100);
        btd.mint(address(treasury), 1_000e18);
        brs.transfer(address(router), 1_000e18);
        vm.deal(address(router), 1 ether);
        _warpPastCooldown();

        bool executed = treasury.tryLazyBuyback();

        assertTrue(executed, "buyback should execute");
        assertEq(router.lastEthAmountIn(), 0, "topup should skip when no BTD remains");
        assertEq(address(treasury).balance, 0, "treasury should receive no ETH");
    }

    function test_tryLazyBuyback_swallowsEthTopupRouterRevert() public {
        _setBuybackParams(1_000e18, 1_000e18, 100);
        btd.mint(address(treasury), 1_300e18);
        brs.transfer(address(router), 1_000e18);
        router.setRevertEthSwap(true);
        _warpPastCooldown();

        bool executed = treasury.tryLazyBuyback();

        assertTrue(executed, "ETH topup failure should not revert buyback");
        assertEq(address(treasury).balance, 0, "failed topup should not change ETH balance");
    }

    function _setBuybackParams(uint256 minAmount, uint256 maxAmount, uint256 probability) internal {
        treasury.setBuybackParams(minAmount, maxAmount, 1 hours, probability, 200);
    }

    function _warpPastCooldown() internal {
        vm.warp(block.timestamp + treasury.buybackCooldown() + 1);
        vm.roll(block.number + 1);
    }
}
