// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../../contracts/libraries/FeedValidation.sol";
import "../../contracts/libraries/IUSDMath.sol";
import "../../contracts/libraries/OracleMath.sol";
import "../../contracts/libraries/Constants.sol";
import "../../contracts/local/MockAggregatorV3.sol";

contract LibraryUnitTest {
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

    // ---- helpers for revert expectation ----
    function _expectRevertFeed(address feed) internal view returns (bool) {
        (bool ok, ) = address(this).staticcall(
            abi.encodeWithSelector(this._callFeedRead.selector, feed)
        );
        return !ok;
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
}
