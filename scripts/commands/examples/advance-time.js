/**
 * Example Command: Advance System Time
 *
 * Usage:
 *   node scripts/CommandExecutor.js commands/examples/advance-time.js
 */

module.exports = async function(context) {
    const { timeManager, priceFeeds } = context;

    console.log("\n" + "=".repeat(80));
    console.log("⏰ Advance System Time Example");
    console.log("=".repeat(80));

    // 1. Display current time
    console.log(`\n1️⃣  Current System State:`);
    await timeManager.printStatus();

    // 2. Advance 30 days
    console.log(`\n2️⃣  Advancing 30 days...`);
    await timeManager.advanceDays(30);
    console.log(`   ✓ Time advanced by 30 days`);

    // 3. Update prices based on time elapsed
    console.log(`\n3️⃣  Updating prices based on time elapsed...`);
    await priceFeeds.updatePricesForTime(30); // 30 days

    // 4. Display new time state
    console.log(`\n4️⃣  Updated System State:`);
    await timeManager.printStatus();

    // 5. Display price changes
    const prices = priceFeeds.getCurrentPrices();
    console.log(`\n5️⃣  Current Prices:`);
    console.log(`   BTC: $${prices.btc.toLocaleString()}`);
    console.log(`   CPI: ${prices.cpiFormatted}`);
    console.log(`   FFR: ${prices.ffrFormatted}`);

    console.log("\n" + "=".repeat(80));
    console.log("✅ Time advance complete!");
    console.log("=".repeat(80) + "\n");

    return {
        daysPassed: 30,
        newPrices: prices
    };
};
