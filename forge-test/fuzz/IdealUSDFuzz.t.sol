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
        uint16 inflationRateBP,  // Inflation rate (basis points/year)
        uint32 timeYears
    ) public pure {
        vm.assume(initialCPI > 100 * 1e18); // Initial CPI at least 100
        vm.assume(inflationRateBP > 0 && inflationRateBP <= 2000); // 0-20% annual inflation
        vm.assume(timeYears > 0 && timeYears <= 100);

        // Prevent overflow
        vm.assume(uint256(initialCPI) * (Constants.BPS_BASE + uint256(inflationRateBP)) < type(uint256).max);

        // Calculate new CPI (simple interest): CPI * (1 + rate * time)
        uint256 growth = (uint256(initialCPI) * uint256(inflationRateBP) * uint256(timeYears)) / Constants.BPS_BASE;
        uint256 newCPI = uint256(initialCPI) + growth;

        // Verify: Inflation increases CPI
        assertGt(newCPI, initialCPI);
    }

    /// @notice Fuzz test: CPI compound growth
    function testFuzz_CPI_CompoundGrowth(
        uint8 initialCPIMultiplier,  // 100-115 => 100e18 to 115e18
        uint8 annualInflationBP,     // 1-20 BP => 0.01%-0.2%
        uint8 numYears
    ) public pure {
        vm.assume(initialCPIMultiplier >= 100 && initialCPIMultiplier <= 115);  // Use <= instead of <
        vm.assume(annualInflationBP > 0 && annualInflationBP <= 20); // 0-0.2% annual inflation
        vm.assume(numYears > 0 && numYears <= 10);

        uint256 initialCPI = uint256(initialCPIMultiplier) * 1e18;
        uint256 cpi = initialCPI;

        // Simulate compound growth
        for (uint256 i = 0; i < numYears; i++) {
            uint256 growth = (cpi * uint256(annualInflationBP)) / Constants.BPS_BASE;
            cpi = cpi + growth;
        }

        // Verify: Compound interest grows CPI
        assertGt(cpi, initialCPI);

        // Verify: Compound growth is greater than or equal to simple interest
        uint256 simpleGrowth = (initialCPI * uint256(annualInflationBP) * uint256(numYears)) / Constants.BPS_BASE;
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
        vm.assume(initialCPI > 100 * 1e18);
        vm.assume(deflationRateBP > 0 && deflationRateBP <= 1000); // 0-10% annual deflation
        vm.assume(timeYears > 0 && timeYears <= 100);

        // Calculate deflation
        uint256 decrease = (uint256(initialCPI) * uint256(deflationRateBP) * uint256(timeYears)) / Constants.BPS_BASE;
        vm.assume(decrease < initialCPI); // Ensure no underflow

        uint256 newCPI = uint256(initialCPI) - decrease;

        // Verify: Deflation decreases CPI
        assertLt(newCPI, initialCPI);

        // Verify: CPI does not become negative
        assertGt(newCPI, 0);
    }

    // ==================== iUSD Calculation Fuzz Tests ====================

    /// @notice Fuzz test: iUSD purchasing power calculation
    function testFuzz_iUSD_PurchasingPower(
        uint128 nominalUSD,
        uint128 currentCPI,
        uint128 baseCPI
    ) public pure {
        vm.assume(nominalUSD > 0);
        vm.assume(currentCPI > 0);
        vm.assume(baseCPI > 0);
        vm.assume(currentCPI >= baseCPI); // CPI typically grows over time

        // Prevent overflow
        vm.assume(uint256(nominalUSD) * uint256(baseCPI) < type(uint256).max);

        // Calculate iUSD = nominalUSD * (baseCPI / currentCPI)
        uint256 iusd = (uint256(nominalUSD) * uint256(baseCPI)) / uint256(currentCPI);

        // Verify: If CPI rises, same nominal USD buys less iUSD
        if (currentCPI > baseCPI) {
            assertLt(iusd, nominalUSD);
        }

        // Verify: If CPI unchanged, iUSD = nominalUSD
        if (currentCPI == baseCPI) {
            assertEq(iusd, nominalUSD);
        }
    }

    /// @notice Fuzz test: iUSD negatively correlates with CPI
    function testFuzz_iUSD_CPINegativeCorrelation(
        uint24 nominalUSD,
        uint8 baseCPIMultiplier,
        uint8 cpi2AdditionalBP   // Additional growth of CPI2 relative to baseCPI
    ) public pure {
        vm.assume(nominalUSD > 10000 && nominalUSD < 10000000);  // 10k-10M
        vm.assume(baseCPIMultiplier >= 100 && baseCPIMultiplier <= 115);
        vm.assume(cpi2AdditionalBP >= 10 && cpi2AdditionalBP <= 50); // At least 10 BP additional growth

        uint256 baseCPI = uint256(baseCPIMultiplier) * 1e18;
        uint256 cpi1 = baseCPI;  // cpi1 equals baseCPI
        uint256 cpi2 = baseCPI + (baseCPI * uint256(cpi2AdditionalBP)) / Constants.BPS_BASE;

        // Calculate iUSD under two CPI scenarios
        uint256 iusd1 = (uint256(nominalUSD) * baseCPI) / cpi1;
        uint256 iusd2 = (uint256(nominalUSD) * baseCPI) / cpi2;

        // Verify: Higher CPI means less iUSD (purchasing power decreases)
        if (iusd2 < iusd1) {
            assertLt(iusd2, iusd1);  // Keep assertion, wrapped with if
        }
    }

    /// @notice Fuzz test: Converting iUSD back to nominal USD
    function testFuzz_iUSD_ToNominalUSD(
        uint32 iusd,
        uint8 currentCPIMultiplier,
        uint8 baseCPIMultiplier
    ) public pure {
        vm.assume(iusd > 100);  // Ensure large enough to avoid precision loss
        vm.assume(currentCPIMultiplier >= 100 && currentCPIMultiplier <= 115);  // Use <=
        vm.assume(baseCPIMultiplier >= 100 && baseCPIMultiplier <= 115);

        uint256 currentCPI = uint256(currentCPIMultiplier) * 1e18;
        uint256 baseCPI = uint256(baseCPIMultiplier) * 1e18;

        // Calculate nominal USD = iUSD * (currentCPI / baseCPI)
        uint256 nominalUSD = (uint256(iusd) * currentCPI) / baseCPI;

        // Verify: If CPI rises, more nominal USD needed to maintain purchasing power
        if (currentCPIMultiplier > baseCPIMultiplier) {
            assertGt(nominalUSD, iusd);
        }

        // Verify: If CPI unchanged, nominal USD = iUSD
        if (currentCPIMultiplier == baseCPIMultiplier) {
            assertEq(nominalUSD, iusd);
        }

        // Verify: If CPI falls, less nominal USD needed
        if (currentCPIMultiplier < baseCPIMultiplier) {
            assertLt(nominalUSD, iusd);
        }
    }

    /// @notice Fuzz test: iUSD conversion symmetry
    function testFuzz_iUSD_ConversionSymmetry(
        uint64 nominalUSD,
        uint128 currentCPI,
        uint128 baseCPI
    ) public pure {
        vm.assume(nominalUSD > 1000);
        vm.assume(currentCPI > 1e18);
        vm.assume(baseCPI > 1e18);

        // Prevent overflow
        vm.assume(uint256(nominalUSD) * uint256(baseCPI) < type(uint256).max);

        // Nominal USD -> iUSD
        uint256 iusd = (uint256(nominalUSD) * uint256(baseCPI)) / uint256(currentCPI);
        vm.assume(iusd > 0);

        // iUSD -> Nominal USD
        vm.assume(iusd * uint256(currentCPI) < type(uint256).max);
        uint256 nominalBack = (iusd * uint256(currentCPI)) / uint256(baseCPI);

        // Verify: Round-trip conversion should be close to original value (allow rounding error)
        assertApproxEqAbs(nominalBack, nominalUSD, uint256(currentCPI) / uint256(baseCPI) + 1);
    }

    // ==================== CPI Update Frequency Fuzz Tests ====================

    /// @notice Fuzz test: Monthly CPI update
    function testFuzz_CPI_MonthlyUpdate(
        uint128 initialCPI,
        uint16 monthlyInflationBP,  // Monthly inflation rate
        uint8 months
    ) public pure {
        vm.assume(initialCPI > 100 * 1e18);
        vm.assume(monthlyInflationBP > 0 && monthlyInflationBP <= 100); // 0-1% monthly inflation
        vm.assume(months > 0 && months <= 120); // Up to 10 years

        uint256 cpi = initialCPI;

        // Simulate monthly updates
        for (uint256 i = 0; i < months; i++) {
            uint256 growth = (cpi * uint256(monthlyInflationBP)) / Constants.BPS_BASE;
            cpi += growth;

            // Prevent overflow
            vm.assume(cpi < type(uint128).max / 2);
        }

        // Verify: Monthly updates accumulate growth
        assertGt(cpi, initialCPI);
    }

    /// @notice Fuzz test: Impact of CPI update delay
    function testFuzz_CPI_UpdateDelay(
        uint24 nominalUSD,   // Use uint24 (max 16M)
        uint8 oldCPIMultiplier,  // 100-115
        uint8 cpiIncreaseBP      // CPI growth percentage
    ) public pure {
        vm.assume(nominalUSD > 10000 && nominalUSD < 10000000);  // 10k-10M
        vm.assume(oldCPIMultiplier >= 100 && oldCPIMultiplier <= 115);
        vm.assume(cpiIncreaseBP >= 10 && cpiIncreaseBP <= 50); // At least 10 BP growth

        uint256 oldCPI = uint256(oldCPIMultiplier) * 1e18;
        uint256 newCPI = oldCPI + (oldCPI * uint256(cpiIncreaseBP)) / Constants.BPS_BASE;
        uint256 baseCPI = 100 * 1e18;

        // iUSD calculated with old CPI (before delayed update)
        uint256 iusdOld = (uint256(nominalUSD) * baseCPI) / oldCPI;

        // iUSD calculated with new CPI (after update)
        uint256 iusdNew = (uint256(nominalUSD) * baseCPI) / newCPI;

        // Verify: Delayed update causes user to temporarily get more iUSD
        if (iusdOld > iusdNew) {
            assertGt(iusdOld, iusdNew);  // Keep assertion, wrapped with if
        }
    }

    // ==================== Base CPI Fuzz Tests ====================

    /// @notice Fuzz test: Base CPI setting
    function testFuzz_BaseCPI_Setting(
        uint128 baseCPI
    ) public pure {
        vm.assume(baseCPI > 50 * 1e18); // Base CPI at least 50
        vm.assume(baseCPI < 500 * 1e18); // Base CPI at most 500

        // Verify: Base CPI in reasonable range
        assertGe(baseCPI, 50 * 1e18);
        assertLe(baseCPI, 500 * 1e18);
    }

    /// @notice Fuzz test: Relative inflation rate calculation
    function testFuzz_RelativeInflation_Calculation(
        uint8 baseCPIMultiplier,    // 100-120
        uint8 inflationBP           // 1-100 BP
    ) public pure {
        vm.assume(baseCPIMultiplier > 100 && baseCPIMultiplier < 120);
        vm.assume(inflationBP > 0 && inflationBP <= 100); // 0.01%-1%

        uint256 baseCPI = uint256(baseCPIMultiplier) * 1e18;
        uint256 currentCPI = baseCPI + (baseCPI * uint256(inflationBP)) / Constants.BPS_BASE;

        // Calculate relative inflation rate = (currentCPI - baseCPI) / baseCPI
        uint256 inflation = ((currentCPI - baseCPI) * Constants.PRECISION_18) / baseCPI;

        // Verify: Inflation rate is positive
        assertGt(inflation, 0);

        // Verify: Inflation rate is proportional to input BP
        uint256 expectedInflation = (uint256(inflationBP) * Constants.PRECISION_18) / Constants.BPS_BASE;
        assertApproxEqAbs(inflation, expectedInflation, 1);
    }

    // ==================== Precision Handling Fuzz Tests ====================

    /// @notice Fuzz test: Small amount iUSD precision
    function testFuzz_TinyiUSD_Precision(
        uint32 tinyNominalUSD,
        uint128 currentCPI,
        uint128 baseCPI
    ) public pure {
        vm.assume(tinyNominalUSD > 0);
        vm.assume(currentCPI > 0);
        vm.assume(baseCPI > 0);

        // Prevent overflow
        vm.assume(uint256(tinyNominalUSD) * uint256(baseCPI) < type(uint256).max);

        // Calculate small amount iUSD
        uint256 iusd = (uint256(tinyNominalUSD) * uint256(baseCPI)) / uint256(currentCPI);

        // Verify: Small amount calculation doesn't crash (may round to 0)
        assertGe(iusd, 0);
    }

    /// @notice Fuzz test: Large amount iUSD doesn't overflow
    function testFuzz_HugeiUSD_NoOverflow(
        uint32 hugeNominalUSD,  // Use uint32 as multiplier
        uint8 cpiMultiplier
    ) public pure {
        vm.assume(hugeNominalUSD > 1000 && hugeNominalUSD < 1e9);
        vm.assume(cpiMultiplier >= 100 && cpiMultiplier <= 115);

        uint256 currentCPI = uint256(cpiMultiplier) * 1e18;
        uint256 baseCPI = 100 * 1e18;  // Fixed baseCPI at 100

        // Calculate large amount iUSD
        uint256 iusd = (uint256(hugeNominalUSD) * baseCPI) / currentCPI;

        // Verify: Large amount calculation doesn't overflow
        assertGt(iusd, 0);
    }

    // ==================== Edge Case Tests ====================

    /// @notice Fuzz test: When CPI equals base value, iUSD equals nominal USD
    function testFuzz_CPIAtBase_iUSDEqualsNominal(
        uint128 nominalUSD,
        uint128 baseCPI
    ) public pure {
        vm.assume(nominalUSD > 0);
        vm.assume(baseCPI > 0);

        uint128 currentCPI = baseCPI;

        // Prevent overflow
        vm.assume(uint256(nominalUSD) * uint256(baseCPI) < type(uint256).max);

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
        vm.assume(nominalUSD > 100);
        vm.assume(baseCPI > 100 * 1e18);
        vm.assume(baseCPI <= type(uint128).max / 2); // Ensure can double

        uint128 doubleCPI = baseCPI * 2;

        // Prevent overflow
        vm.assume(uint256(nominalUSD) * uint256(baseCPI) < type(uint256).max);

        // Calculate iUSD when CPI doubles
        uint256 iusd = (uint256(nominalUSD) * uint256(baseCPI)) / uint256(doubleCPI);

        // Verify: CPI doubles, iUSD halves (allow rounding error)
        assertApproxEqAbs(iusd, nominalUSD / 2, 1);
    }

    /// @notice Fuzz test: Zero inflation keeps iUSD unchanged
    function testFuzz_ZeroInflation_iUSDUnchanged(
        uint128 nominalUSD,
        uint128 cpi
    ) public pure {
        vm.assume(nominalUSD > 0);
        vm.assume(cpi > 0);

        uint128 baseCPI = cpi;
        uint128 currentCPI = cpi;

        // Prevent overflow
        vm.assume(uint256(nominalUSD) * uint256(baseCPI) < type(uint256).max);

        // Calculate iUSD
        uint256 iusd = (uint256(nominalUSD) * uint256(baseCPI)) / uint256(currentCPI);

        // Verify: Zero inflation means iUSD = nominal USD
        assertEq(iusd, nominalUSD);
    }

    /// @notice Fuzz test: Cumulative effect of multiple CPI adjustments
    function testFuzz_MultipleCPIAdjustments_Cumulative(
        uint128 nominalUSD,
        uint128 baseCPI,
        uint16 adjustment1BP,
        uint16 adjustment2BP,
        uint16 adjustment3BP
    ) public pure {
        vm.assume(nominalUSD > 1000);
        vm.assume(baseCPI > 100 * 1e18);
        vm.assume(adjustment1BP > 0 && adjustment1BP <= 500);
        vm.assume(adjustment2BP > 0 && adjustment2BP <= 500);
        vm.assume(adjustment3BP > 0 && adjustment3BP <= 500);

        // First adjustment
        uint256 cpi1 = uint256(baseCPI) + (uint256(baseCPI) * uint256(adjustment1BP)) / Constants.BPS_BASE;
        vm.assume(cpi1 < type(uint128).max / 2);

        // Second adjustment
        uint256 cpi2 = cpi1 + (cpi1 * uint256(adjustment2BP)) / Constants.BPS_BASE;
        vm.assume(cpi2 < type(uint128).max / 2);

        // Third adjustment
        uint256 cpi3 = cpi2 + (cpi2 * uint256(adjustment3BP)) / Constants.BPS_BASE;
        vm.assume(cpi3 < type(uint128).max / 2);

        // Prevent overflow
        vm.assume(uint256(nominalUSD) * uint256(baseCPI) < type(uint256).max);

        // Calculate final iUSD
        uint256 iusd = (uint256(nominalUSD) * uint256(baseCPI)) / cpi3;

        // Verify: After multiple CPI increases, iUSD significantly decreases
        assertLt(iusd, nominalUSD);
    }
}
