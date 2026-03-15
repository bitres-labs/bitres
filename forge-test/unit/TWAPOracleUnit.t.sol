// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/UniswapV2TWAPOracle.sol";
import "../../contracts/local/UniswapV2Pair.sol";
import "../../contracts/local/MockWBTC.sol";
import "../../contracts/local/MockUSDC.sol";
import "../../contracts/BTD.sol";
import "../helpers/ProxyTestHelper.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title UniswapV2TWAPOracle Unit Tests
/// @notice Comprehensive tests for TWAP oracle functionality including update logic,
///         readiness checks, price computation, and observation management.
contract TWAPOracleUnitTest is Test {
    UniswapV2TWAPOracle public oracle;

    // WBTC/USDC pair
    UniswapV2Pair public wbtcUsdcPair;
    MockWBTC public wbtc;
    MockUSDC public usdc;

    // BTD/USDC pair
    UniswapV2Pair public btdUsdcPair;
    BTD public btd;
    MockUSDC public usdc2; // separate USDC instance for BTD pair

    uint256 constant PERIOD = 30 minutes;

    function setUp() public {
        // Set a known starting timestamp to avoid zero-timestamp edge cases
        vm.warp(1_000_000);

        oracle = ProxyTestHelper.deployTWAPOracle(address(this));

        // --- Deploy WBTC/USDC pair with real liquidity ---
        wbtc = new MockWBTC(address(this));
        usdc = new MockUSDC(address(this));

        wbtcUsdcPair = new UniswapV2Pair();
        // Ensure token0 < token1 ordering (match Uniswap convention)
        if (address(wbtc) < address(usdc)) {
            wbtcUsdcPair.initialize(address(wbtc), address(usdc));
        } else {
            wbtcUsdcPair.initialize(address(usdc), address(wbtc));
        }

        // Provide liquidity: 1 WBTC = 100,000 USDC
        // Transfer tokens to pair then mint LP
        _addLiquidityWbtcUsdc(1e8, 100_000e6);

        // --- Deploy BTD/USDC pair with real liquidity ---
        btd = ProxyTestHelper.deployBTD(address(this));
        btd.grantRole(btd.MINTER_ROLE(), address(this));
        btd.mint(address(this), 1_000_000e18);

        usdc2 = new MockUSDC(address(this));

        btdUsdcPair = new UniswapV2Pair();
        if (address(btd) < address(usdc2)) {
            btdUsdcPair.initialize(address(btd), address(usdc2));
        } else {
            btdUsdcPair.initialize(address(usdc2), address(btd));
        }

        // Provide liquidity: 1 BTD = 1 USDC (stablecoin)
        _addLiquidityBtdUsdc(100_000e18, 100_000e6);
    }

    // ============ Helper Functions ============

    function _addLiquidityWbtcUsdc(uint256 amountWbtc, uint256 amountUsdc) internal {
        address t0 = wbtcUsdcPair.token0();

        if (t0 == address(wbtc)) {
            wbtc.transfer(address(wbtcUsdcPair), amountWbtc);
            usdc.transfer(address(wbtcUsdcPair), amountUsdc);
        } else {
            usdc.transfer(address(wbtcUsdcPair), amountUsdc);
            wbtc.transfer(address(wbtcUsdcPair), amountWbtc);
        }
        wbtcUsdcPair.mint(address(this));
    }

    function _addLiquidityBtdUsdc(uint256 amountBtd, uint256 amountUsdc) internal {
        address t0 = btdUsdcPair.token0();

        if (t0 == address(btd)) {
            IERC20(address(btd)).transfer(address(btdUsdcPair), amountBtd);
            usdc2.transfer(address(btdUsdcPair), amountUsdc);
        } else {
            usdc2.transfer(address(btdUsdcPair), amountUsdc);
            IERC20(address(btd)).transfer(address(btdUsdcPair), amountBtd);
        }
        btdUsdcPair.mint(address(this));
    }

    /// @dev Perform a full TWAP warmup: two updates separated by PERIOD
    function _warmupTWAP(address pair) internal {
        oracle.updateIfNeeded(pair);
        vm.warp(block.timestamp + PERIOD);
        // Sync the pair so cumulative prices advance with time
        UniswapV2Pair(pair).sync();
        oracle.updateIfNeeded(pair);
    }

    // ============ updateIfNeeded Tests ============

    function test_updateIfNeeded_firstUpdate() public {
        // Before any update, observations should be empty
        (, uint32 newerTs,) = oracle.getObservationInfo(address(wbtcUsdcPair));
        assertEq(newerTs, 0, "Newer timestamp should be 0 before first update");

        // First update should succeed
        bool updated = oracle.updateIfNeeded(address(wbtcUsdcPair));
        assertTrue(updated, "First update should return true");

        // Verify observation was stored
        (, newerTs,) = oracle.getObservationInfo(address(wbtcUsdcPair));
        assertEq(newerTs, uint32(block.timestamp), "Newer timestamp should match current block timestamp");
    }

    function test_updateIfNeeded_withinPeriod() public {
        // First update
        oracle.updateIfNeeded(address(wbtcUsdcPair));

        // Advance less than PERIOD
        vm.warp(block.timestamp + PERIOD - 1);

        // Second update should be skipped
        bool updated = oracle.updateIfNeeded(address(wbtcUsdcPair));
        assertFalse(updated, "Update within PERIOD should return false");
    }

    function test_updateIfNeeded_afterPeriod() public {
        // First update at known time
        uint256 t1 = 2_000_000;
        vm.warp(t1);
        oracle.updateIfNeeded(address(wbtcUsdcPair));

        // Advance exactly PERIOD
        uint256 t2 = t1 + PERIOD;
        vm.warp(t2);
        wbtcUsdcPair.sync(); // sync to update cumulative prices

        // Second update should succeed
        bool updated = oracle.updateIfNeeded(address(wbtcUsdcPair));
        assertTrue(updated, "Update after PERIOD should return true");

        // Verify both observations are stored (older = first, newer = second)
        (uint32 olderTs, uint32 newerTs,) = oracle.getObservationInfo(address(wbtcUsdcPair));
        assertEq(uint256(olderTs), t1, "Older observation should have first update timestamp");
        assertEq(uint256(newerTs), t2, "Newer observation should have second update timestamp");
    }

    // ============ isTWAPReady Tests ============

    function test_isTWAPReady_noObservations() public view {
        // Fresh pair with no updates
        bool ready = oracle.isTWAPReady(address(wbtcUsdcPair));
        assertFalse(ready, "TWAP should not be ready with no observations");
    }

    function test_isTWAPReady_oneObservation_tooRecent() public {
        // Single update, not enough time elapsed
        oracle.updateIfNeeded(address(wbtcUsdcPair));

        // Advance less than PERIOD
        vm.warp(block.timestamp + PERIOD - 1);

        bool ready = oracle.isTWAPReady(address(wbtcUsdcPair));
        assertFalse(ready, "TWAP should not be ready with one recent observation");
    }

    function test_isTWAPReady_ready() public {
        // Full warmup: two updates separated by PERIOD
        _warmupTWAP(address(wbtcUsdcPair));

        // Advance a bit more so the newer observation is >= PERIOD old
        vm.warp(block.timestamp + PERIOD);

        bool ready = oracle.isTWAPReady(address(wbtcUsdcPair));
        assertTrue(ready, "TWAP should be ready after proper warmup and time");
    }

    function test_isTWAPReady_oneObservation_afterPeriod() public {
        // Single update
        oracle.updateIfNeeded(address(wbtcUsdcPair));

        // Advance >= PERIOD so the single observation (stored in slot [1]) is old enough
        vm.warp(block.timestamp + PERIOD);

        bool ready = oracle.isTWAPReady(address(wbtcUsdcPair));
        assertTrue(ready, "TWAP should be ready when single observation is >= PERIOD old");
    }

    // ============ getTWAP Tests ============

    function test_getTWAP_noObservations_reverts() public {
        vm.expectRevert("No observations");
        oracle.getTWAP(address(wbtcUsdcPair));
    }

    function test_getTWAP_notReady_reverts() public {
        // One observation, but not enough time elapsed
        oracle.updateIfNeeded(address(wbtcUsdcPair));

        // Only advance a small amount (less than PERIOD)
        vm.warp(block.timestamp + 10 minutes);

        vm.expectRevert("No observation >= PERIOD ago");
        oracle.getTWAP(address(wbtcUsdcPair));
    }

    function test_getTWAP_normal() public {
        // First update to record initial cumulative prices
        oracle.updateIfNeeded(address(wbtcUsdcPair));

        // Advance time by PERIOD, sync pair to accumulate prices
        vm.warp(block.timestamp + PERIOD);
        wbtcUsdcPair.sync();

        // Second update
        oracle.updateIfNeeded(address(wbtcUsdcPair));

        // Advance PERIOD again so the older observation qualifies
        vm.warp(block.timestamp + PERIOD);
        wbtcUsdcPair.sync();

        // getTWAP should return a non-zero Q112 price
        uint256 twap = oracle.getTWAP(address(wbtcUsdcPair));
        assertGt(twap, 0, "TWAP should be non-zero after proper warmup");
    }

    // ============ getTWAPPrice Tests ============

    function test_getTWAPPrice_WBTC_USDC() public {
        // Full warmup for WBTC/USDC pair
        oracle.updateIfNeeded(address(wbtcUsdcPair));
        vm.warp(block.timestamp + PERIOD);
        wbtcUsdcPair.sync();
        oracle.updateIfNeeded(address(wbtcUsdcPair));
        vm.warp(block.timestamp + PERIOD);
        wbtcUsdcPair.sync();

        // Determine token ordering to pass correct decimals
        address t0 = wbtcUsdcPair.token0();
        uint8 t0Decimals;
        uint8 t1Decimals;
        if (t0 == address(wbtc)) {
            t0Decimals = 8;
            t1Decimals = 6;
        } else {
            t0Decimals = 6;
            t1Decimals = 8;
        }

        uint256 price = oracle.getTWAPPrice(address(wbtcUsdcPair), t0Decimals, t1Decimals);
        assertGt(price, 0, "WBTC/USDC TWAP price should be non-zero");

        // Expected: if WBTC is token0, price = USDC per WBTC ~ 100,000 * 1e18
        // If USDC is token0, price = WBTC per USDC ~ 0.00001 * 1e18 = 1e13
        if (t0 == address(wbtc)) {
            // Price should be around 100,000 * 1e18 (with some tolerance for rounding)
            assertGt(price, 90_000e18, "WBTC price should be > 90,000 USDC");
            assertLt(price, 110_000e18, "WBTC price should be < 110,000 USDC");
        } else {
            // Price should be around 0.00001 * 1e18 = 1e13
            assertGt(price, 0.000005e18, "USDC price should be > 0.000005 WBTC");
            assertLt(price, 0.00002e18, "USDC price should be < 0.00002 WBTC");
        }
    }

    function test_getTWAPPrice_BTD_USDC() public {
        // Full warmup for BTD/USDC pair
        oracle.updateIfNeeded(address(btdUsdcPair));
        vm.warp(block.timestamp + PERIOD);
        btdUsdcPair.sync();
        oracle.updateIfNeeded(address(btdUsdcPair));
        vm.warp(block.timestamp + PERIOD);
        btdUsdcPair.sync();

        // Determine token ordering
        address t0 = btdUsdcPair.token0();
        uint8 t0Decimals;
        uint8 t1Decimals;
        if (t0 == address(btd)) {
            t0Decimals = 18;
            t1Decimals = 6;
        } else {
            t0Decimals = 6;
            t1Decimals = 18;
        }

        uint256 price = oracle.getTWAPPrice(address(btdUsdcPair), t0Decimals, t1Decimals);
        assertGt(price, 0, "BTD/USDC TWAP price should be non-zero");

        // Expected: if BTD is token0, price = USDC per BTD ~ 1 * 1e18
        // If USDC is token0, price = BTD per USDC ~ 1 * 1e18
        if (t0 == address(btd)) {
            assertGt(price, 0.5e18, "BTD price should be > 0.5 USDC");
            assertLt(price, 2e18, "BTD price should be < 2 USDC");
        } else {
            assertGt(price, 0.5e18, "USDC price should be > 0.5 BTD");
            assertLt(price, 2e18, "USDC price should be < 2 BTD");
        }
    }

    // ============ needsUpdate Tests ============

    function test_needsUpdate_noObservations() public view {
        bool needs = oracle.needsUpdate(address(wbtcUsdcPair));
        assertTrue(needs, "Should need update when no observations exist");
    }

    function test_needsUpdate_justUpdated() public {
        oracle.updateIfNeeded(address(wbtcUsdcPair));

        bool needs = oracle.needsUpdate(address(wbtcUsdcPair));
        assertFalse(needs, "Should not need update immediately after an update");
    }

    function test_needsUpdate_afterPeriod() public {
        oracle.updateIfNeeded(address(wbtcUsdcPair));

        // Advance exactly PERIOD
        vm.warp(block.timestamp + PERIOD);

        bool needs = oracle.needsUpdate(address(wbtcUsdcPair));
        assertTrue(needs, "Should need update after PERIOD has elapsed");
    }

    function test_needsUpdate_justBeforePeriod() public {
        oracle.updateIfNeeded(address(wbtcUsdcPair));

        // Advance 1 second less than PERIOD
        vm.warp(block.timestamp + PERIOD - 1);

        bool needs = oracle.needsUpdate(address(wbtcUsdcPair));
        assertFalse(needs, "Should not need update 1 second before PERIOD");
    }

    // ============ getObservationInfo Tests ============

    function test_getObservationInfo_empty() public view {
        (uint32 olderTs, uint32 newerTs, uint32 elapsed) =
            oracle.getObservationInfo(address(wbtcUsdcPair));

        assertEq(olderTs, 0, "Older timestamp should be 0 with no observations");
        assertEq(newerTs, 0, "Newer timestamp should be 0 with no observations");
        assertEq(elapsed, 0, "Time elapsed should be 0 with no observations");
    }

    function test_getObservationInfo_afterOneUpdate() public {
        uint32 ts1 = uint32(block.timestamp);
        oracle.updateIfNeeded(address(wbtcUsdcPair));

        (uint32 olderTs, uint32 newerTs,) =
            oracle.getObservationInfo(address(wbtcUsdcPair));

        // After first update: older=[0] is the shifted zero, newer=[1] is ts1
        assertEq(olderTs, 0, "Older should be 0 after first update (shifted from default)");
        assertEq(newerTs, ts1, "Newer should match first update timestamp");
    }

    function test_getObservationInfo_afterTwoUpdates() public {
        uint256 t1 = 2_000_000;
        vm.warp(t1);
        oracle.updateIfNeeded(address(wbtcUsdcPair));

        uint256 t2 = t1 + PERIOD;
        vm.warp(t2);
        wbtcUsdcPair.sync();
        oracle.updateIfNeeded(address(wbtcUsdcPair));

        (uint32 olderTs, uint32 newerTs, uint32 elapsed) =
            oracle.getObservationInfo(address(wbtcUsdcPair));

        assertEq(uint256(olderTs), t1, "Older should be first update timestamp");
        assertEq(uint256(newerTs), t2, "Newer should be second update timestamp");
        assertEq(uint256(elapsed), t2 - t1, "Elapsed should be difference between updates");
        assertEq(uint256(elapsed), PERIOD, "Elapsed should equal PERIOD");
    }

    // ============ PERIOD Constant Test ============

    function test_period_is_30_minutes() public view {
        assertEq(oracle.PERIOD(), 30 minutes, "PERIOD should be 30 minutes");
    }

    // ============ Event Emission Test ============

    function test_updateIfNeeded_emitsEvent() public {
        vm.expectEmit(true, false, false, false);
        emit UniswapV2TWAPOracle.ObservationUpdated(
            address(wbtcUsdcPair), 0, 0, 0
        );

        oracle.updateIfNeeded(address(wbtcUsdcPair));
    }
}
