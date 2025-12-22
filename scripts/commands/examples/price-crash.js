/**
 * Example Command: Simulate BTC Price Crash
 *
 * Usage:
 *   node scripts/CommandExecutor.js commands/examples/price-crash.js
 */

module.exports = async function(context) {
    const { contracts, priceFeeds, utils } = context;

    console.log("\n" + "=".repeat(80));
    console.log("⚠️  Simulating Price Crash Scenario");
    console.log("=".repeat(80));

    // 1. Record pre-crash state
    const pricesBefore = priceFeeds.getCurrentPrices();
    const crBefore = await contracts.minter.getCollateralRatio();

    console.log(`\n1️⃣  Pre-Crash State:`);
    console.log(`   BTC Price: $${pricesBefore.btc.toLocaleString()}`);
    console.log(`   Collateral Ratio: ${utils.formatEther(crBefore)}x (${(Number(utils.formatEther(crBefore)) * 100).toFixed(2)}%)`);

    const totalBTD = await contracts.btd.totalSupply();
    const treasuryWBTC = await contracts.wbtc.balanceOf(await contracts.treasury.getAddress());

    console.log(`   BTD Total Supply: ${utils.formatEther(totalBTD)}`);
    console.log(`   Treasury WBTC: ${utils.formatUnits(treasuryWBTC, 8)}`);

    // 2. Create snapshot (for recovery)
    console.log(`\n2️⃣  Creating snapshot 'before-crash'...`);
    context.stateManager.createSnapshot('before-crash');

    // 3. Execute price crash
    const crashPercent = 40; // 40% drop
    console.log(`\n3️⃣  Executing price crash (-${crashPercent}%)...`);
    await priceFeeds.simulateCrash(crashPercent);

    // 4. View post-crash state
    const pricesAfter = priceFeeds.getCurrentPrices();
    const crAfter = await contracts.minter.getCollateralRatio();

    console.log(`\n4️⃣  Post-Crash State:`);
    console.log(`   BTC Price: $${pricesAfter.btc.toLocaleString()}`);
    console.log(`   Collateral Ratio: ${utils.formatEther(crAfter)}x (${(Number(utils.formatEther(crAfter)) * 100).toFixed(2)}%)`);

    const priceChange = ((pricesAfter.btc - pricesBefore.btc) / pricesBefore.btc * 100).toFixed(2);
    const crChange = ((Number(utils.formatEther(crAfter)) - Number(utils.formatEther(crBefore))) * 100).toFixed(2);

    console.log(`\n5️⃣  Change Statistics:`);
    console.log(`   Price Change: ${priceChange}%`);
    console.log(`   Collateral Ratio Change: ${crChange} percentage points`);

    // 6. Warning information
    if (Number(utils.formatEther(crAfter)) < 1.0) {
        console.log(`\n⚠️  Warning: System undercollateralized!`);
        console.log(`   Current CR: ${(Number(utils.formatEther(crAfter)) * 100).toFixed(2)}% < 100%`);
        console.log(`   Redeeming BTD will receive BTB bond compensation`);
    }

    console.log("\n💡 Tip: Use the following command to restore to pre-crash state:");
    console.log("   node scripts/CommandExecutor.js commands/utils/restore.js before-crash");

    console.log("\n" + "=".repeat(80));
    console.log("✅ Price crash simulation complete!");
    console.log("=".repeat(80) + "\n");

    return {
        crashPercent: crashPercent,
        priceBefore: pricesBefore.btc,
        priceAfter: pricesAfter.btc,
        crBefore: utils.formatEther(crBefore),
        crAfter: utils.formatEther(crAfter)
    };
};
