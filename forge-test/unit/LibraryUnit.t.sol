// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/FeedValidation.sol";
import "../../contracts/libraries/IUSDMath.sol";
import "../../contracts/libraries/OracleMath.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/local/MockAggregatorV3.sol";

contract LibraryUnitTest is Test {
    function testFeedValidationReadsAndScales() public {
        MockAggregatorV3 feed = new MockAggregatorV3(300_000_000_000);
        uint256 price = FeedValidation.readAggregator(address(feed));
        require(price == 3000e18, "price should scale to 18 decimals");
    }

    function testFeedValidationRejectsZero() public {
        vm.expectRevert(bytes("Feed not set"));
        this._callFeedRead(address(0));
    }

    function testFeedValidationRejectsNegative() public {
        MockAggregatorV3 feed = new MockAggregatorV3(-1);
        vm.expectRevert(bytes("Invalid feed price"));
        this._callFeedRead(address(feed));
    }

    function testFeedValidationRejectsInvalidRoundTiming() public {
        MockAggregatorV3 feed = new MockAggregatorV3(300_000_000_000);
        feed.setRoundData(1, 101, 100, 1);

        vm.expectRevert(bytes("Invalid round timing"));
        this._callFeedRead(address(feed));
    }

    function testFeedValidationRejectsIncompleteRoundData() public {
        MockAggregatorV3 feed = new MockAggregatorV3(300_000_000_000);
        feed.setRoundData(1, 0, 0, 1);

        vm.expectRevert(bytes("Incomplete round data"));
        this._callFeedRead(address(feed));
    }

    function testFeedValidationRejectsStaleAnsweredRound() public {
        MockAggregatorV3 feed = new MockAggregatorV3(300_000_000_000);
        feed.setRoundData(2, block.timestamp, block.timestamp, 1);

        vm.expectRevert(bytes("Stale round data"));
        this._callFeedRead(address(feed));
    }

    function testFeedValidationRejectsOldPriceData() public {
        MockAggregatorV3 feed = new MockAggregatorV3(300_000_000_000);
        feed.setRoundData(1, 1, 1, 1);
        vm.warp(7200 + 2);

        vm.expectRevert(bytes("Price data too old"));
        this._callFeedRead(address(feed));
    }

    function testPCEFeedValidationReadsAndScales() public {
        MockAggregatorV3 feed = new MockAggregatorV3(300_00_000_000);
        uint256 pce = FeedValidation.readPCEAggregator(address(feed));
        require(pce == 300e18, "pce should scale to 18 decimals");
    }

    function testPCEFeedValidationRejectsZero() public {
        vm.expectRevert(bytes("PCE Feed not set"));
        this._callPCEFeedRead(address(0));
    }

    function testPCEFeedValidationRejectsNegative() public {
        MockAggregatorV3 feed = new MockAggregatorV3(-1);
        vm.expectRevert(bytes("Invalid PCE value"));
        this._callPCEFeedRead(address(feed));
    }

    function testPCEFeedValidationRejectsInvalidRoundTiming() public {
        MockAggregatorV3 feed = new MockAggregatorV3(300_00_000_000);
        feed.setRoundData(1, 101, 100, 1);

        vm.expectRevert(bytes("Invalid PCE timing"));
        this._callPCEFeedRead(address(feed));
    }

    function testPCEFeedValidationRejectsIncompleteRoundData() public {
        MockAggregatorV3 feed = new MockAggregatorV3(300_00_000_000);
        feed.setRoundData(1, 0, 0, 1);

        vm.expectRevert(bytes("Incomplete PCE round data"));
        this._callPCEFeedRead(address(feed));
    }

    function testPCEFeedValidationRejectsStaleAnsweredRound() public {
        MockAggregatorV3 feed = new MockAggregatorV3(300_00_000_000);
        feed.setRoundData(2, block.timestamp, block.timestamp, 1);

        vm.expectRevert(bytes("Stale PCE round data"));
        this._callPCEFeedRead(address(feed));
    }

    function testPCEFeedValidationRejectsOldPriceData() public {
        MockAggregatorV3 feed = new MockAggregatorV3(300_00_000_000);
        feed.setRoundData(1, 1, 1, 1);
        vm.warp(35 days + 2);

        vm.expectRevert(bytes("PCE data too old"));
        this._callPCEFeedRead(address(feed));
    }

    function testIUSDMathAdjustment() public pure {
        uint256 current = 303_00_000_000;
        uint256 previous = 300_00_000_000;
        (uint256 mult, uint256 factor) = IUSDMath.adjustmentFactor(
            current,
            previous,
            1_001651581301920174
        );
        // current / previous = 1.01
        require(OracleMath.deviationWithin(mult, 101e16, 1), "inflation multiplier near 1.01");
        // factor = 1.01 / monthlyGrowthFactor ~= 1.0082
        require(factor > 1e18, "factor > 1");
    }

    function testOracleMathNormalize() public pure {
        require(OracleMath.normalizeAmount(1e20, 20) == 1e18, "downscale >18");
        require(OracleMath.normalizeAmount(123 * 1e6, 6) == 123 * 1e18, "upscale <18");
        require(OracleMath.normalizeAmount(5e18, 18) == 5e18, "equal decimals");
    }

    function testOracleMathInversePrice() public view {
        require(OracleMath.inversePrice(2e18) == 5e17, "inverse 2 -> 0.5");
        bool reverted = _expectRevertInverse(0);
        require(reverted, "inverse of zero should revert");
    }

    function testOracleMathSpotPrice() public pure {
        uint256 price = OracleMath.spotPrice(2 * 10 ** 8, 100_000 * 10 ** 6, 8, 6); // 2 WBTC, 100k USDC
        require(OracleMath.deviationWithin(price, 50_000e18, 1), "spot near 50k");
    }

    // testPrecisionMathSafeMulDivOverflowPath removed - PrecisionMath library deleted
    // Now using Math.mulDiv directly from OpenZeppelin

    function testDeviationWithinZero() public pure {
        require(!OracleMath.deviationWithin(0, 1e18, 100), "zero should fail");
        require(!OracleMath.deviationWithin(1e18, 0, 100), "zero should fail");
    }

    function _expectRevertInverse(uint256 price) internal view returns (bool) {
        (bool ok, ) = address(this).staticcall(
            abi.encodeWithSelector(this._callInverse.selector, price)
        );
        return !ok;
    }

    function _callFeedRead(address feed) external view returns (uint256) {
        return FeedValidation.readAggregator(feed);
    }

    function _callPCEFeedRead(address feed) external view returns (uint256) {
        return FeedValidation.readPCEAggregator(feed);
    }

    function _callInverse(uint256 price) external pure returns (uint256) {
        return OracleMath.inversePrice(price);
    }
}
