// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "../../contracts/IdealUSDManager.sol";
import "../../contracts/ConfigGov.sol";
import "../../contracts/local/MockAggregatorV3.sol";
import "../../contracts/libraries/Constants.sol";
import "../helpers/ProxyTestHelper.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

interface Vm {
    function warp(uint256 newTimestamp) external;
}

contract IdealUSDManagerCoreTest {
    uint256 constant INITIAL_IUSD = 1e18;
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testUpdateIUSDFlow() public {
        MockAggregatorV3 pce = new MockAggregatorV3(int256(300_00_000_000)); // 300, 8 decimals

        // Deploy ConfigGov via proxy and set PCE Feed
        ConfigGov configGov = ProxyTestHelper.deployConfigGov(address(this));
        configGov.setAddressParam(ConfigGov.AddressParamType.PceFeed, address(pce));

        // Deploy IdealUSDManager via proxy
        IdealUSDManager mgr = ProxyTestHelper.deployIdealUSDManager(
            address(this),      // owner
            address(configGov), // configGov
            INITIAL_IUSD        // initialIUSD
        );

        // Advance time past cooldown before first update
        vm.warp(30 days);
        pce.setAnswer(int256(300_00_000_000));
        mgr.updateIUSD();
        uint256 afterFirst = mgr.getCurrentIUSD();
        require(afterFirst < INITIAL_IUSD, "should decrease when PCE lower");

        // Advance time past cooldown before second update
        vm.warp(60 days);
        pce.setAnswer(int256(303_00_000_000)); // +1%
        mgr.updateIUSD();
        uint256 afterSecond = mgr.getCurrentIUSD();
        require(afterSecond > afterFirst, "should increase when PCE up");
    }

    function testInflationParametersFromConstants() public {
        MockAggregatorV3 pce = new MockAggregatorV3(int256(300_00_000_000));

        ConfigGov configGov = ProxyTestHelper.deployConfigGov(address(this));
        configGov.setAddressParam(ConfigGov.AddressParamType.PceFeed, address(pce));

        IdealUSDManager mgr = ProxyTestHelper.deployIdealUSDManager(
            address(this),
            address(configGov),
            INITIAL_IUSD
        );

        // Verify inflation parameters come from Constants library (fixed at 2%)
        (uint256 annual, uint256 monthlyFactor) = mgr.getInflationParameters();
        require(annual == Constants.ANNUAL_INFLATION_RATE, "rate should be 2%");
        require(annual == 2e16, "rate should be exactly 2e16");
        require(monthlyFactor == Constants.MONTHLY_GROWTH_FACTOR, "factor mismatch");
        require(monthlyFactor == 1_001651581301920174, "factor should be exact value");
    }

    function testPCEFeedFromConfigGov() public {
        MockAggregatorV3 pce = new MockAggregatorV3(int256(300_00_000_000));

        ConfigGov configGov = ProxyTestHelper.deployConfigGov(address(this));
        configGov.setAddressParam(ConfigGov.AddressParamType.PceFeed, address(pce));

        IdealUSDManager mgr = ProxyTestHelper.deployIdealUSDManager(
            address(this),
            address(configGov),
            INITIAL_IUSD
        );

        // Verify PCE feed address comes from ConfigGov
        require(address(mgr.pceFeed()) == address(pce), "pce feed mismatch");
        require(mgr.pceFeedDecimals() == 8, "pce decimals should be 8");
    }

    function testInitializeValidation() public {
        MockAggregatorV3 pce = new MockAggregatorV3(int256(300_00_000_000));
        IdealUSDManager impl = new IdealUSDManager();

        // Test invalid ConfigGov (zero address)
        bool reverted1;
        try new ERC1967Proxy(
            address(impl),
            abi.encodeCall(IdealUSDManager.initialize, (address(this), address(0), INITIAL_IUSD))
        ) {
        } catch {
            reverted1 = true;
        }
        require(reverted1, "should reject zero ConfigGov");

        // Test ConfigGov without PCE Feed set
        ConfigGov emptyConfigGov = ProxyTestHelper.deployConfigGov(address(this));
        bool reverted2;
        try new ERC1967Proxy(
            address(impl),
            abi.encodeCall(IdealUSDManager.initialize, (address(this), address(emptyConfigGov), INITIAL_IUSD))
        ) {
        } catch {
            reverted2 = true;
        }
        require(reverted2, "should reject ConfigGov without PCE Feed");

        // Test zero initial IUSD
        ConfigGov configGov = ProxyTestHelper.deployConfigGov(address(this));
        configGov.setAddressParam(ConfigGov.AddressParamType.PceFeed, address(pce));
        bool reverted3;
        try new ERC1967Proxy(
            address(impl),
            abi.encodeCall(IdealUSDManager.initialize, (address(this), address(configGov), 0))
        ) {
        } catch {
            reverted3 = true;
        }
        require(reverted3, "should reject zero initial IUSD");
    }

    function testManualIUSDSetWithSafety() public {
        MockAggregatorV3 pce = new MockAggregatorV3(int256(300_00_000_000));

        ConfigGov configGov = ProxyTestHelper.deployConfigGov(address(this));
        configGov.setAddressParam(ConfigGov.AddressParamType.PceFeed, address(pce));

        IdealUSDManager mgr = ProxyTestHelper.deployIdealUSDManager(
            address(this),
            address(configGov),
            INITIAL_IUSD
        );

        // Manual override within 5% should work
        uint256 newValue = INITIAL_IUSD * 103 / 100; // +3%
        mgr.setIUSDValue(newValue, "emergency adjustment");
        require(mgr.getCurrentIUSD() == newValue, "should set new value");

        // Manual override >5% should fail
        bool reverted;
        uint256 tooHighValue = INITIAL_IUSD * 110 / 100; // +10% > 5% max
        try mgr.setIUSDValue(tooHighValue, "too large adjustment") {
        } catch {
            reverted = true;
        }
        require(reverted, "should reject >5% deviation");
    }

    function testAuthorizerWhitelist() public {
        MockAggregatorV3 pce = new MockAggregatorV3(int256(300_00_000_000));

        ConfigGov configGov = ProxyTestHelper.deployConfigGov(address(this));
        configGov.setAddressParam(ConfigGov.AddressParamType.PceFeed, address(pce));

        IdealUSDManager mgr = ProxyTestHelper.deployIdealUSDManager(
            address(this),
            address(configGov),
            INITIAL_IUSD
        );

        address newUpdater = address(0x1234);

        // Enable whitelist
        mgr.setUpdaterWhitelistEnabled(true);

        // Authorize new updater
        mgr.setUpdaterAuthorization(newUpdater, true);
        require(mgr.authorizedUpdaters(newUpdater), "should be authorized");

        // Revoke authorization
        mgr.setUpdaterAuthorization(newUpdater, false);
        require(!mgr.authorizedUpdaters(newUpdater), "should be revoked");
    }

    function testPCEDeviationLimit() public {
        MockAggregatorV3 pce = new MockAggregatorV3(int256(300_00_000_000)); // 300, 8 decimals

        ConfigGov configGov = ProxyTestHelper.deployConfigGov(address(this));
        configGov.setAddressParam(ConfigGov.AddressParamType.PceFeed, address(pce));

        // Set PCE max deviation to 2% (2e16)
        configGov.setParam(ConfigGov.ParamType.PceMaxDeviation, 2e16);

        IdealUSDManager mgr = ProxyTestHelper.deployIdealUSDManager(
            address(this),
            address(configGov),
            INITIAL_IUSD
        );

        // First update establishes baseline
        vm.warp(30 days);
        pce.setAnswer(int256(300_00_000_000));
        mgr.updateIUSD();

        // Change PCE by 1.5% (within 2% limit) - should succeed
        vm.warp(60 days);
        pce.setAnswer(int256(304_50_000_000)); // 300 * 1.015 = 304.5
        mgr.updateIUSD();
        require(mgr.getCurrentIUSD() > 0, "should update successfully");

        // Change PCE by 3% (exceeds 2% limit) - should fail
        vm.warp(90 days);
        pce.setAnswer(int256(313_64_000_000)); // 304.5 * 1.03 = 313.64
        bool reverted;
        try mgr.updateIUSD() {
        } catch {
            reverted = true;
        }
        require(reverted, "should reject PCE change > 2%");

        // Set max deviation to 10% (maximum allowed by ConfigGov)
        configGov.setParam(ConfigGov.ParamType.PceMaxDeviation, 1e17);

        // Now larger change should succeed (within 10% limit)
        // Previous successful PCE was 304.5, so 9% increase = 331.9
        pce.setAnswer(int256(331_90_000_000)); // 304.5 * 1.09 = 331.9
        mgr.updateIUSD();
        require(mgr.getCurrentIUSD() > 0, "should succeed with higher limit");
    }
}
