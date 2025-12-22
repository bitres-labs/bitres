/**
 * Utility Command: Generate Complete System Report
 *
 * Usage:
 *   node scripts/CommandExecutor.js commands/utils/report.js
 */

module.exports = async function(context) {
    const { contracts, accounts, utils, stateManager, timeManager, priceFeeds } = context;

    console.log("\n" + "=".repeat(80));
    console.log("📊 Generating System Report");
    console.log("=".repeat(80));

    const report = {
        timestamp: new Date().toISOString(),
        blockNumber: await context.ethers.provider.getBlockNumber(),
        sections: {}
    };

    // 1. Time System
    console.log(`\n1️⃣  Time System Status...`);
    const timeState = await timeManager.getState();
    report.sections.time = {
        currentTime: timeState.currentTime,
        currentBlock: timeState.currentBlock,
        elapsedSimulated: timeState.elapsedSimulatedSeconds,
        accelerationFactor: timeState.accelerationFactor
    };
    console.log(`   ✓ Current Time: ${new Date(timeState.currentTime * 1000).toISOString()}`);
    console.log(`   ✓ Current Block: ${timeState.currentBlock}`);

    // 2. Price Data
    console.log(`\n2️⃣  Price Data...`);
    const prices = priceFeeds.getCurrentPrices();
    report.sections.prices = prices;
    console.log(`   ✓ BTC: $${prices.btc.toLocaleString()}`);
    console.log(`   ✓ CPI: ${prices.cpiFormatted}`);
    console.log(`   ✓ FFR: ${prices.ffrFormatted}`);

    // 3. System Collateral Ratio
    console.log(`\n3️⃣  System Collateral Ratio...`);
    const cr = await contracts.minter.getCollateralRatio();
    const btcPrice = await contracts.priceOracle.getWBTCPrice();
    report.sections.collateral = {
        cr: utils.formatEther(cr),
        btcPrice: utils.formatUnits(btcPrice, 18)
    };
    console.log(`   ✓ CR: ${utils.formatEther(cr)}x (${(Number(utils.formatEther(cr)) * 100).toFixed(2)}%)`);

    // 4. Token Supply
    console.log(`\n4️⃣  Token Supply...`);
    const btdSupply = await contracts.btd.totalSupply();
    const btbSupply = await contracts.btb.totalSupply();
    const brsSupply = await contracts.brs.totalSupply();

    report.sections.supply = {
        btd: utils.formatEther(btdSupply),
        btb: utils.formatEther(btbSupply),
        brs: utils.formatEther(brsSupply)
    };

    console.log(`   ✓ BTD Total Supply: ${utils.formatEther(btdSupply)}`);
    console.log(`   ✓ BTB Total Supply: ${utils.formatEther(btbSupply)}`);
    console.log(`   ✓ BRS Total Supply: ${utils.formatEther(brsSupply)}`);

    // 5. Treasury Assets
    console.log(`\n5️⃣  Treasury Assets...`);
    const treasuryAddr = await contracts.treasury.getAddress();
    const treasuryWBTC = await contracts.wbtc.balanceOf(treasuryAddr);
    const treasuryBRS = await contracts.brs.balanceOf(treasuryAddr);

    report.sections.treasury = {
        wbtc: utils.formatUnits(treasuryWBTC, 8),
        brs: utils.formatEther(treasuryBRS)
    };

    console.log(`   ✓ WBTC: ${utils.formatUnits(treasuryWBTC, 8)}`);
    console.log(`   ✓ BRS: ${utils.formatEther(treasuryBRS)}`);

    // 6. Farming Pool Statistics
    console.log(`\n6️⃣  Farming Pool Statistics...`);
    report.sections.farmingPools = [];

    const poolCount = await contracts.farmingPool.poolLength();
    for (let i = 0; i < poolCount; i++) {
        const poolInfo = await contracts.farmingPool.pools(i);
        const poolData = {
            id: i,
            token: poolInfo.stakingToken,
            weight: Number(poolInfo.weight),
            totalStaked: utils.formatEther(poolInfo.totalStaked)
        };
        report.sections.farmingPools.push(poolData);
        console.log(`   Pool ${i}: Weight=${poolData.weight}, Staked=${poolData.totalStaked}`);
    }

    // 7. User Balance Statistics
    console.log(`\n7️⃣  User Balance Statistics...`);
    report.sections.users = [];

    for (let i = 0; i < Math.min(5, accounts.users.length); i++) {
        const user = accounts.users[i];
        const btd = await contracts.btd.balanceOf(user.address);
        const btb = await contracts.btb.balanceOf(user.address);
        const brs = await contracts.brs.balanceOf(user.address);
        const wbtc = await contracts.wbtc.balanceOf(user.address);

        const userData = {
            address: user.address,
            btd: utils.formatEther(btd),
            btb: utils.formatEther(btb),
            brs: utils.formatEther(brs),
            wbtc: utils.formatUnits(wbtc, 8)
        };

        report.sections.users.push(userData);

        if (Number(userData.btd) > 0 || Number(userData.btb) > 0 || Number(userData.brs) > 0) {
            console.log(`   User${i}: BTD=${userData.btd}, BTB=${userData.btb}, BRS=${userData.brs}`);
        }
    }

    // 8. Save Report
    const fs = require('fs');
    const path = require('path');
    const reportPath = path.join(__dirname, '../../reports', `report-${Date.now()}.json`);

    const reportsDir = path.dirname(reportPath);
    if (!fs.existsSync(reportsDir)) {
        fs.mkdirSync(reportsDir, { recursive: true });
    }

    fs.writeFileSync(reportPath, JSON.stringify(report, null, 2));

    console.log(`\n8️⃣  Report saved to: ${reportPath}`);

    // 9. Display Summary
    console.log("\n" + "=".repeat(80));
    console.log("📈 System Summary");
    console.log("=".repeat(80));
    console.log(`BTC Price: $${prices.btc.toLocaleString()} | CR: ${(Number(utils.formatEther(cr)) * 100).toFixed(2)}%`);
    console.log(`BTD Supply: ${utils.formatEther(btdSupply)} | BTB Supply: ${utils.formatEther(btbSupply)}`);
    console.log(`BRS Supply: ${utils.formatEther(brsSupply)} | Farming Pools: ${poolCount}`);

    console.log("\n" + "=".repeat(80));
    console.log("✅ Report generation complete!");
    console.log("=".repeat(80) + "\n");

    return {
        reportPath: reportPath,
        report: report
    };
};
