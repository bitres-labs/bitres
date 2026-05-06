// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";

import "../../contracts/BTB.sol";
import "../../contracts/BTD.sol";
import "../../contracts/ConfigCore.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/libraries/FeedValidation.sol";
import "../../contracts/libraries/MintLogic.sol";
import "../../contracts/libraries/OracleMath.sol";
import "../../contracts/libraries/RedeemLogic.sol";
import "../../contracts/local/MockAggregatorV3.sol";
import "../helpers/ProxyTestHelper.sol";

contract FeedValidationHarness {
    function readAggregator(address feed) external view returns (uint256) {
        return FeedValidation.readAggregator(feed);
    }

    function readPCEAggregator(address feed) external view returns (uint256) {
        return FeedValidation.readPCEAggregator(feed);
    }
}

contract BranchLibraryHarness {
    function inversePrice(uint256 price) external pure returns (uint256) {
        return OracleMath.inversePrice(price);
    }

    function normalizeAmount(uint256 amount, uint8 decimals_) external pure returns (uint256) {
        return OracleMath.normalizeAmount(amount, decimals_);
    }

    function spotPrice(uint256 reserveBase, uint256 reserveQuote, uint8 baseDecimals, uint8 quoteDecimals)
        external
        pure
        returns (uint256)
    {
        return OracleMath.spotPrice(reserveBase, reserveQuote, baseDecimals, quoteDecimals);
    }

    function mintEvaluate(MintLogic.MintInputs memory inputs) external pure returns (MintLogic.MintOutputs memory) {
        return MintLogic.evaluate(inputs);
    }

    function redeemEvaluate(RedeemLogic.RedeemInputs memory inputs)
        external
        pure
        returns (RedeemLogic.RedeemOutputs memory)
    {
        return RedeemLogic.evaluate(inputs);
    }
}

contract CriticalBranchCoverageUnitTest is Test {
    address internal owner = address(this);
    FeedValidationHarness internal feedHarness;
    BranchLibraryHarness internal libraryHarness;

    function setUp() public {
        vm.warp(1_700_000_000);
        feedHarness = new FeedValidationHarness();
        libraryHarness = new BranchLibraryHarness();
    }

    function test_configCoreConstructorRejectsEveryZeroCriticalAddress() public {
        _expectCoreConstructorRevert(0, "Invalid BTC collateral");
        _expectCoreConstructorRevert(1, "Invalid BTD");
        _expectCoreConstructorRevert(2, "Invalid BTB");
        _expectCoreConstructorRevert(3, "Invalid BRS");
        _expectCoreConstructorRevert(4, "Invalid WETH");
        _expectCoreConstructorRevert(5, "Invalid USDC");
        _expectCoreConstructorRevert(6, "Invalid USDT");
        _expectCoreConstructorRevert(7, "Invalid Pool BTC/USDC");
        _expectCoreConstructorRevert(8, "Invalid Pool BTD/USDC");
        _expectCoreConstructorRevert(9, "Invalid Pool BTB/BTD");
        _expectCoreConstructorRevert(10, "Invalid Pool BRS/BTD");
        _expectCoreConstructorRevert(11, "Invalid stBTD");
        _expectCoreConstructorRevert(12, "Invalid stBTB");
    }

    function test_configCoreSetCoreContractsRejectsInvalidAndSecondSet() public {
        ConfigCore core = _validCore();

        _expectSetCoreRevert(core, 0, "Invalid Treasury");
        _expectSetCoreRevert(core, 1, "Invalid Minter");
        _expectSetCoreRevert(core, 2, "Invalid PriceOracle");
        _expectSetCoreRevert(core, 3, "Invalid IdealUSDManager");
        _expectSetCoreRevert(core, 4, "Invalid InterestPool");
        _expectSetCoreRevert(core, 5, "Invalid FarmingPool");

        core.setCoreContracts(
            address(0x3000), address(0x3001), address(0x3002), address(0x3003), address(0x3004), address(0x3005)
        );
        assertTrue(core.coreContractsSet(), "core contracts set");

        vm.expectRevert("Core contracts already set");
        core.setCoreContracts(
            address(0x4000), address(0x4001), address(0x4002), address(0x4003), address(0x4004), address(0x4005)
        );

        core.renounceOwnership();
        assertEq(core.owner(), address(0), "ownership renounced");
    }

    function test_tokenMintRoleBranchesForBTDAndBTB() public {
        BTD btd = ProxyTestHelper.deployBTD(owner);
        BTB btb = ProxyTestHelper.deployBTB(owner);
        address outsider = address(0xBEEF);

        vm.startPrank(outsider);
        vm.expectRevert();
        btd.mint(outsider, 1e18);
        vm.expectRevert();
        btb.mint(outsider, 1e18);
        vm.stopPrank();

        btd.grantRole(btd.MINTER_ROLE(), owner);
        btb.grantRole(btb.MINTER_ROLE(), owner);
        btd.mint(outsider, 1e18);
        btb.mint(outsider, 2e18);

        assertEq(btd.balanceOf(outsider), 1e18, "BTD minted");
        assertEq(btb.balanceOf(outsider), 2e18, "BTB minted");
    }

    function test_feedValidationAggregatorBranches() public {
        MockAggregatorV3 feed = new MockAggregatorV3(100_000_000);
        assertEq(feedHarness.readAggregator(address(feed)), 1e18, "8 decimal feed normalized");

        feed.setDecimals(20);
        assertEq(feedHarness.readAggregator(address(feed)), 1_000_000, "high decimal feed downscaled");

        vm.expectRevert("Feed not set");
        feedHarness.readAggregator(address(0));

        MockAggregatorV3 invalidPrice = _feed(0);
        vm.expectRevert("Invalid feed price");
        feedHarness.readAggregator(address(invalidPrice));

        MockAggregatorV3 invalidTiming = _feed(100_000_000);
        invalidTiming.setRoundData(2, block.timestamp, block.timestamp - 1, 2);
        vm.expectRevert("Invalid round timing");
        feedHarness.readAggregator(address(invalidTiming));

        MockAggregatorV3 incomplete = _feed(100_000_000);
        incomplete.setRoundData(2, 0, 0, 2);
        vm.expectRevert("Incomplete round data");
        feedHarness.readAggregator(address(incomplete));

        MockAggregatorV3 staleRound = _feed(100_000_000);
        staleRound.setRoundData(3, block.timestamp, block.timestamp, 2);
        vm.expectRevert("Stale round data");
        feedHarness.readAggregator(address(staleRound));

        MockAggregatorV3 oldData = _feed(100_000_000);
        oldData.setRoundData(3, block.timestamp - 7201, block.timestamp - 7201, 3);
        vm.expectRevert("Price data too old");
        feedHarness.readAggregator(address(oldData));
    }

    function test_feedValidationPCEBranches() public {
        MockAggregatorV3 pce = new MockAggregatorV3(300_000_000);
        assertEq(feedHarness.readPCEAggregator(address(pce)), 3e18, "PCE normalized");

        vm.expectRevert("PCE Feed not set");
        feedHarness.readPCEAggregator(address(0));

        MockAggregatorV3 invalidPrice = _feed(0);
        vm.expectRevert("Invalid PCE value");
        feedHarness.readPCEAggregator(address(invalidPrice));

        MockAggregatorV3 invalidTiming = _feed(300_000_000);
        invalidTiming.setRoundData(2, block.timestamp, block.timestamp - 1, 2);
        vm.expectRevert("Invalid PCE timing");
        feedHarness.readPCEAggregator(address(invalidTiming));

        MockAggregatorV3 incomplete = _feed(300_000_000);
        incomplete.setRoundData(2, 0, 0, 2);
        vm.expectRevert("Incomplete PCE round data");
        feedHarness.readPCEAggregator(address(incomplete));

        MockAggregatorV3 staleRound = _feed(300_000_000);
        staleRound.setRoundData(3, block.timestamp, block.timestamp, 2);
        vm.expectRevert("Stale PCE round data");
        feedHarness.readPCEAggregator(address(staleRound));

        MockAggregatorV3 oldData = _feed(300_000_000);
        oldData.setRoundData(3, block.timestamp - 35 days - 1, block.timestamp - 35 days - 1, 3);
        vm.expectRevert("PCE data too old");
        feedHarness.readPCEAggregator(address(oldData));
    }

    function test_oracleMathMintLogicAndRedeemLogicBranches() public {
        assertEq(libraryHarness.normalizeAmount(123, 18), 123, "18 decimals unchanged");
        assertEq(libraryHarness.normalizeAmount(123_000_000, 20), 1_230_000, "20 decimals downscaled");
        assertEq(libraryHarness.normalizeAmount(123, 6), 123e12, "6 decimals upscaled");

        vm.expectRevert("Oracle: zero price");
        libraryHarness.inversePrice(0);
        vm.expectRevert("Oracle: zero reserve");
        libraryHarness.spotPrice(0, 1e18, 18, 18);

        MintLogic.MintInputs memory mintInputs = MintLogic.MintInputs({
            wbtcAmount: 1e8, wbtcPrice: 50_000e18, iusdPrice: 1e18, currentBTDSupply: 1_000e18, feeBP: 50
        });
        MintLogic.MintOutputs memory mintResult = libraryHarness.mintEvaluate(mintInputs);
        assertGt(mintResult.btdToMint, 0, "valid mint");

        mintInputs.wbtcAmount = 0;
        vm.expectRevert("Invalid amount");
        libraryHarness.mintEvaluate(mintInputs);
        mintInputs.wbtcAmount = 1e8;
        mintInputs.wbtcPrice = 0;
        vm.expectRevert("Invalid WBTC price");
        libraryHarness.mintEvaluate(mintInputs);
        mintInputs.wbtcPrice = 50_000e18;
        mintInputs.iusdPrice = 0;
        vm.expectRevert("Invalid IUSD price");
        libraryHarness.mintEvaluate(mintInputs);
        mintInputs.iusdPrice = 1e18;
        mintInputs.wbtcAmount = 1;
        mintInputs.wbtcPrice = 1e18;
        vm.expectRevert("Mint value too small");
        libraryHarness.mintEvaluate(mintInputs);

        RedeemLogic.RedeemInputs memory redeemInputs = _redeemInputs(100e18, 1.2e18, 1e18, 0.6e18, 1e18);
        RedeemLogic.RedeemOutputs memory overResult = libraryHarness.redeemEvaluate(redeemInputs);
        assertGt(overResult.wbtcOutNormalized, 0, "overcollateralized redeem");

        redeemInputs.btdAmount = 0;
        vm.expectRevert("Invalid amount");
        libraryHarness.redeemEvaluate(redeemInputs);
        redeemInputs = _redeemInputs(100e18, 1e18, 1e18, 0.6e18, 1e18);
        redeemInputs.iusdPrice = 0;
        vm.expectRevert("Invalid price");
        libraryHarness.redeemEvaluate(redeemInputs);
        redeemInputs = _redeemInputs(1, 1e18, 1e18, 0.6e18, 1e18);
        vm.expectRevert("Redeem value too small");
        libraryHarness.redeemEvaluate(redeemInputs);

        redeemInputs = _redeemInputs(100e18, 0.7e18, 1e18, 0.6e18, 1e18);
        RedeemLogic.RedeemOutputs memory healthyBtb = libraryHarness.redeemEvaluate(redeemInputs);
        assertGt(healthyBtb.btbOut, 0, "BTB compensation");
        assertEq(healthyBtb.brsOut, 0, "no BRS when BTB healthy");

        redeemInputs = _redeemInputs(100e18, 0.7e18, 1e18, 0.2e18, 1e18);
        RedeemLogic.RedeemOutputs memory belowFloor = libraryHarness.redeemEvaluate(redeemInputs);
        assertGt(belowFloor.brsOut, 0, "BRS compensation");

        redeemInputs.brsPrice = 0;
        vm.expectRevert("Invalid BRS price");
        libraryHarness.redeemEvaluate(redeemInputs);

        redeemInputs = _redeemInputs(100e18, 0.7e18, 0, 0.6e18, 1e18);
        vm.expectRevert("Invalid secondary price");
        libraryHarness.redeemEvaluate(redeemInputs);
    }

    function _feed(int256 answer) internal returns (MockAggregatorV3) {
        return new MockAggregatorV3(answer);
    }

    function _validCore() internal returns (ConfigCore) {
        address[13] memory args = _validCoreArgs();
        return _deployCore(args);
    }

    function _expectCoreConstructorRevert(uint256 index, string memory reason) internal {
        address[13] memory args = _validCoreArgs();
        args[index] = address(0);
        vm.expectRevert(bytes(reason));
        _deployCore(args);
    }

    function _expectSetCoreRevert(ConfigCore core, uint256 index, string memory reason) internal {
        address[6] memory args =
            [address(0x2000), address(0x2001), address(0x2002), address(0x2003), address(0x2004), address(0x2005)];
        args[index] = address(0);

        vm.expectRevert(bytes(reason));
        core.setCoreContracts(args[0], args[1], args[2], args[3], args[4], args[5]);
    }

    function _validCoreArgs() internal pure returns (address[13] memory args) {
        for (uint256 i = 0; i < args.length; i++) {
            args[i] = address(uint160(0x1000 + i));
        }
    }

    function _deployCore(address[13] memory args) internal returns (ConfigCore) {
        return new ConfigCore(
            args[0],
            args[1],
            args[2],
            args[3],
            args[4],
            args[5],
            args[6],
            args[7],
            args[8],
            args[9],
            args[10],
            args[11],
            args[12]
        );
    }

    function _redeemInputs(uint256 amount, uint256 cr, uint256 btdPrice, uint256 btbPrice, uint256 brsPrice)
        internal
        pure
        returns (RedeemLogic.RedeemInputs memory)
    {
        return RedeemLogic.RedeemInputs({
            btdAmount: amount,
            wbtcPrice: 50_000e18,
            iusdPrice: 1e18,
            cr: cr,
            btdPrice: btdPrice,
            btbPrice: btbPrice,
            brsPrice: brsPrice,
            minBTBPriceInBTD: 0.5e18,
            redeemFeeBP: 50
        });
    }
}
