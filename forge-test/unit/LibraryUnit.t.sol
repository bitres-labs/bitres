// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../../contracts/libraries/PriceBlend.sol";
import "../../contracts/libraries/FeedValidation.sol";
import "../../contracts/libraries/IUSDMath.sol";
import "../../contracts/libraries/OracleMath.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/local/MockAggregatorV3.sol";

contract LibraryUnitTest {
    function testMedian3Permutations() public pure {
        require(PriceBlend.median3(1, 2, 3) == 2, "sorted");
        require(PriceBlend.median3(3, 2, 1) == 2, "reverse");
        require(PriceBlend.median3(2, 3, 1) == 2, "rotated");
        require(PriceBlend.median3(7, 7, 9) == 7, "duplicate high");
        require(PriceBlend.median3(5, 3, 3) == 3, "duplicate low");
    }

    function testValidateSpotAgainstRefPass() public pure {
        uint256 ref = 100e18;
        uint256 spot = 100_50e16; // +0.5%
        PriceBlend.validateSpotAgainstRef(spot, ref, 100); // 1%
    }

    function testValidateSpotAgainstRefFail() public view {
        uint256 ref = 100e18;
        uint256 spot = 102e18;
        bool reverted = _expectRevertValidate(spot, ref, 100);
        require(reverted, "should revert when > max bps");
    }

    function testFeedValidationReadsAndScales() public {
        MockAggregatorV3 feed = new MockAggregatorV3(300_000_000_000);
        uint256 price = FeedValidation.readAggregator(address(feed));
        require(price == 3000e18, "price should scale to 18 decimals");
    }

    function testFeedValidationRejectsZero() public view {
        bool reverted = _expectRevertFeed(address(0));
        require(reverted, "zero feed should revert");
    }

    function testFeedValidationRejectsNegative() public {
        MockAggregatorV3 feed = new MockAggregatorV3(-1);
        bool reverted = _expectRevertFeed(address(feed));
        require(reverted, "negative answer should revert");
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

    // ---- New PriceBlend functions tests ----

    function testBlendMultiSourceThreeSource() public pure {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 50000e18;
        prices[1] = 50050e18;
        prices[2] = 49950e18;

        uint256 result = PriceBlend.blendMultiSource(prices, 100); // 1% deviation
        require(result == 50000e18, "median should be 50000");
    }

    function testBlendMultiSourceFiveSource() public pure {
        uint256[] memory prices = new uint256[](5);
        prices[0] = 100e18;
        prices[1] = 102e18;
        prices[2] = 101e18;
        prices[3] = 99e18;
        prices[4] = 103e18;

        uint256 result = PriceBlend.blendMultiSource(prices, 300); // 3% deviation
        require(result == 101e18, "median should be 101");
    }

    function testBlendMultiSourceEvenCount() public pure {
        uint256[] memory prices = new uint256[](4);
        prices[0] = 100e18;
        prices[1] = 102e18;
        prices[2] = 98e18;
        prices[3] = 104e18;

        uint256 result = PriceBlend.blendMultiSource(prices, 400); // 4% deviation
        // Sorted: [98, 100, 102, 104]
        // Median (even): (100 + 102) / 2 = 101
        require(result == 101e18, "median should be 101");
    }

    function testBlendMultiSourceRevertsOnExcessiveDeviation() public view {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 50000e18;
        prices[1] = 51000e18; // 2% deviation from 50000
        prices[2] = 49950e18;

        bool reverted = _expectRevertBlend(prices, 100); // Only allow 1%
        require(reverted, "should revert on excessive deviation");
    }

    function testBlendMultiSourceRevertsOnInsufficientPrices() public view {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 50000e18;

        bool reverted = _expectRevertBlend(prices, 100);
        require(reverted, "should revert with < 2 prices");
    }

    function testValidateAllWithinBoundsPass() public pure {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 50000e18;
        prices[1] = 50050e18; // 0.1% from first
        prices[2] = 49950e18; // 0.1% from first

        bool valid = PriceBlend.validateAllWithinBounds(prices, 100); // 1%
        require(valid, "all prices should be within bounds");
    }

    function testValidateAllWithinBoundsFail() public pure {
        uint256[] memory prices = new uint256[](3);
        prices[0] = 50000e18;
        prices[1] = 51000e18; // 2% from first
        prices[2] = 49950e18;

        bool valid = PriceBlend.validateAllWithinBounds(prices, 100); // 1%
        require(!valid, "should fail due to excessive deviation");
    }

    function testValidateAllWithinBoundsMultipleSources() public pure {
        uint256[] memory prices = new uint256[](5);
        prices[0] = 100e18;
        prices[1] = 101e18;
        prices[2] = 100_5e17; // 100.5
        prices[3] = 99_5e17;  // 99.5
        prices[4] = 101e18;   // 101 (changed from 101.5 to stay within 2%)

        bool valid = PriceBlend.validateAllWithinBounds(prices, 200); // 2%
        require(valid, "all prices should be within 2%");
    }

    function testValidateAllWithinBoundsRejectsInsufficientPrices() public view {
        uint256[] memory prices = new uint256[](1);
        prices[0] = 100e18;

        bool reverted = _expectRevertValidateAll(prices, 100);
        require(reverted, "should revert with < 2 prices");
    }

    // ---- helpers for revert expectation ----
    function _expectRevertValidate(uint256 spot, uint256 ref, uint256 bps) internal view returns (bool) {
        (bool ok, ) = address(this).staticcall(
            abi.encodeWithSelector(this._callValidate.selector, spot, ref, bps)
        );
        return !ok;
    }

    function _expectRevertFeed(address feed) internal view returns (bool) {
        (bool ok, ) = address(this).staticcall(
            abi.encodeWithSelector(this._callFeedRead.selector, feed)
        );
        return !ok;
    }

    function _callValidate(uint256 spot, uint256 ref, uint256 bps) external pure returns (uint256) {
        PriceBlend.validateSpotAgainstRef(spot, ref, bps);
        return spot;
    }

    function _callFeedRead(address feed) external view returns (uint256) {
        return FeedValidation.readAggregator(feed);
    }

    function _expectRevertInverse(uint256 price) internal view returns (bool) {
        (bool ok, ) = address(this).staticcall(
            abi.encodeWithSelector(this._callInverse.selector, price)
        );
        return !ok;
    }

    function _callInverse(uint256 price) external pure returns (uint256) {
        return OracleMath.inversePrice(price);
    }

    function _expectRevertBlend(uint256[] memory prices, uint256 bps) internal view returns (bool) {
        (bool ok, ) = address(this).staticcall(
            abi.encodeWithSelector(this._callBlend.selector, prices, bps)
        );
        return !ok;
    }

    function _callBlend(uint256[] memory prices, uint256 bps) external pure returns (uint256) {
        return PriceBlend.blendMultiSource(prices, bps);
    }

    function _expectRevertValidateAll(uint256[] memory prices, uint256 bps) internal view returns (bool) {
        (bool ok, ) = address(this).staticcall(
            abi.encodeWithSelector(this._callValidateAll.selector, prices, bps)
        );
        return !ok;
    }

    function _callValidateAll(uint256[] memory prices, uint256 bps) external pure returns (bool) {
        return PriceBlend.validateAllWithinBounds(prices, bps);
    }
}
