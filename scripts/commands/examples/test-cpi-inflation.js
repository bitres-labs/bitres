/**
 * Example Command: Test CPI Random Annual Inflation Rate Mechanism
 *
 * Usage:
 *   node scripts/CommandExecutor.js commands/examples/test-cpi-inflation.js
 */

module.exports = async function(context) {
    const { priceFeeds, timeManager } = context;

    console.log("\n" + "=".repeat(80));
    console.log("📊 Testing CPI Random Annual Inflation Rate Mechanism");
    console.log("=".repeat(80));

    console.log("\n💡 Description:");
    console.log("   Each monthly CPI update, the system randomly generates 1%-5% annual inflation rate");
    console.log("   Then automatically converts to monthly inflation rate and applies to CPI calculation");
    console.log("");

    // Record initial CPI
    const initialPrices = priceFeeds.getCurrentPrices();
    console.log(`📌 Initial State:`);
    console.log(`   CPI: ${initialPrices.cpiFormatted} (${initialPrices.cpi})`);
    console.log(`   Annual Inflation Rate: ${initialPrices.inflationFormatted}`);
    console.log("");

    // Advance 12 months, observe monthly inflation rate changes
    console.log(`⏰ Advancing 12 months, observing monthly CPI and inflation rate changes:\n`);

    const monthlyData = [];

    for (let month = 1; month <= 12; month++) {
        console.log(`\n📅 Month ${month}:`);

        // Advance 30 days (1 month)
        await timeManager.advanceDays(30);

        // This triggers CPI update and displays new annual inflation rate
        await priceFeeds.updatePricesForTime(30);

        // Get updated prices
        const currentPrices = priceFeeds.getCurrentPrices();

        // Calculate CPI growth
        const previousCPI = monthlyData.length > 0
            ? monthlyData[monthlyData.length - 1].cpi
            : initialPrices.cpi;
        const cpiGrowth = ((currentPrices.cpi - previousCPI) / previousCPI * 100).toFixed(3);

        console.log(`   CPI: ${currentPrices.cpiFormatted} (Growth: ${cpiGrowth}%)`);

        // Save data
        monthlyData.push({
            month: month,
            cpi: currentPrices.cpi,
            annualInflation: currentPrices.annualInflation,
            monthlyGrowth: parseFloat(cpiGrowth)
        });
    }

    // Statistical analysis
    console.log("\n" + "=".repeat(80));
    console.log("📈 12-Month Statistical Analysis");
    console.log("=".repeat(80));

    const inflationRates = monthlyData.map(d => d.annualInflation * 100);
    const avgInflation = inflationRates.reduce((a, b) => a + b, 0) / inflationRates.length;
    const minInflation = Math.min(...inflationRates);
    const maxInflation = Math.max(...inflationRates);

    const finalPrices = priceFeeds.getCurrentPrices();
    const totalCPIGrowth = ((finalPrices.cpi - initialPrices.cpi) / initialPrices.cpi * 100).toFixed(2);

    console.log(`\n📊 CPI Changes:`);
    console.log(`   Initial CPI: ${initialPrices.cpiFormatted}`);
    console.log(`   Final CPI: ${finalPrices.cpiFormatted}`);
    console.log(`   Total Growth: ${totalCPIGrowth}%`);

    console.log(`\n📊 Annual Inflation Rate Statistics:`);
    console.log(`   Average: ${avgInflation.toFixed(2)}%`);
    console.log(`   Minimum: ${minInflation.toFixed(2)}%`);
    console.log(`   Maximum: ${maxInflation.toFixed(2)}%`);
    console.log(`   Standard Deviation: ${calculateStdDev(inflationRates).toFixed(2)}%`);

    console.log(`\n📋 Monthly Detailed Data:`);
    console.log(`   Month | Annual Inflation | Monthly Growth | CPI Value`);
    console.log(`   ` + "-".repeat(50));
    monthlyData.forEach(d => {
        console.log(`   ${d.month.toString().padStart(2)}    | ${(d.annualInflation * 100).toFixed(2)}%`.padEnd(20) +
                    `| ${d.monthlyGrowth.toFixed(3)}%`.padEnd(15) +
                    `| ${(d.cpi / 1e6).toFixed(3)}`);
    });

    console.log("\n" + "=".repeat(80));
    console.log("✅ CPI random inflation rate test complete!");
    console.log("=".repeat(80) + "\n");

    return {
        initialCPI: initialPrices.cpi,
        finalCPI: finalPrices.cpi,
        totalGrowth: totalCPIGrowth,
        avgInflation: avgInflation.toFixed(2),
        minInflation: minInflation.toFixed(2),
        maxInflation: maxInflation.toFixed(2),
        monthlyData: monthlyData
    };
};

// Helper function: Calculate standard deviation
function calculateStdDev(values) {
    const avg = values.reduce((a, b) => a + b, 0) / values.length;
    const squareDiffs = values.map(value => Math.pow(value - avg, 2));
    const avgSquareDiff = squareDiffs.reduce((a, b) => a + b, 0) / squareDiffs.length;
    return Math.sqrt(avgSquareDiff);
}
