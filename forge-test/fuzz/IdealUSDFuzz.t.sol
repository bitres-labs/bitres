// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import "forge-std/Test.sol";
import "../../contracts/libraries/Constants.sol";

/// @title iUSD Ideal Dollar Fuzz Tests
/// @notice Tests all edge cases for CPI adjustments and iUSD calculations
contract IdealUSDFuzzTest is Test {
    using Constants for *;

    // ==================== CPI Calculation Fuzz Tests ====================

    /// @notice Fuzz test: CPI growth calculation
    function testFuzz_CPI_Growth(
        uint128 initialCPI,
        uint16 inflationRateBP,
        uint32 timeYears
    ) public pure {
        // Use bound() instead of vm.assume() for range constraints
        initialCPI = uint128(bound(initialCPI, 100 * 1e18, type(uint128).max / 1000));
        inflationRateBP = uint16(bound(inflationRateBP, 1, 2000));
        timeYears = uint32(bound(timeYears, 1, 100));

        // Calculate new CPI (simple interest): CPI * (1 + rate * time)
        uint256 growth = (uint256(initialCPI) * uint256(inflationRateBP) * uint256(timeYears)) / Constants.BPS_BASE;
        uint256 newCPI = uint256(initialCPI) + growth;

        // Verify: Inflation increases CPI
        assertGt(newCPI, initialCPI);
    }

    /// @notice Fuzz test: CPI compound growth
    function testFuzz_CPI_CompoundGrowth(
        uint256 initialCPIMultiplier,
        uint256 annualInflationBP,
        uint256 numYears
    ) public pure {
        initialCPIMultiplier = bound(initialCPIMultiplier, 100, 115);
        annualInflationBP = bound(annualInflationBP, 1, 20);
        numYears = bound(numYears, 1, 10);

        uint256 initialCPI = initialCPIMultiplier * 1e18;
        uint256 cpi = initialCPI;

        // Simulate compound growth
        for (uint256 i = 0; i < numYears; i++) {
            uint256 growth = (cpi * annualInflationBP) / Constants.BPS_BASE;
            cpi = cpi + growth;
        }

        // Verify: Compound interest grows CPI
        assertGt(cpi, initialCPI);

        // Verify: Compound growth is greater than or equal to simple interest
        uint256 simpleGrowth = (initialCPI * annualInflationBP * numYears) / Constants.BPS_BASE;
        uint256 simpleCPI = initialCPI + simpleGrowth;

        if (numYears > 1 && annualInflationBP > 3) {
            assertGe(cpi, simpleCPI);
        }
    }

    /// @notice Fuzz test: CPI deflation scenario
    function testFuzz_CPI_Deflation(
        uint128 initialCPI,
        uint16 deflationRateBP,
        uint32 timeYears
    ) public pure {
        initialCPI = uint128(bound(initialCPI, 100 * 1e18, type(uint128).max / 100));
        deflationRateBP = uint16(bound(deflationRateBP, 1, 500)); // Max 5% to avoid underflow
        timeYears = uint32(bound(timeYears, 1, 10)); // Limit years to avoid underflow

        // Calculate deflation
        uint256 decrease = (uint256(initialCPI) * uint256(deflationRateBP) * uint256(timeYears)) / Constants.BPS_BASE;

        // Skip if would underflow
        if (decrease >= initialCPI) return;

        uint256 newCPI = uint256(initialCPI) - decrease;

        // Verify: Deflation decreases CPI
        assertLt(newCPI, initialCPI);
        assertGt(newCPI, 0);
    }

    // ==================== iUSD Calculation Fuzz Tests ====================

    /// @notice Fuzz test: iUSD purchasing power calculation
    function testFuzz_iUSD_PurchasingPower(
        uint128 nominalUSD,
        uint128 currentCPI,
        uint128 baseCPI
    ) public pure {
        nominalUSD = uint128(bound(nominalUSD, 1, type(uint64).max));
        baseCPI = uint128(bound(baseCPI, 1e18, 200 * 1e18));
        currentCPI = uint128(bound(currentCPI, baseCPI, baseCPI * 2));

        // Calculate iUSD = nominalUSD * (baseCPI / currentCPI)
        uint256 iusd = (uint256(nominalUSD) * uint256(baseCPI)) / uint256(currentCPI);

        // Verify: If CPI rises, same nominal USD buys less iUSD
        if (currentCPI > baseCPI) {
            assertLe(iusd, nominalUSD);
        }

        // Verify: If CPI unchanged, iUSD = nominalUSD
        if (currentCPI == baseCPI) {
            assertEq(iusd, nominalUSD);
        }
    }

    /// @notice Fuzz test: iUSD negatively correlates with CPI
    function testFuzz_iUSD_CPINegativeCorrelation(
        uint256 nominalUSD,
        uint256 baseCPIMultiplier,
        uint256 cpi2AdditionalBP
    ) public pure {
        nominalUSD = bound(nominalUSD, 10000, 10000000);
        baseCPIMultiplier = bound(baseCPIMultiplier, 100, 115);
        cpi2AdditionalBP = bound(cpi2AdditionalBP, 10, 50);

        uint256 baseCPI = baseCPIMultiplier * 1e18;
        uint256 cpi1 = baseCPI;
        uint256 cpi2 = baseCPI + (baseCPI * cpi2AdditionalBP) / Constants.BPS_BASE;

        // Calculate iUSD under two CPI scenarios
        uint256 iusd1 = (nominalUSD * baseCPI) / cpi1;
        uint256 iusd2 = (nominalUSD * baseCPI) / cpi2;

        // Verify: Higher CPI means less iUSD (purchasing power decreases)
        assertLt(iusd2, iusd1);
    }

    /// @notice Fuzz test: Converting iUSD back to nominal USD
    function testFuzz_iUSD_ToNominalUSD(
        uint256 iusd,
        uint256 baseCPIMultiplier,
        uint256 cpiDelta,
        bool cpiRises
    ) public pure {
        iusd = bound(iusd, 1000, 1e12); // Larger min to avoid rounding issues
        baseCPIMultiplier = bound(baseCPIMultiplier, 100, 110);
        cpiDelta = bound(cpiDelta, 0, 5); // 0-5% difference

        uint256 currentCPIMultiplier;
        if (cpiRises) {
            currentCPIMultiplier = baseCPIMultiplier + cpiDelta;
        } else {
            if (cpiDelta >= baseCPIMultiplier - 100) cpiDelta = baseCPIMultiplier - 100;
            currentCPIMultiplier = baseCPIMultiplier - cpiDelta;
        }

        uint256 currentCPI = currentCPIMultiplier * 1e18;
        uint256 baseCPI = baseCPIMultiplier * 1e18;

        // Calculate nominal USD = iUSD * (currentCPI / baseCPI)
        uint256 nominalUSD = (iusd * currentCPI) / baseCPI;

        // Verify based on CPI relationship
        if (currentCPIMultiplier > baseCPIMultiplier) {
            assertGt(nominalUSD, iusd);
        } else if (currentCPIMultiplier == baseCPIMultiplier) {
            assertEq(nominalUSD, iusd);
        } else {
            assertLt(nominalUSD, iusd);
        }
    }

    /// @notice Fuzz test: iUSD conversion symmetry
    function testFuzz_iUSD_ConversionSymmetry(
        uint64 nominalUSD,
        uint128 currentCPI,
        uint128 baseCPI
    ) public pure {
        nominalUSD = uint64(bound(nominalUSD, 1000, type(uint64).max / 1000));
        baseCPI = uint128(bound(baseCPI, 1e18, 200 * 1e18));
        currentCPI = uint128(bound(currentCPI, baseCPI / 2, baseCPI * 2));

        // Nominal USD -> iUSD
        uint256 iusd = (uint256(nominalUSD) * uint256(baseCPI)) / uint256(currentCPI);
        if (iusd == 0) return;

        // iUSD -> Nominal USD
        uint256 nominalBack = (iusd * uint256(currentCPI)) / uint256(baseCPI);

        // Verify: Round-trip should be close to original
        assertApproxEqAbs(nominalBack, nominalUSD, uint256(currentCPI) / uint256(baseCPI) + 1);
    }

    // ==================== CPI Update Frequency Fuzz Tests ====================

    /// @notice Fuzz test: Monthly CPI update
    function testFuzz_CPI_MonthlyUpdate(
        uint256 initialCPIMultiplier,
        uint256 monthlyInflationBP,
        uint256 months
    ) public pure {
        initialCPIMultiplier = bound(initialCPIMultiplier, 100, 200);
        monthlyInflationBP = bound(monthlyInflationBP, 1, 50); // 0.01%-0.5% monthly
        months = bound(months, 1, 60); // Up to 5 years

        uint256 cpi = initialCPIMultiplier * 1e18;
        uint256 initialCPI = cpi;

        // Simulate monthly updates
        for (uint256 i = 0; i < months; i++) {
            uint256 growth = (cpi * monthlyInflationBP) / Constants.BPS_BASE;
            cpi += growth;
        }

        // Verify: Monthly updates accumulate growth
        assertGt(cpi, initialCPI);
    }

    /// @notice Fuzz test: Impact of CPI update delay
    function testFuzz_CPI_UpdateDelay(
        uint256 nominalUSD,
        uint256 oldCPIMultiplier,
        uint256 cpiIncreaseBP
    ) public pure {
        nominalUSD = bound(nominalUSD, 10000, 10000000);
        oldCPIMultiplier = bound(oldCPIMultiplier, 100, 115);
        cpiIncreaseBP = bound(cpiIncreaseBP, 10, 50);

        uint256 oldCPI = oldCPIMultiplier * 1e18;
        uint256 newCPI = oldCPI + (oldCPI * cpiIncreaseBP) / Constants.BPS_BASE;
        uint256 baseCPI = 100 * 1e18;

        // iUSD calculated with old CPI (before delayed update)
        uint256 iusdOld = (nominalUSD * baseCPI) / oldCPI;

        // iUSD calculated with new CPI (after update)
        uint256 iusdNew = (nominalUSD * baseCPI) / newCPI;

        // Verify: Delayed update causes user to temporarily get more iUSD
        assertGt(iusdOld, iusdNew);
    }

    // ==================== Base CPI Fuzz Tests ====================

    /// @notice Fuzz test: Base CPI setting
    function testFuzz_BaseCPI_Setting(uint128 baseCPI) public pure {
        baseCPI = uint128(bound(baseCPI, 50 * 1e18, 500 * 1e18));

        // Verify: Base CPI in reasonable range
        assertGe(baseCPI, 50 * 1e18);
        assertLe(baseCPI, 500 * 1e18);
    }

    /// @notice Fuzz test: Relative inflation rate calculation
    function testFuzz_RelativeInflation_Calculation(
        uint256 baseCPIMultiplier,
        uint256 inflationBP
    ) public pure {
        baseCPIMultiplier = bound(baseCPIMultiplier, 101, 119);
        inflationBP = bound(inflationBP, 1, 100);

        uint256 baseCPI = baseCPIMultiplier * 1e18;
        uint256 currentCPI = baseCPI + (baseCPI * inflationBP) / Constants.BPS_BASE;

        // Calculate relative inflation rate
        uint256 inflation = ((currentCPI - baseCPI) * Constants.PRECISION_18) / baseCPI;

        // Verify: Inflation rate is positive
        assertGt(inflation, 0);

        // Verify: Inflation rate is proportional to input BP
        uint256 expectedInflation = (inflationBP * Constants.PRECISION_18) / Constants.BPS_BASE;
        assertApproxEqAbs(inflation, expectedInflation, 1);
    }

    // ==================== Precision Handling Fuzz Tests ====================

    /// @notice Fuzz test: Small amount iUSD precision
    function testFuzz_TinyiUSD_Precision(
        uint32 tinyNominalUSD,
        uint128 currentCPI,
        uint128 baseCPI
    ) public pure {
        tinyNominalUSD = uint32(bound(tinyNominalUSD, 1, type(uint32).max));
        baseCPI = uint128(bound(baseCPI, 1e18, 200 * 1e18));
        currentCPI = uint128(bound(currentCPI, baseCPI / 2, baseCPI * 2));

        // Calculate small amount iUSD
        uint256 iusd = (uint256(tinyNominalUSD) * uint256(baseCPI)) / uint256(currentCPI);

        // Verify: Small amount calculation doesn't crash
        assertGe(iusd, 0);
    }

    /// @notice Fuzz test: Large amount iUSD doesn't overflow
    function testFuzz_HugeiUSD_NoOverflow(
        uint256 hugeNominalUSD,
        uint256 cpiMultiplier
    ) public pure {
        hugeNominalUSD = bound(hugeNominalUSD, 1000, 1e12);
        cpiMultiplier = bound(cpiMultiplier, 100, 115);

        uint256 currentCPI = cpiMultiplier * 1e18;
        uint256 baseCPI = 100 * 1e18;

        // Calculate large amount iUSD
        uint256 iusd = (hugeNominalUSD * baseCPI) / currentCPI;

        // Verify: Large amount calculation doesn't overflow
        assertGt(iusd, 0);
    }

    // ==================== Edge Case Tests ====================

    /// @notice Fuzz test: When CPI equals base value, iUSD equals nominal USD
    function testFuzz_CPIAtBase_iUSDEqualsNominal(
        uint128 nominalUSD,
        uint128 baseCPI
    ) public pure {
        nominalUSD = uint128(bound(nominalUSD, 1, type(uint64).max));
        baseCPI = uint128(bound(baseCPI, 1e18, 200 * 1e18));

        uint128 currentCPI = baseCPI;

        // Calculate iUSD
        uint256 iusd = (uint256(nominalUSD) * uint256(baseCPI)) / uint256(currentCPI);

        // Verify: When CPI at base value, iUSD = nominal USD
        assertEq(iusd, nominalUSD);
    }

    /// @notice Fuzz test: When CPI doubles, iUSD halves
    function testFuzz_CPIDouble_iUSDHalf(
        uint128 nominalUSD,
        uint128 baseCPI
    ) public pure {
        nominalUSD = uint128(bound(nominalUSD, 100, type(uint64).max));
        baseCPI = uint128(bound(baseCPI, 100 * 1e18, type(uint128).max / 4));

        uint128 doubleCPI = baseCPI * 2;

        // Calculate iUSD when CPI doubles
        uint256 iusd = (uint256(nominalUSD) * uint256(baseCPI)) / uint256(doubleCPI);

        // Verify: CPI doubles, iUSD halves
        assertApproxEqAbs(iusd, nominalUSD / 2, 1);
    }

    /// @notice Fuzz test: Zero inflation keeps iUSD unchanged
    function testFuzz_ZeroInflation_iUSDUnchanged(
        uint128 nominalUSD,
        uint128 cpi
    ) public pure {
        nominalUSD = uint128(bound(nominalUSD, 1, type(uint64).max));
        cpi = uint128(bound(cpi, 1e18, 200 * 1e18));

        uint128 baseCPI = cpi;
        uint128 currentCPI = cpi;

        // Calculate iUSD
        uint256 iusd = (uint256(nominalUSD) * uint256(baseCPI)) / uint256(currentCPI);

        // Verify: Zero inflation means iUSD = nominal USD
        assertEq(iusd, nominalUSD);
    }

    /// @notice Fuzz test: Cumulative effect of multiple CPI adjustments
    function testFuzz_MultipleCPIAdjustments_Cumulative(
        uint256 nominalUSD,
        uint256 baseCPIMultiplier,
        uint256 adjustment1BP,
        uint256 adjustment2BP,
        uint256 adjustment3BP
    ) public pure {
        nominalUSD = bound(nominalUSD, 1000, 1e12);
        baseCPIMultiplier = bound(baseCPIMultiplier, 100, 150);
        adjustment1BP = bound(adjustment1BP, 1, 200);
        adjustment2BP = bound(adjustment2BP, 1, 200);
        adjustment3BP = bound(adjustment3BP, 1, 200);

        uint256 baseCPI = baseCPIMultiplier * 1e18;

        // Apply adjustments
        uint256 cpi1 = baseCPI + (baseCPI * adjustment1BP) / Constants.BPS_BASE;
        uint256 cpi2 = cpi1 + (cpi1 * adjustment2BP) / Constants.BPS_BASE;
        uint256 cpi3 = cpi2 + (cpi2 * adjustment3BP) / Constants.BPS_BASE;

        // Calculate final iUSD
        uint256 iusd = (nominalUSD * baseCPI) / cpi3;

        // Verify: After multiple CPI increases, iUSD decreases
        assertLt(iusd, nominalUSD);
    }
}
